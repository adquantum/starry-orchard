"""Small account and save API. Local runner: Python 3.11+, no extra dependencies."""
from __future__ import annotations
import argparse, hashlib, hmac, json, os, re, secrets, sqlite3, threading, time
from collections import OrderedDict, deque
from contextlib import contextmanager, closing
from pathlib import Path
from socketserver import ThreadingMixIn
from wsgiref.simple_server import WSGIServer, WSGIRequestHandler, make_server

FILES = {'fusion_3d_story.json', 'academy_chapter_one.json', 'academy_wardrobe.json', 'academy_custom_decks.json'}
SCHOOLS = ['fire', 'ice', 'storm', 'myth', 'life', 'death', 'balance']
CHARACTERS = ['fire_student', 'ice_guardian', 'storm_duelist', 'myth_scholar', 'life_healer', 'death_reaper', 'balance_adept']
MAX_BODY = 524288
ITERATIONS = 600000
SESSION_SECONDS = 7 * 86400

from progression_ledger import ProgressionLedger, APIError


def validate_save(value):
    if not isinstance(value, dict) or set(value) - FILES:
        raise APIError(400, '存档格式不正确。')
    if any(not isinstance(v, dict) for v in value.values()):
        raise APIError(400, '存档内容必须是对象。')
    if len(json.dumps(value, ensure_ascii=False).encode()) > MAX_BODY - 2048:
        raise APIError(413, '存档超过大小限制。')
    return value

def initial_save(school, gender, hair):
    lead = CHARACTERS[SCHOOLS.index(school)]
    party = [lead] + [v for v in ['ice_guardian', 'life_healer', 'storm_duelist', 'fire_student'] if v != lead][:3]
    outfit = {k: school for k in ['body', 'hat', 'robe', 'boots', 'staff', 'aura']}
    outfit.update(gender=gender, hairstyle=hair, model_style='teen')
    return {'fusion_3d_story.json': {'quest_step': 0, 'party': party},
            'academy_chapter_one.json': {'version': 1, 'step': 0, 'xp': 0, 'samples': [], 'rewards': []},
            'academy_wardrobe.json': {'version': 3, 'outfits': {school: outfit}},
            'academy_custom_decks.json': {}}

