"""Linux launcher: hold one kernel lock across the supervisor and its children.

Embedded in start.sh by the game builder; does not modify the Python runtime.
The lock file is never unlinked, so all future starts lock the same inode.
"""
import fcntl
import os
from pathlib import Path
import runpy
import subprocess
import sys


def main():
    data = Path(sys.argv[1])
    if not data.is_absolute() or data.is_symlink():
        raise RuntimeError('Expected an absolute, non-symlink game-data directory')
    data.mkdir(parents=True, exist_ok=True)
    lock_path = data / 'supervisor.lock'
    descriptor = os.open(str(lock_path), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(descriptor)
        print('GAME_SUPERVISOR_ALREADY_RUNNING', flush=True)
        return 75
    os.set_inheritable(descriptor, True)
    os.environ['ISLAND_SUPERVISOR_LOCK_FD'] = str(descriptor)
    os.environ['ISLAND_SUPERVISOR_LOCK_PATH'] = str(lock_path)
    os.environ['ISLAND_SUPERVISED_OUTBOX'] = str(data / 'outbox')
    original_popen = subprocess.Popen

    def locked_popen(*args, **kwargs):
        # Keep the lock alive even if the supervisor is killed before its children.
        kwargs['pass_fds'] = tuple(sorted(set(kwargs.get('pass_fds', ())) | {descriptor}))
        kwargs['close_fds'] = True
        return original_popen(*args, **kwargs)

    subprocess.Popen = locked_popen
    sys.argv = sys.argv[2:]
    try:
        print('GAME_SUPERVISOR_EXCLUSIVE_LOCK_READY', flush=True)
        runpy.run_path(sys.argv[0], run_name='__main__')
    finally:
        subprocess.Popen = original_popen
        os.close(descriptor)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
