"""Loopback game ledger. The unchanged cloud v1 remains the sole identity provider."""
from __future__ import annotations
import argparse,hashlib,hmac,json,os,re,sqlite3,sys,threading,urllib.request,urllib.error
from collections import deque
from pathlib import Path
from socketserver import ThreadingMixIn
from wsgiref.simple_server import make_server,WSGIServer,WSGIRequestHandler
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from progression_ledger import ProgressionLedger,APIError

class Application:
    ACTIONS={'progression','exchange','shop-buy','equip-stat','appearance','equip-wing'}
    def __init__(self,data_dir,legacy_url,service_key,catalog_root=None):
        if not service_key or not legacy_url.startswith(('http://','https://')):raise ValueError('Explicit identity URL and service key required')
        self.legacy_url=legacy_url.rstrip('/');self.service_key=service_key
        self.ledger=ProgressionLedger(Path(data_dir)/'progression.sqlite3',catalog_root,service_key)
        self.connections={};self.retired=deque(maxlen=4096);self.lock=threading.RLock()
        self.probe()

    def cloud(self,path,token=''):
        headers={'Authorization':'Bearer '+token} if token else {}
        try:
            with urllib.request.urlopen(urllib.request.Request(self.legacy_url+path,headers=headers),timeout=6) as response:
                raw=response.read(1048577)
                if len(raw)>1048576:raise APIError(503,'身份服务响应过大。','service_unavailable')
                value=json.loads(raw)
                if not isinstance(value,dict):raise ValueError()
                return value
        except urllib.error.HTTPError as error:
            raise APIError(401 if error.code in (401,403,404) else 503,'登录失效或角色不可访问。' if error.code in (401,403,404) else '身份服务暂不可用。','unauthorized' if error.code in (401,403,404) else 'service_unavailable') from None
        except (OSError,ValueError):raise APIError(503,'身份服务暂不可用。','service_unavailable') from None

    def probe(self):
        health=self.cloud('/health')
        if health.get('service')!='academy-accounts' or int(health.get('version',0))<1:raise APIError(503,'身份服务协议不兼容。','service_unavailable')
        try:
            with urllib.request.urlopen(self.legacy_url+'/v1/me',timeout=6):pass
            raise APIError(503,'身份服务未执行鉴权。','service_unavailable')
        except urllib.error.HTTPError as error:
            if error.code!=401:raise APIError(503,'身份服务验证接口不可用。','service_unavailable') from None
        except OSError:raise APIError(503,'身份服务暂不可用。','service_unavailable') from None
        for name in ['weekend_equipment.json','weekend_treasure_economy.json','weekend_shop_catalog.json','weekend_boss_wings.json','frost_encounter_progression.json','frost_circled_encounters.json','teen_catalog.json','teen_hat_hair_catalog.json','teen_hat_hair_v2_catalog.json','teen_starweave_v1.json','teen_pink_sakura.json','teen_sailor_uniform.json','teen_hanbok.json']:self.ledger.read_catalog(name)
        versions={self.ledger.read_catalog(name).get('catalog_version') for name in ['weekend_equipment.json','weekend_treasure_economy.json','weekend_shop_catalog.json']}
        if len(versions)!=1 or None in versions:raise APIError(503,'游戏目录版本不一致。','service_unavailable')
        with self.ledger.db() as db:
            db.execute('BEGIN IMMEDIATE');db.execute('CREATE TEMP TABLE IF NOT EXISTS health_probe(value INTEGER)')
            db.execute('INSERT INTO health_probe VALUES(1)');db.rollback()
        return {'ok':True,'ready':True,'service':'game-progression','version':1,'protocol_version':2}

    def identity(self,token,cid):
        if not isinstance(token,str) or not token or len(token)>256 or '\n' in token or '\r' in token or not isinstance(cid,str) or not re.fullmatch('[0-9a-f]{32}',cid):raise APIError(401,'登录凭据无效。','unauthorized')
        account=self.cloud('/v1/me',token).get('account',{})
        remote=self.cloud('/v1/characters/'+cid,token)
        character=remote.get('character',{})
        if character.get('id')!=cid:raise APIError(403,'角色身份不匹配。','unauthorized')
        snapshot=self.ledger.bind_identity(account,character,remote.get('save',{}))
        return snapshot,str(character.get('name',''))

    def dispatch(self,env,body):
        path=env.get('PATH_INFO','');method=env.get('REQUEST_METHOD','GET')
        if path=='/health' and method=='GET':return self.probe()
        if not hmac.compare_digest(env.get('HTTP_X_ACADEMY_SERVICE_KEY',''),self.service_key):raise APIError(403,'服务凭据无效。','unauthorized')
        if method!='POST' or not path.startswith('/v1/internal/'):raise APIError(404,'接口不存在。')
        action=path.rsplit('/',1)[-1]
        if action=='probe':return self.probe()
        if action=='disconnect':
            binding=str(body.get('connection_id',''))
            with self.lock:self.connections.pop(binding,None);self.retired.append(binding)
            return {'ok':True,'code':'ok'}
        if action!='claim':
            with self.ledger.db() as db:self.check_boot(db,body)
        # Only the authenticated dedicated service calls these operations.
        if action in {'bootstrap','authenticate'}:
            snapshot,name=self.identity(body.get('token'),body.get('character_id'))
            if action=='authenticate':
                binding=self.ledger.valid_key(body.get('connection_id'))
                with self.ledger.db() as db:self.check_boot(db,body)
                with self.lock:
                    if binding in self.retired:raise APIError(401,'游戏连接已关闭。','unauthorized')
                    self.connections[binding]=(body['token'],snapshot['character_id'],snapshot['account_id'])
            return {'ok':True,'code':'ok','snapshot':snapshot,'name':name}
        if action in {'player','reserve'}:
            binding=str(body.get('connection_id',''))
            with self.lock:identity=self.connections.get(binding)
            if identity is None:raise APIError(401,'游戏连接身份已失效。','unauthorized')
            snapshot,_=self.identity(identity[0],identity[1])
            with self.lock:
                if self.connections.get(binding)!=identity:raise APIError(401,'游戏连接已关闭。','unauthorized')
            if snapshot['account_id']!=identity[2]:raise APIError(403,'账号身份改变。','unauthorized')
            if action=='reserve':
                if body.get('character_id')!=identity[1]:raise APIError(403,'角色身份不匹配。','unauthorized')
            else:
                operation=body.get('action')
                payload=body.get('payload',{})
                if operation not in self.ACTIONS or not isinstance(payload,dict):raise APIError(400,'经济操作无效。')
                with self.ledger.db() as db:
                    db.execute('BEGIN IMMEDIATE')
                    self.check_boot(db,body)
                    row=self.ledger.character_row(db,identity[1],identity[2])
                    return self.ledger.player_progression(db,row,operation,payload,'')
        if action=='redeem-ticket':raise APIError(400,'请更新游戏客户端。','client_upgrade_required')
        if action not in {'claim','recover','snapshot','reserve','consume','finish'}:raise APIError(404,'接口不存在。')
        return self.ledger.internal(env,action,body)

    def check_boot(self,db,body):
        current=db.execute('SELECT boot_id FROM island_services WHERE server_id=?',(body.get('server_id'),)).fetchone()
        if not current or current[0]!=body.get('boot_id'):raise APIError(409,'游戏进程已被替代。','revision_conflict')

    def __call__(self,env,start_response):
        status=200
        try:
            if env.get('HTTP_TRANSFER_ENCODING'):raise APIError(400,'不支持请求编码。')
            size=int(env.get('CONTENT_LENGTH') or 0)
            if size<0 or size>65536:raise APIError(413,'请求过大。')
            body=json.loads(env['wsgi.input'].read(size)) if size else {}
            if not isinstance(body,dict):raise APIError(400,'请求无效。')
            result=self.dispatch(env,body)
        except APIError as error:status=error.status;result={'ok':False,'code':error.code,'error':error.message,'snapshot':{}}
        except (ValueError,TypeError):status=400;result={'ok':False,'code':'invalid_request','snapshot':{}}
        except Exception:status=503;result={'ok':False,'code':'service_unavailable','snapshot':{}}
        payload=json.dumps(result,ensure_ascii=False,allow_nan=False).encode()
        start_response(str(status)+' '+('OK' if status==200 else 'Error'),[('Content-Type','application/json'),('Content-Length',str(len(payload))),('Cache-Control','no-store')])
        return [payload]

class BoundedServer(ThreadingMixIn,WSGIServer):
    daemon_threads=True
    def __init__(self,*args,**kwargs):self.slots=threading.BoundedSemaphore(8);super().__init__(*args,**kwargs)
    def process_request(self,request,address):
        request.settimeout(15)
        if not self.slots.acquire(False):request.close();return
        try:super().process_request(request,address)
        except BaseException:self.slots.release();raise
    def process_request_thread(self,request,address):
        try:super().process_request_thread(request,address)
        finally:self.slots.release()
class QuietHandler(WSGIRequestHandler):
    def log_message(self,*args):pass

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--host',choices=['127.0.0.1'],default='127.0.0.1');parser.add_argument('--port',type=int,default=18788)
    args=parser.parse_args();data=Path(os.environ['GAME_DATA_DIR'])
    if not data.is_absolute():raise ValueError('GAME_DATA_DIR must be absolute')
    app=Application(data,os.environ['LEGACY_ACCOUNT_SERVER_URL'],os.environ['ACADEMY_SERVICE_KEY'])
    print('GAME_PROGRESSION_READY',flush=True)
    with make_server(args.host,args.port,app,server_class=BoundedServer,handler_class=QuietHandler) as server:server.serve_forever()
if __name__=='__main__':main()