class Application(ProgressionLedger):
    account_table="accounts"
    character_table="characters"
    def legacy_presentation(self,row):return json.loads(row["save_json"])
    def __init__(self, db_path, catalog_root=None, service_key=None):
        self.db_path = str(db_path)
        self.catalog_root = Path(catalog_root) if catalog_root else Path(__file__).resolve().parent.parent/'resources/fusion_3d'
        self.service_key = service_key if service_key is not None else os.environ.get('ACADEMY_SERVICE_KEY', '')
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        self.rate_lock = threading.Lock()
        self.rates = OrderedDict()
        self.dummy_salt = secrets.token_hex(16)
        with self.db() as db:
            db.execute('PRAGMA journal_mode=WAL')
            db.executescript('''
                CREATE TABLE IF NOT EXISTS accounts(
                  id TEXT PRIMARY KEY, username TEXT UNIQUE NOT NULL, display_name TEXT NOT NULL,
                  salt TEXT NOT NULL, password_hash TEXT NOT NULL, created INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS sessions(
                  token_hash TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id), expires INTEGER NOT NULL);
                CREATE INDEX IF NOT EXISTS sessions_account ON sessions(account_id);
                CREATE TABLE IF NOT EXISTS characters(
                  id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id), name TEXT NOT NULL,
                  school TEXT NOT NULL, gender TEXT NOT NULL, hairstyle TEXT NOT NULL,
                  revision INTEGER NOT NULL DEFAULT 1, save_json TEXT NOT NULL,
                  created INTEGER NOT NULL, updated INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0);
                CREATE INDEX IF NOT EXISTS characters_account ON characters(account_id, deleted);
                CREATE TABLE IF NOT EXISTS save_history(
                  character_id TEXT NOT NULL REFERENCES characters(id), revision INTEGER NOT NULL,
                  save_json TEXT NOT NULL, created INTEGER NOT NULL, PRIMARY KEY(character_id,revision));
            ''')
            self.migrate_progression(db)
















    def rate_limit(self, key, limit):
        now = time.monotonic()
        with self.rate_lock:
            bucket = self.rates.setdefault(key, deque())
            while bucket and bucket[0] < now - 60:
                bucket.popleft()
            if len(bucket) >= limit:
                raise APIError(429, '尝试过于频繁，请稍后再试。')
            bucket.append(now)
            self.rates.move_to_end(key)
            while len(self.rates) > 2048:
                self.rates.popitem(last=False)

    @staticmethod
    def password_hash(password, salt):
        return hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), ITERATIONS).hex()

    @staticmethod
    def valid_password(password):
        if not isinstance(password, str) or not 8 <= len(password) <= 128:
            raise APIError(400, '密码需为 8–128 个字符。')

    @staticmethod
    def valid_name(name):
        if not isinstance(name, str) or not 2 <= len(name.strip()) <= 20 or any(ord(c) < 32 for c in name):
            raise APIError(400, '角色名需为 2–20 个字符。')
        return name.strip()

    def session(self, db, account):
        token = secrets.token_urlsafe(32)
        db.execute('DELETE FROM sessions WHERE expires < ?', (int(time.time()),))
        db.execute('DELETE FROM sessions WHERE account_id=? AND token_hash NOT IN (SELECT token_hash FROM sessions WHERE account_id=? ORDER BY expires DESC LIMIT 7)', (account['id'], account['id']))
        db.execute('INSERT INTO sessions VALUES(?,?,?)', (hashlib.sha256(token.encode()).hexdigest(), account['id'], int(time.time()) + SESSION_SECONDS))
        return {'token': token, 'account': {'id': account['id'], 'username': account['display_name']}}

    def authenticate(self, db, env):
        header = env.get('HTTP_AUTHORIZATION', '')
        if not header.startswith('Bearer ') or len(header) > 256:
            raise APIError(401, '请先登录账号。', 'unauthorized')
        digest = hashlib.sha256(header[7:].encode()).hexdigest()
        account = db.execute('SELECT a.* FROM accounts a JOIN sessions s ON s.account_id=a.id WHERE s.token_hash=? AND s.expires>?', (digest, int(time.time()))).fetchone()
        if not account:
            raise APIError(401, '登录已过期，请重新登录；本地进度已保留。', 'unauthorized')
        return account, digest

    @staticmethod
    def summary(row):
        data = json.loads(row['save_json'])
        chapter = data.get('academy_chapter_one.json', {})
        return {k: row[k] for k in ['id', 'name', 'school', 'gender', 'hairstyle', 'revision', 'updated']} | {'xp': chapter.get('xp', 0), 'step': chapter.get('step', 0)}

    def dispatch(self, env, body):
        path, method = env.get('PATH_INFO', ''), env['REQUEST_METHOD']
        if path == '/health' and method == 'GET':
            return {'ok': True, 'service': 'academy-accounts', 'version': 2}
        if path.startswith('/v1/internal/') and method=='POST':
            return self.internal(env,path.removeprefix('/v1/internal/'),body)
        ip = env.get('REMOTE_ADDR', 'local')
        if path in ['/v1/register', '/v1/login'] and method == 'POST':
            self.rate_limit(('auth', ip), 30)
            username, password = body.get('username'), body.get('password')
            if not isinstance(username, str) or not re.fullmatch(r'[A-Za-z0-9_]{3,24}', username):
                raise APIError(400, '账号名为 3–24 位字母、数字或下划线。')
            self.valid_password(password)
            self.rate_limit(('user', username.casefold()), 12)
            with self.db() as db:
                row = db.execute('SELECT * FROM accounts WHERE username=?', (username.casefold(),)).fetchone()
                if path.endswith('register'):
                    if row:
                        raise APIError(409, '这个账号名已被注册。')
                    salt = secrets.token_hex(16)
                    try:
                        db.execute('INSERT INTO accounts VALUES(?,?,?,?,?,?)', (secrets.token_hex(16), username.casefold(), username, salt, self.password_hash(password, salt), int(time.time())))
                    except sqlite3.IntegrityError:
                        raise APIError(409, '这个账号名已被注册。')
                    row = db.execute('SELECT * FROM accounts WHERE username=?', (username.casefold(),)).fetchone()
                else:
                    digest = self.password_hash(password, row['salt'] if row else self.dummy_salt)
                    if row is None or not hmac.compare_digest(digest, row['password_hash']):
                        raise APIError(401, '账号或密码不正确。')
                return self.session(db, row)
        with self.db() as db:
            account, token_hash = self.authenticate(db, env)
            aid = account['id']
            self.rate_limit(('api', aid), 180)
            progression_match=re.fullmatch(r'/v1/characters/([0-9a-f]{32})/(progression|island-ticket|exchange|equip-stat|appearance|equip-wing)',path)
            if progression_match:
                cid,action=progression_match.groups()
                if method!=('GET' if action=='progression' else 'POST'):raise APIError(400,'请求方法不正确。')
                db.execute('BEGIN IMMEDIATE')
                row=self.character_row(db,cid,aid)
                return self.player_progression(db,row,action,body,token_hash)
            if path == '/v1/me' and method == 'GET':
                return {'account': {'id': aid, 'username': account['display_name']}}
            if path == '/v1/logout' and method == 'POST':
                db.execute('DELETE FROM sessions WHERE token_hash=?', (token_hash,))
                return {'ok': True}
            if path == '/v1/password' and method == 'POST':
                self.rate_limit(('password', aid), 6)
                old, new = body.get('old_password'), body.get('new_password')
                self.valid_password(old); self.valid_password(new)
                if not hmac.compare_digest(self.password_hash(old, account['salt']), account['password_hash']):
                    raise APIError(403, '原密码不正确。')
                salt = secrets.token_hex(16)
                db.execute('UPDATE accounts SET salt=?,password_hash=? WHERE id=?', (salt, self.password_hash(new, salt), aid))
                db.execute('DELETE FROM sessions WHERE account_id=?', (aid,))
                return self.session(db, account)
            if path == '/v1/characters':
                if method == 'GET':
                    return {'characters': [self.summary(r) for r in db.execute('SELECT * FROM characters WHERE account_id=? AND deleted=0 ORDER BY updated DESC,id', (aid,))]}
                if method == 'POST':
                    name = self.valid_name(body.get('name'))
                    school, gender, hair = body.get('school'), body.get('gender'), body.get('hairstyle')
                    if school not in SCHOOLS or gender not in ['male', 'female'] or hair not in ['m1', 'm2', 'm3', 'm4', 'f1', 'f2', 'f3', 'f4']:
                        raise APIError(400, '请选择有效的学院、性别和发型。')
                    save = validate_save(body['save']) if 'save' in body else initial_save(school, gender, hair)
                    db.execute('BEGIN IMMEDIATE')
                    if db.execute('SELECT count(*) FROM characters WHERE account_id=? AND deleted=0', (aid,)).fetchone()[0] >= 12:
                        raise APIError(409, '每个账号最多创建 12 个角色。')
                    if db.execute('SELECT 1 FROM characters WHERE account_id=? AND name=? AND deleted=0', (aid, name)).fetchone():
                        raise APIError(409, '账号内已有同名角色。')
                    cid, now = secrets.token_hex(16), int(time.time())
                    db.execute('INSERT INTO characters VALUES(?,?,?,?,?,?,1,?,?,?,0)', (cid, aid, name, school, gender, hair, json.dumps(save, ensure_ascii=False), now, now))
                    row = db.execute('SELECT * FROM characters WHERE id=?', (cid,)).fetchone()
                    return {'character': self.summary(row), 'save': save, 'revision': 1}
            match = re.fullmatch(r'/v1/characters/([0-9a-f]{32})(/save)?', path)
            if match:
                cid, action = match.groups()
                row = db.execute('SELECT * FROM characters WHERE id=? AND account_id=? AND deleted=0', (cid, aid)).fetchone()
                if not row:
                    raise APIError(404, '找不到该角色。')
                if method == 'GET':
                    return {'character': self.summary(row), 'save': json.loads(row['save_json']), 'revision': row['revision']}
                if method == 'PUT' and action:
                    save, revision = validate_save(body.get('save')), body.get('revision')
                    if type(revision) is not int or revision < 1:
                        raise APIError(400, '缺少有效的存档版本。')
                    db.execute('BEGIN IMMEDIATE')
                    current = db.execute('SELECT * FROM characters WHERE id=? AND account_id=? AND deleted=0', (cid, aid)).fetchone()
                    if not current:
                        raise APIError(404, '找不到该角色。')
                    if current['revision'] != revision:
                        raise APIError(409, '云端已有更新的进度；请在角色管理中选择要保留的版本。', 'save_conflict')
                    db.execute('INSERT INTO save_history VALUES(?,?,?,?)', (cid, revision, current['save_json'], int(time.time())))
                    db.execute('DELETE FROM save_history WHERE character_id=? AND revision < ?', (cid, revision - 2))
                    db.execute('UPDATE characters SET save_json=?,revision=revision+1,updated=? WHERE id=?', (json.dumps(save, ensure_ascii=False), int(time.time()), cid))
                    return {'ok': True, 'revision': revision + 1}
                if method == 'PATCH' and not action:
                    name = self.valid_name(body.get('name'))
                    db.execute('BEGIN IMMEDIATE')
                    if db.execute('SELECT 1 FROM characters WHERE account_id=? AND name=? AND id<>? AND deleted=0', (aid, name, cid)).fetchone():
                        raise APIError(409, '账号内已有同名角色。')
                    db.execute('UPDATE characters SET name=?,updated=? WHERE id=?', (name, int(time.time()), cid))
                    return {'ok': True}
                if method == 'DELETE' and not action:
                    if body.get('confirm_name') != row['name']:
                        raise APIError(400, '请输入完整角色名确认删除。')
                    db.execute('BEGIN IMMEDIATE')
                    if db.execute('SELECT 1 FROM treasure_participants WHERE character_id=? AND released=0',(cid,)).fetchone():raise APIError(409,'战斗结算前不能删除角色。','in_battle')
                    db.execute('UPDATE characters SET deleted=1 WHERE id=?', (cid,))
                    return {'ok': True}
            raise APIError(404, '接口不存在。')

    def __call__(self, env, start_response):
        status = 200
        try:
            if env.get('HTTP_TRANSFER_ENCODING'):
                raise APIError(400, '不支持此请求编码。')
            length = int(env.get('CONTENT_LENGTH') or 0)
            if length < 0 or length > MAX_BODY:
                raise APIError(413, '请求超过大小限制。')
            body = json.loads(env['wsgi.input'].read(length), parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value))) if length else {}
            if not isinstance(body, dict):
                raise APIError(400, '请求格式不正确。')
            result = self.dispatch(env, body)
        except APIError as exc:
            status, result = exc.status, {'ok':False,'error': exc.message, 'code': exc.code,'snapshot':{}}
        except (ValueError, UnicodeError, RecursionError):
            status, result = 400, {'error': '请求格式不正确。'}
        except sqlite3.OperationalError:
            status, result = 503, {'ok':False,'error': '存档服务暂时繁忙，请稍后重试。','code':'service_unavailable','snapshot':{}}
        except Exception as exc:
            print('Request failed:', type(exc).__name__, flush=True)
            status, result = 500, {'error': '服务器暂时无法完成请求。'}
        payload = json.dumps(result, ensure_ascii=False, allow_nan=False).encode()
        reasons = {200:'OK',400:'Bad Request',401:'Unauthorized',403:'Forbidden',404:'Not Found',409:'Conflict',413:'Payload Too Large',429:'Too Many Requests',500:'Internal Server Error',503:'Service Unavailable'}
        start_response(f'{status} {reasons.get(status,"Error")}', [('Content-Type','application/json; charset=utf-8'),('Content-Length',str(len(payload))),('Cache-Control','no-store')])
        return [payload]

