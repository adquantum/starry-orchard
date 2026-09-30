"""Unified Linux/Windows supervisor for the existing account and battle services."""
import argparse, json, os, signal, subprocess, sys, time, urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parent

def healthy(url):
    try:
        with urllib.request.urlopen(url+'/health',timeout=2) as r:
            return json.load(r).get('service')=='academy-accounts'
    except (OSError,ValueError):return False

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--godot',default=os.environ.get('GODOT_BIN','godot'))
    p.add_argument('--game-project',type=Path,default=ROOT.parent/'builds/island-server')
    p.add_argument('--data',type=Path,default=ROOT/'data')
    p.add_argument('--host',default='127.0.0.1')
    p.add_argument('--account-port',type=int,default=8787)
    p.add_argument('--game-port',type=int,default=29710)
    p.add_argument('--production',action='store_true')
    p.add_argument('--reuse-accounts',action='store_true',help='Reuse an already running local account service; never stop it')
    args=p.parse_args()
    project=args.game_project.resolve()
    if not (project/'project.godot').is_file():p.error('Build the game server first: python server/game/build.py')
    children=[]
    def stop(_sig=None,_frame=None):raise KeyboardInterrupt
    signal.signal(signal.SIGTERM,stop)
    url=f'http://127.0.0.1:{args.account_port}'
    try:
        if args.reuse_accounts:
            if not healthy(url):raise RuntimeError('No compatible running account service at '+url)
            print('Reusing existing account service and its database.',flush=True)
        else:
            if healthy(url):raise RuntimeError('Account service already running. Use --reuse-accounts to retain it.')
            cmd=[sys.executable,str(ROOT/'account_server.py'),'--host',args.host,'--port',str(args.account_port),'--data',str(args.data.resolve())]
            if args.production:cmd.append('--production')
            children.append(subprocess.Popen(cmd))
            for _ in range(100):
                if children[0].poll() is not None:raise RuntimeError('Account service stopped during startup')
                if healthy(url):break
                time.sleep(.1)
            else:raise RuntimeError('Account service startup timed out')
        subprocess.run([args.godot,'--headless','--editor','--path',str(project),'--import','--quit'],check=True)
        children.append(subprocess.Popen([args.godot,'--headless','--path',str(project),'--','--port='+str(args.game_port)]))
        print(f'STAR_ORCHARD_READY accounts={args.account_port}/TCP game={args.game_port}/UDP',flush=True)
        while True:
            for child in children:
                if child.poll() is not None:raise RuntimeError('A managed service exited: '+str(child.returncode))
            time.sleep(.5)
    except KeyboardInterrupt:pass
    finally:
        for child in reversed(children):
            if child.poll() is None:child.terminate()
        for child in children:
            try:child.wait(timeout=10)
            except subprocess.TimeoutExpired:child.kill();child.wait()

if __name__=='__main__':main()