class BoundedServer(ThreadingMixIn, WSGIServer):
    daemon_threads = True
    request_queue_size = 16
    def __init__(self, *args, **kwargs):
        self.slots = threading.BoundedSemaphore(4)
        super().__init__(*args, **kwargs)
    def process_request(self, request, address):
        request.settimeout(10)
        if not self.slots.acquire(blocking=False):
            request.sendall(b'HTTP/1.0 503 Service Unavailable\r\nContent-Length: 0\r\n\r\n')
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except Exception:
            self.slots.release()
            raise
    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()

class QuietHandler(WSGIRequestHandler):
    def log_message(self, fmt, *args):
        pass  # Never log passwords, tokens, or save bodies.

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default=os.environ.get('ACADEMY_HOST','127.0.0.1'))
    parser.add_argument('--port', type=int, default=int(os.environ.get('ACADEMY_PORT','8787')))
    parser.add_argument('--data', type=Path, default=Path(os.environ.get('ACADEMY_DATA', str(Path(__file__).parent/'data'))))
    parser.add_argument('--production', action='store_true', help='Use Waitress (install requirements.txt) behind an HTTPS reverse proxy')
    parser.add_argument('--backup', type=Path, help='Create a consistent SQLite backup and exit')
    args = parser.parse_args()
    app = Application(args.data/'accounts.sqlite3')
    if args.backup:
        with app.db() as source, sqlite3.connect(args.backup) as target:
            source.backup(target)
        print('Backup completed')
        return
    print(f'Academy account service: http://{args.host}:{args.port}; SQLite; 4 workers', flush=True)
    if args.production:
        from waitress import serve
        serve(app, host=args.host, port=args.port, threads=4, connection_limit=64, channel_timeout=30, max_request_body_size=MAX_BODY, max_request_header_size=8192)
    else:
        with make_server(args.host, args.port, app, server_class=BoundedServer, handler_class=QuietHandler) as server:
            server.serve_forever()

if __name__ == '__main__':
    main()
