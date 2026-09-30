"""Single SQLite progression implementation, shared by game service and legacy local tests."""
from __future__ import annotations
import hashlib,hmac,json,os,re,secrets,sqlite3,time
from pathlib import Path
from contextlib import contextmanager,closing
SCHOOLS=['fire','ice','storm','myth','life','death','balance']

class APIError(Exception):
    def __init__(self,status,message,code='error'):
        self.status,self.message,self.code=status,message,code

class ProgressionLedger:
    account_table='identity_accounts'
    character_table='identity_characters'
    def __init__(self,db_path,catalog_root=None,service_key=None):
        self.db_path=str(db_path)
        self.catalog_root=Path(catalog_root) if catalog_root else Path(__file__).resolve().parent.parent/'resources/fusion_3d'
        self.service_key=service_key or ''
        Path(db_path).parent.mkdir(parents=True,exist_ok=True)
        with self.db() as db:
            if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='accounts'").fetchone():
                raise RuntimeError('Refusing to open a cloud account database as a game ledger')
            db.execute('PRAGMA journal_mode=WAL')
            db.executescript("""
                CREATE TABLE IF NOT EXISTS identity_accounts(id TEXT PRIMARY KEY,username TEXT NOT NULL,verified_at INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS identity_characters(id TEXT PRIMARY KEY,account_id TEXT NOT NULL REFERENCES identity_accounts(id),school TEXT NOT NULL,name TEXT NOT NULL,gender TEXT NOT NULL,hairstyle TEXT NOT NULL,verified_at INTEGER NOT NULL,deleted INTEGER NOT NULL DEFAULT 0);
            """)
            self.migrate_progression(db)

    def bind_identity(self,account,character,save):
        aid,cid=account.get('id'),character.get('id')
        school=character.get('school')
        if not isinstance(aid,str) or not re.fullmatch('[0-9a-f]{32}',aid) or not isinstance(cid,str) or not re.fullmatch('[0-9a-f]{32}',cid) or school not in ['fire','ice','storm','myth','life','death','balance'] or character.get('gender') not in ['male','female']:
            raise APIError(403,'云端身份格式无效。','unauthorized')
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            old=db.execute('SELECT * FROM identity_characters WHERE id=?',(cid,)).fetchone()
            if old and (old['account_id']!=aid or old['school']!=school):
                raise APIError(403,'角色归属或学院与已验证记录冲突。','unauthorized')
            now=int(time.time())
            db.execute('INSERT INTO identity_accounts VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET username=excluded.username,verified_at=excluded.verified_at',(aid,str(account.get('username','')),now))
            db.execute('INSERT INTO identity_characters(id,account_id,school,name,gender,hairstyle,verified_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,gender=excluded.gender,hairstyle=excluded.hairstyle,verified_at=excluded.verified_at',(cid,aid,school,str(character.get('name','')),character['gender'],str(character.get('hairstyle','f1')),now))
            row=dict(self.character_row(db,cid));row['legacy_presentation']=save
            self.ensure_progression(db,row)
            return self.progression(db,row)

    def legacy_presentation(self,row):
        return row.get('legacy_presentation',{}) if isinstance(row,dict) else {}

    def migrate_progression(self, db):
        version = db.execute('PRAGMA user_version').fetchone()[0]
        if version > 2:
            raise RuntimeError('Account schema is newer than this server')
        if version < 2:
            # A consistent pre-migration copy preserves legacy saves without trusting their economy.
            backup = Path(self.db_path + '.pre-v2.bak')
            if not backup.exists():
                with closing(sqlite3.connect(backup)) as target:
                    db.backup(target)
            db.executescript(f'''BEGIN IMMEDIATE;
                CREATE TABLE IF NOT EXISTS progression_accounts(account_id TEXT PRIMARY KEY REFERENCES {self.account_table}(id), revision INTEGER NOT NULL DEFAULT 1);
                CREATE TABLE IF NOT EXISTS progression_characters(character_id TEXT PRIMARY KEY REFERENCES {self.character_table}(id), revision INTEGER NOT NULL DEFAULT 1, equipped TEXT NOT NULL, appearance TEXT NOT NULL, wing TEXT NOT NULL DEFAULT '');
                CREATE TABLE IF NOT EXISTS treasure_inventory(character_id TEXT NOT NULL REFERENCES {self.character_table}(id), card_id TEXT NOT NULL, quantity INTEGER NOT NULL CHECK(quantity>=0), PRIMARY KEY(character_id,card_id));
                CREATE TABLE IF NOT EXISTS equipment_unlocks(account_id TEXT NOT NULL REFERENCES {self.account_table}(id), slot TEXT NOT NULL, tier TEXT NOT NULL, PRIMARY KEY(account_id,slot,tier));
                CREATE TABLE IF NOT EXISTS cosmetic_unlocks(account_id TEXT NOT NULL REFERENCES {self.account_table}(id), cosmetic_id TEXT NOT NULL, PRIMARY KEY(account_id,cosmetic_id));
                CREATE TABLE IF NOT EXISTS wing_unlocks(account_id TEXT NOT NULL REFERENCES {self.account_table}(id), wing_id TEXT NOT NULL, PRIMARY KEY(account_id,wing_id));
                CREATE TABLE IF NOT EXISTS progression_requests(account_id TEXT NOT NULL, request_id TEXT NOT NULL, fingerprint TEXT NOT NULL, result TEXT NOT NULL, PRIMARY KEY(account_id,request_id));
                CREATE TABLE IF NOT EXISTS island_tickets(ticket_hash TEXT PRIMARY KEY, character_id TEXT NOT NULL, token_hash TEXT NOT NULL, expires INTEGER NOT NULL, binding TEXT NOT NULL DEFAULT '');
                CREATE TABLE IF NOT EXISTS island_services(server_id TEXT PRIMARY KEY, boot_id TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS treasure_battles(battle_id TEXT PRIMARY KEY, server_id TEXT NOT NULL, boot_id TEXT NOT NULL, site_id TEXT NOT NULL, reward_version TEXT NOT NULL, rules TEXT NOT NULL, pvp INTEGER NOT NULL, finished INTEGER NOT NULL DEFAULT 0, finish_fingerprint TEXT NOT NULL DEFAULT '');
                CREATE TABLE IF NOT EXISTS treasure_participants(battle_id TEXT NOT NULL REFERENCES treasure_battles(battle_id), character_id TEXT NOT NULL REFERENCES {self.character_table}(id), cards TEXT NOT NULL, released INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(battle_id,character_id));
                CREATE UNIQUE INDEX IF NOT EXISTS treasure_active_character ON treasure_participants(character_id) WHERE released=0;
                CREATE TABLE IF NOT EXISTS treasure_reservations(token TEXT PRIMARY KEY, battle_id TEXT NOT NULL, character_id TEXT NOT NULL, card_id TEXT NOT NULL, consumed INTEGER NOT NULL DEFAULT 0, FOREIGN KEY(battle_id,character_id) REFERENCES treasure_participants(battle_id,character_id));
                CREATE TABLE IF NOT EXISTS treasure_rewards(battle_id TEXT NOT NULL, character_id TEXT NOT NULL, cards TEXT NOT NULL, PRIMARY KEY(battle_id,character_id));
                PRAGMA user_version=2;
                COMMIT;''')


    @contextmanager
    def db(self):
        connection = sqlite3.connect(self.db_path, timeout=5)
        connection.row_factory = sqlite3.Row
        connection.execute('PRAGMA foreign_keys=ON')
        connection.execute('PRAGMA busy_timeout=5000')
        try:
            with connection:
                yield connection
        finally:
            connection.close()


    def read_catalog(self, name):
        try:
            return json.loads((self.catalog_root/name).read_text(encoding='utf-8-sig'))
        except (OSError, ValueError):
            raise APIError(503, '装备目录暂不可用。', 'service_unavailable')


    def catalogs(self):
        equipment = self.read_catalog('weekend_equipment.json')
        economy = self.read_catalog('weekend_treasure_economy.json')
        return equipment, economy


    def character_row(self,db, cid, aid=None, allow_deleted=False):
        row = db.execute(f'SELECT * FROM {self.character_table} WHERE id=?'+('' if allow_deleted else ' AND deleted=0'), (cid,)).fetchone()
        if not row or (aid is not None and row['account_id'] != aid):
            raise APIError(404, '找不到该角色。', 'unauthorized')
        return row


    def ensure_progression(self, db, row):
        aid, cid, school = row['account_id'], row['id'], row['school']
        db.execute('INSERT OR IGNORE INTO progression_accounts(account_id) VALUES(?)', (aid,))
        if db.execute('SELECT 1 FROM progression_characters WHERE character_id=?', (cid,)).fetchone():
            return
        defaults = self.read_catalog('teen_catalog.json')['defaults'][row['gender']]
        appearance = {k: school for k in ['body','hat','robe','boots','staff','aura']}
        appearance.update(defaults)
        appearance.update(gender=row['gender'], hairstyle=row['hairstyle'], model_style='teen', teen_dyes={}, teen_hair_color='')
        for spec in self.read_catalog('weekend_equipment.json').get('cosmetics',[]):
            if spec.get('school')==school and spec.get('tier')=='t0':
                appearance.update(spec.get('appearance_by_gender',{}).get(row['gender'],{}))
        # Carry forward only independently validated non-economic presentation fields.
        saved=self.legacy_presentation(row).get('academy_wardrobe.json',{})
        outfits=saved.get('outfits',{}) if isinstance(saved,dict) else {}
        legacy=outfits.get(school,{}) if isinstance(outfits,dict) else {}
        if isinstance(legacy,dict):
            for key in ['teen_hair','teen_skin','teen_hair_color','teen_dyes']:
                if key not in legacy:continue
                try:appearance=self.validate_appearance(row,{key:legacy[key]},{'appearance':appearance,'cosmetic_unlocks':[]})
                except APIError:pass
        equipped = {slot: f'eq_{school}_{slot}_t0' for slot in ['staff','hat','robe','boots','cape']}
        db.execute('INSERT INTO progression_characters(character_id,equipped,appearance) VALUES(?,?,?)', (cid,json.dumps(equipped),json.dumps(appearance)))


    def progression(self, db, row):
        self.ensure_progression(db, row)
        aid, cid = row['account_id'], row['id']
        character = db.execute('SELECT * FROM progression_characters WHERE character_id=?', (cid,)).fetchone()
        self.unlock_equipment_cosmetics(db,aid)
        self.preserve_equipped_cosmetics(db,row,character)
        try:
            catalog_version = self.read_catalog('weekend_equipment.json').get('catalog_version', 1)
        except APIError:
            catalog_version = ''
        return {'schema_version':1, 'catalog_version':catalog_version, 'account_id':aid, 'character_id':cid, 'school':row['school'],
                'account_revision':db.execute('SELECT revision FROM progression_accounts WHERE account_id=?',(aid,)).fetchone()[0],
                'character_revision':character['revision'],
                'frost_cleared_sites':self.frost_cleared_sites(db,cid),
                'treasure_inventory':dict(db.execute('SELECT card_id,quantity FROM treasure_inventory WHERE character_id=? AND quantity>0',(cid,)).fetchall()),
                'treasure_reserved':dict(db.execute('SELECT r.card_id,count(*) FROM treasure_reservations r JOIN treasure_participants p USING(battle_id,character_id) WHERE r.character_id=? AND r.consumed=0 AND p.released=0 GROUP BY r.card_id',(cid,)).fetchall()),
                'equipment_unlocks':[r['slot']+':'+r['tier'] for r in db.execute('SELECT slot,tier FROM equipment_unlocks WHERE account_id=? ORDER BY slot,tier',(aid,))],
                'cosmetic_unlocks':[r[0] for r in db.execute('SELECT cosmetic_id FROM cosmetic_unlocks WHERE account_id=? ORDER BY cosmetic_id',(aid,))],
                'wing_unlocks':[r[0] for r in db.execute('SELECT wing_id FROM wing_unlocks WHERE account_id=? ORDER BY wing_id',(aid,))],
                'equipped_stats':json.loads(character['equipped']), 'appearance':json.loads(character['appearance']), 'equipped_wing':character['wing']}


    @staticmethod
    def valid_key(value):
        if not isinstance(value,str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,160}',value):
            raise APIError(400, '缺少稳定请求标识。', 'revision_conflict')
        return value


    @staticmethod
    def card_counts(value, limit=10000):
        if not isinstance(value,dict) or len(value)>40 or any(not isinstance(k,str) or not k or type(v) is not int or v<=0 or v>limit for k,v in value.items()) or sum(value.values())>limit:
            raise APIError(400, '卡牌数量不正确。', 'insufficient_cards')
        return value


    @staticmethod
    def fingerprint(value):
        return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()


    @staticmethod
    def bump_character(db,cid):
        db.execute('UPDATE progression_characters SET revision=revision+1 WHERE character_id=?',(cid,))


    def player_progression(self, db, row, action, body, token_hash):
        self.ensure_progression(db,row)
        aid,cid=row['account_id'],row['id']
        if action=='progression':
            return {'ok':True,'code':'ok','snapshot':self.progression(db,row)}
        if action=='island-ticket':
            ticket=secrets.token_urlsafe(32)
            db.execute('DELETE FROM island_tickets WHERE expires<? AND binding=?',(int(time.time())-300,''))
            db.execute('INSERT INTO island_tickets(ticket_hash,character_id,token_hash,expires) VALUES(?,?,?,?)',(hashlib.sha256(ticket.encode()).hexdigest(),cid,token_hash,int(time.time())+60))
            return {'ok':True,'code':'ok','ticket':ticket,'expires_in':60,'snapshot':self.progression(db,row)}
        request_id=self.valid_key(body.get('request_id'))
        fingerprint=self.fingerprint([cid,action,body])
        old=db.execute('SELECT * FROM progression_requests WHERE account_id=? AND request_id=?',(aid,request_id)).fetchone()
        if old:
            if old['fingerprint']!=fingerprint:raise APIError(409,'请求标识已用于其它操作。','revision_conflict')
            return json.loads(old['result'])
        snapshot=self.progression(db,row)
        for key in ['account_revision','character_revision']:
            if key in body and body[key]!=snapshot[key]:raise APIError(409,'权益已更新，请刷新后重试。','revision_conflict')
        code='ok'
        if action=='exchange':
            equipment,economy=self.catalogs()
            slot,tier=body.get('slot'),body.get('tier')
            if slot not in ['staff','hat','robe','boots','cape'] or tier not in ['t1','t2','t3','t4','t5']:
                raise APIError(400,'装备档次不正确。','invalid_equipment')
            if slot+':'+tier in snapshot['equipment_unlocks']:
                code='already_unlocked'
            else:
                previous='t'+str(int(tier[1:])-1)
                if tier!='t1' and slot+':'+previous not in snapshot['equipment_unlocks']:
                    raise APIError(409,'请先解锁该槽 '+previous.upper()+'。','invalid_equipment')
                payment=self.card_counts(body.get('payment_cards'))
                price=int(economy['exchange']['prices'][tier])
                if sum(payment.values())!=price:raise APIError(400,'所选卡数必须等于价格。','insufficient_cards')
                if set(payment)-set(economy['currency']['legal_cards']):raise APIError(400,'不能支付这种卡牌。','insufficient_cards')
                for card,count in payment.items():
                    if snapshot['treasure_inventory'].get(card,0)-snapshot['treasure_reserved'].get(card,0)<count:
                        raise APIError(409,'可用宝藏卡不足，战斗中的卡不可兑换。','insufficient_cards')
                items=[v for v in equipment['items'] if v['slot']==slot and v['tier']==tier]
                if {v['school'] for v in items}!=set(SCHOOLS):raise APIError(503,'装备目录不完整。','service_unavailable')
                for card,count in payment.items():
                    db.execute('UPDATE treasure_inventory SET quantity=quantity-? WHERE character_id=? AND card_id=?',(count,cid,card))
                db.execute('INSERT INTO equipment_unlocks VALUES(?,?,?)',(aid,slot,tier))
                db.execute('UPDATE progression_accounts SET revision=revision+1 WHERE account_id=?',(aid,))
                self.bump_character(db,cid)
        elif action=='shop-buy':
            shop=self.read_catalog('weekend_shop_catalog.json')
            equipment,economy=self.catalogs()
            if body.get('catalog_version')!=shop.get('catalog_version'):
                raise APIError(409,'商品目录已更新，请更新客户端后重试。','catalog_version_mismatch')
            if shop.get('catalog_version')!=economy.get('catalog_version') or shop.get('catalog_version')!=equipment.get('catalog_version'):
                raise APIError(503,'商品目录版本不一致。','service_unavailable')
            offer=next((v for v in shop['offers'] if v['id']==body.get('offer_id')),None)
            if not offer or offer.get('kind') not in ['treasure','cosmetic']:
                raise APIError(400,'商品不存在或不支持此购买方式。','invalid_offer')
            quantity=body.get('quantity')
            if type(quantity) is not int or not 1<=quantity<=int(shop['max_quantity']) or (offer['kind']=='cosmetic' and quantity!=1):
                raise APIError(400,'购买数量无效。','invalid_quantity')
            cosmetic_ids=[]
            if offer['kind']=='cosmetic':
                if offer.get('cosmetic_id'):
                    spec=next((v for v in equipment['cosmetics'] if v['id']==offer['cosmetic_id']),None)
                    if not spec or spec.get('school','any') not in ['any',row['school']] or offer.get('school','any') not in ['any',row['school']]:
                        raise APIError(403,'外观不属于本学院。','invalid_equipment')
                    gender=snapshot['appearance']['gender']
                    mapping=spec.get('appearance_by_gender',{}).get(gender,{})
                    if offer.get('gender','both') not in ['both',gender] or not mapping:
                        raise APIError(403,'外观不适用于当前角色性别。','invalid_equipment')
                    # Validate the exact authored mapping before any charge, including
                    # model gender and restricted-account flags from source options.
                    trial=dict(snapshot,cosmetic_unlocks=snapshot['cosmetic_unlocks']+[spec['id']])
                    self.validate_appearance(row,mapping,trial)
                    cosmetic_ids=[spec['id']]
                    if self.cosmetic_owned(spec,snapshot['cosmetic_unlocks']):code='already_unlocked'
                else:
                    items=[v for v in equipment['items'] if v['slot']==offer.get('slot') and v['tier']==offer.get('tier')]
                    if offer.get('tier') not in ['t1','t2','t3','t4','t5'] or {v['school'] for v in items}!=set(SCHOOLS):
                        raise APIError(503,'外观目录不完整。','service_unavailable')
                    cosmetic_ids=[v['cosmetic_id'] for v in items]
                    if set(cosmetic_ids)<=set(snapshot['cosmetic_unlocks']):code='already_unlocked'
            elif offer.get('card_id') not in economy['playable_cards'] or offer.get('card_id')==economy['currency']['card_id']:
                raise APIError(503,'宝藏商品目录无效。','service_unavailable')
            if code!='already_unlocked':
                price=offer['cost_empower']
                if type(price) is not int or price<=0:raise APIError(503,'商品价格无效。','service_unavailable')
                cost=price*quantity;currency=economy['currency']['card_id']
                if snapshot['treasure_inventory'].get(currency,0)-snapshot['treasure_reserved'].get(currency,0)<cost:
                    raise APIError(409,'可用赋能不足，战斗预留的卡不可支付。','insufficient_cards')
                db.execute('UPDATE treasure_inventory SET quantity=quantity-? WHERE character_id=? AND card_id=?',(cost,cid,currency))
                if offer['kind']=='treasure':
                    db.execute('INSERT INTO treasure_inventory VALUES(?,?,?) ON CONFLICT(character_id,card_id) DO UPDATE SET quantity=quantity+excluded.quantity',(cid,offer['card_id'],quantity))
                else:
                    for cosmetic_id in cosmetic_ids:db.execute('INSERT OR IGNORE INTO cosmetic_unlocks VALUES(?,?)',(aid,cosmetic_id))
                    db.execute('UPDATE progression_accounts SET revision=revision+1 WHERE account_id=?',(aid,))
                self.bump_character(db,cid)
        elif action=='equip-stat':
            if db.execute('SELECT 1 FROM treasure_participants WHERE character_id=? AND released=0',(cid,)).fetchone():
                raise APIError(409,'战斗中不能更换属性装备。','in_battle')
            equipment,_=self.catalogs()
            item=next((v for v in equipment['items'] if v['id']==body.get('item_id')),None)
            if not item or item['school']!=row['school'] or item['slot']!=body.get('slot') or (item['tier']!='t0' and item['slot']+':'+item['tier'] not in snapshot['equipment_unlocks']):
                raise APIError(403,'未拥有或不属于本系的装备。','invalid_equipment')
            snapshot['equipped_stats'][item['slot']]=item['id']
            db.execute('UPDATE progression_characters SET equipped=? WHERE character_id=?',(json.dumps(snapshot['equipped_stats']),cid))
            self.bump_character(db,cid)
        elif action=='appearance':
            value=self.validate_appearance(row,body.get('value'),snapshot)
            db.execute('UPDATE progression_characters SET appearance=? WHERE character_id=?',(json.dumps(value),cid))
            self.bump_character(db,cid)
        elif action=='equip-wing':
            wing=body.get('wing_id')
            if not isinstance(wing,str) or (wing and wing not in snapshot['wing_unlocks']):raise APIError(403,'尚未解锁此翅膀。','invalid_equipment')
            db.execute('UPDATE progression_characters SET wing=? WHERE character_id=?',(wing,cid))
            self.bump_character(db,cid)
        else:raise APIError(404,'接口不存在。')
        result={'ok':True,'code':code,'snapshot':self.progression(db,row)}
        db.execute('INSERT INTO progression_requests VALUES(?,?,?,?)',(aid,request_id,fingerprint,json.dumps(result)))
        return result


    def internal(self, env, action, body):
        supplied=env.get('HTTP_X_ACADEMY_SERVICE_KEY','')
        if not self.service_key or not hmac.compare_digest(supplied,self.service_key):
            raise APIError(401,'服务身份验证失败。','unauthorized')
        server_id,boot_id=self.valid_key(body.get('server_id')),self.valid_key(body.get('boot_id'))
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            if action=='claim':
                current=db.execute('SELECT boot_id FROM island_services WHERE server_id=?',(server_id,)).fetchone()
                expected=body.get('expected_boot_ids',[])
                if not isinstance(expected,list) or len(expected)>2 or any(not isinstance(v,str) for v in expected):raise APIError(400,'专服恢复身份无效。','unauthorized')
                if current and current[0]!=boot_id and current[0] not in expected:
                    raise APIError(409,'必须使用原专服持久目录恢复，不允许新目录夺取活跃实例。','revision_conflict')
                db.execute('INSERT INTO island_services VALUES(?,?) ON CONFLICT(server_id) DO UPDATE SET boot_id=excluded.boot_id',(server_id,boot_id))
                return {'ok':True,'code':'ok'}
            service=db.execute('SELECT boot_id FROM island_services WHERE server_id=?',(server_id,)).fetchone()
            if not service or service[0]!=boot_id:raise APIError(409,'专服进程已被替代。','revision_conflict')
            if action=='redeem-ticket':
                ticket=body.get('ticket','')
                binding=server_id+':'+boot_id+':'+self.valid_key(body.get('binding'))
                if not isinstance(ticket,str) or len(ticket)>256:raise APIError(401,'入场凭据无效。','unauthorized')
                ticket_hash=hashlib.sha256(ticket.encode()).hexdigest()
                record=db.execute('SELECT * FROM island_tickets WHERE ticket_hash=?',(ticket_hash,)).fetchone()
                if not record or record['expires']<int(time.time()) or record['binding'] not in ['',binding]:raise APIError(401,'入场凭据过期或已使用。','unauthorized')
                row=self.character_row(db,record['character_id'])
                if not db.execute('SELECT 1 FROM sessions WHERE token_hash=? AND account_id=? AND expires>?',(record['token_hash'],row['account_id'],int(time.time()))).fetchone():raise APIError(401,'会话已过期。','unauthorized')
                db.execute('UPDATE island_tickets SET binding=? WHERE ticket_hash=?',(binding,ticket_hash))
                return {'ok':True,'code':'ok','snapshot':self.progression(db,row),'name':row['name']}
            if action=='snapshot':
                return {'ok':True,'code':'ok','snapshot':self.progression(db,self.character_row(db,body.get('character_id')))}
            if action=='recover':
                # The caller has fenced the former process and drained its durable outbox.
                old=[r[0] for r in db.execute('SELECT battle_id FROM treasure_battles WHERE server_id=? AND boot_id<>? AND finished=0',(server_id,boot_id))]
                for battle_id in old:
                    self.release_battle(db,battle_id)
                    db.execute('UPDATE treasure_battles SET finished=1,finish_fingerprint=? WHERE battle_id=?',('recovered',battle_id))
                return {'ok':True,'code':'ok','recovered':len(old)}
            battle_id=self.valid_key(body.get('battle_id'))
            battle=db.execute('SELECT * FROM treasure_battles WHERE battle_id=?',(battle_id,)).fetchone()
            if battle and battle['server_id']!=server_id:raise APIError(403,'战斗不属于此专服。','unauthorized')
            if action=='reserve':
                cid=body.get('character_id')
                row=self.character_row(db,cid)
                self.ensure_progression(db,row)
                cards=self.card_counts(body.get('cards',{}),40)
                _,economy=self.catalogs()
                if set(cards)-set(economy.get('playable_cards',economy['currency']['legal_cards'])):raise APIError(400,'非法宝藏卡。','insufficient_cards')
                site_id=self.valid_key(body.get('site_id'))
                pvp=body.get('pvp',False)
                if type(pvp) is not bool:raise APIError(400,'战斗类型无效。')
                if not battle:
                    mapping=self.read_catalog('weekend_boss_wings.json')
                    if mapping.get('schema_version')!=1 or not isinstance(mapping.get('sites'),dict):
                        raise APIError(503,'首领奖励目录不可用。','service_unavailable')
                    boss=mapping['sites'].get(site_id,{}) if not pvp else {}
                    if boss and (boss.get('boss') is not True or not boss.get('wing_id')):
                        raise APIError(503,'首领奖励配置不完整。','service_unavailable')
                    economy=dict(economy, battle_boss=bool(boss), reward_wing=boss.get('wing_id',''), boss_catalog_version=mapping.get('catalog_version',''))
                    if economy.get('drops',{}).get('mode')=='empower_by_site':
                        economy['frozen_reward']=self.site_reward(site_id,pvp,economy)
                        economy['frost_first_clear_multiplier']=3
                    db.execute('INSERT INTO treasure_battles(battle_id,server_id,boot_id,site_id,reward_version,rules,pvp) VALUES(?,?,?,?,?,?,?)',(battle_id,server_id,boot_id,site_id,str(economy['catalog_version']),json.dumps(economy),int(pvp)))
                    battle=db.execute('SELECT * FROM treasure_battles WHERE battle_id=?',(battle_id,)).fetchone()
                if battle['finished'] or battle['boot_id']!=boot_id or battle['site_id']!=site_id or bool(battle['pvp'])!=pvp:raise APIError(409,'战斗已结束或版本冲突。','revision_conflict')
                participant=db.execute('SELECT * FROM treasure_participants WHERE battle_id=? AND character_id=?',(battle_id,cid)).fetchone()
                if participant:
                    if participant['released'] or json.loads(participant['cards'])!=cards:raise APIError(409,'入场请求冲突。','revision_conflict')
                else:
                    if db.execute('SELECT 1 FROM treasure_participants WHERE character_id=? AND released=0',(cid,)).fetchone():raise APIError(409,'该角色已在另一场战斗中。','in_battle')
                    snapshot=self.progression(db,row)
                    if any(snapshot['treasure_inventory'].get(card,0)-snapshot['treasure_reserved'].get(card,0)<count for card,count in cards.items()):raise APIError(409,'可用宝藏卡不足。','insufficient_cards')
                    db.execute('INSERT INTO treasure_participants(battle_id,character_id,cards) VALUES(?,?,?)',(battle_id,cid,json.dumps(cards,sort_keys=True)))
                    for card,count in cards.items():
                        for index in range(count):
                            token=hashlib.sha256(f'{battle_id}:{cid}:{card}:{index}'.encode()).hexdigest()
                            db.execute('INSERT INTO treasure_reservations(token,battle_id,character_id,card_id) VALUES(?,?,?,?)',(token,battle_id,cid,card))
                    self.bump_character(db,cid)
                tokens={card:[r[0] for r in db.execute('SELECT token FROM treasure_reservations WHERE battle_id=? AND character_id=? AND card_id=? ORDER BY token',(battle_id,cid,card))] for card in cards}
                return {'ok':True,'code':'ok','snapshot':self.progression(db,row),'treasures':cards,'treasure_tokens':tokens,'reward_version':battle['reward_version']}
            if not battle:raise APIError(404,'战斗不存在。','revision_conflict')
            if action=='consume':
                token=self.valid_key(body.get('token'))
                record=db.execute('SELECT * FROM treasure_reservations WHERE token=? AND battle_id=?',(token,battle_id)).fetchone()
                if not record or record['character_id']!=body.get('character_id') or record['card_id']!=body.get('card_id'):raise APIError(403,'消费凭据无效。','unauthorized')
                row=self.character_row(db,record['character_id'],allow_deleted=True)
                if not record['consumed']:
                    if battle['finished']:raise APIError(409,'战斗已结算。','revision_conflict')
                    changed=db.execute('UPDATE treasure_inventory SET quantity=quantity-1 WHERE character_id=? AND card_id=? AND quantity>0',(row['id'],record['card_id'])).rowcount
                    if changed!=1:raise APIError(409,'宝藏卡账本不一致。','insufficient_cards')
                    db.execute('UPDATE treasure_reservations SET consumed=1 WHERE token=?',(token,))
                    self.bump_character(db,row['id'])
                return {'ok':True,'code':'ok','snapshot':self.progression(db,row)}
            if action=='finish':
                winners=body.get('winners',[])
                if not isinstance(winners,list) or len(winners)>4 or any(not isinstance(v,str) for v in winners) or len(set(winners))!=len(winners):raise APIError(400,'结算角色无效。')
                fingerprint=self.fingerprint(sorted(winners))
                if battle['finished'] and battle['finish_fingerprint']!=fingerprint:raise APIError(409,'战斗已经按其它结果结算。','revision_conflict')
                participants=[r[0] for r in db.execute('SELECT character_id FROM treasure_participants WHERE battle_id=?',(battle_id,))]
                if set(winners)-set(participants) or (battle['pvp'] and winners):raise APIError(403,'无奖励资格。','unauthorized')
                rules=json.loads(battle['rules'])
                for cid in winners:
                    if db.execute('SELECT 1 FROM treasure_rewards WHERE battle_id=? AND character_id=?',(battle_id,cid)).fetchone():continue
                    row=self.character_row(db,cid,allow_deleted=True)
                    frozen=rules.get('frozen_reward')
                    pool=[frozen['card_id']] if frozen else rules['school_pools'][row['school']]['all']
                    count=int(frozen['quantity']) if frozen else int(rules['drops']['boss'] if rules.get('battle_boss',False) else rules['drops']['normal'])
                    # Winner receipts are the durable first-clear ledger, including
                    # historical victories. The same transaction serializes rewards
                    # and keeps finish retries/restarts from awarding the bonus twice.
                    if frozen and not battle['pvp'] and battle['site_id'].startswith('frost_') and battle['site_id'] not in self.frost_cleared_sites(db,cid):
                        count*=int(rules.get('frost_first_clear_multiplier',1))
                    cards={}
                    for index in range(count):
                        card=pool[int(hashlib.sha256(f'{battle_id}:{cid}:{index}'.encode()).hexdigest(),16)%len(pool)]
                        cards[card]=cards.get(card,0)+1
                    for card,amount in cards.items():
                        db.execute('INSERT INTO treasure_inventory VALUES(?,?,?) ON CONFLICT(character_id,card_id) DO UPDATE SET quantity=quantity+excluded.quantity',(cid,card,amount))
                    wing=rules.get('reward_wing','')
                    if wing and db.execute('INSERT OR IGNORE INTO wing_unlocks(account_id,wing_id) VALUES(?,?)',(row['account_id'],wing)).rowcount:
                        db.execute('UPDATE progression_accounts SET revision=revision+1 WHERE account_id=?',(row['account_id'],))
                    db.execute('INSERT INTO treasure_rewards VALUES(?,?,?)',(battle_id,cid,json.dumps(cards)))
                    self.bump_character(db,cid)
                if not battle['finished']:
                    self.release_battle(db,battle_id)
                    db.execute('UPDATE treasure_battles SET finished=1,finish_fingerprint=? WHERE battle_id=?',(fingerprint,battle_id))
                return {'ok':True,'code':'ok','snapshots':{cid:self.progression(db,self.character_row(db,cid,allow_deleted=True)) for cid in participants},'rewards':{r['character_id']:json.loads(r['cards']) for r in db.execute('SELECT * FROM treasure_rewards WHERE battle_id=?',(battle_id,))}}
            raise APIError(404,'接口不存在。')


    def release_battle(self,db,battle_id):
        for row in db.execute('SELECT character_id FROM treasure_participants WHERE battle_id=? AND released=0',(battle_id,)):
            self.bump_character(db,row[0])
        db.execute('UPDATE treasure_participants SET released=1 WHERE battle_id=?',(battle_id,))

    def frost_cleared_sites(self,db,cid):
        return [r[0] for r in db.execute("SELECT DISTINCT b.site_id FROM treasure_rewards r JOIN treasure_battles b USING(battle_id) WHERE r.character_id=? AND b.pvp=0 AND b.site_id GLOB 'frost_*' ORDER BY b.site_id",(cid,))]

    def site_reward(self,site_id,pvp,economy):
        if pvp:return {'card_id':economy['currency']['card_id'],'quantity':0}
        base=self.read_catalog('frost_encounter_progression.json')
        site=next((v for v in base if v['id']==site_id),None)
        if site is None:
            addition=next((v for v in self.read_catalog('frost_circled_encounters.json') if v['id']==site_id),None)
            # template_order is a reference to an authored template, never a difficulty value.
            template=next((v for v in base if addition and v['order']==addition['template_order']),None)
            if template:site=dict(template,**{k:v for k,v in addition.items() if k!='template_order'})
        difficulty=economy['drops']['difficulty_by_encounter'].get(site.get('encounter')) if site else None
        if type(difficulty) is not int or difficulty not in [1,2,3,4] or not site.get('enemies') or site_id=='frost_pvp_01':
            raise APIError(503,'营地奖励目录不完整。','service_unavailable')
        # Explicit per-template amounts preserve identical rewards at cloned sites.
        # Existing battles keep their already-frozen quantity; never rescale receipts.
        quantity_mode=economy['drops'].get('quantity_mode','legacy')
        if quantity_mode not in ['legacy','authored_encounter_quantity']:
            raise APIError(503,'营地奖励模式无效。','service_unavailable')
        if quantity_mode == 'authored_encounter_quantity':
            quantities=economy['drops'].get('quantity_by_encounter')
            count=quantities.get(site['encounter']) if isinstance(quantities,dict) else None
            if type(count) is not int or not 1 <= count <= 100:
                raise APIError(503,'营地奖励数量配置无效。','service_unavailable')
        else:
            count=len(site['enemies'])+difficulty+int(economy['drops']['site_bonus'].get(site_id,0))
        return {'card_id':economy['currency']['card_id'],'quantity':count,'enemy_count':len(site['enemies']),'difficulty':difficulty,'encounter':site['encounter']}


    @staticmethod
    def cosmetic_owned(spec,unlocks):
        return spec.get('always_unlocked') is True or spec.get('tier')=='t0' or spec['id'] in unlocks or bool(set(spec.get('unlock_aliases',[])) & set(unlocks))

    def unlock_equipment_cosmetics(self,db,aid):
        """Pair authoritative account equipment rights with their exact catalog looks.

        Called before snapshots, including immediately after exchange. This also
        repairs existing accounts without replaying purchases or granting currency.
        Slot/tier rights already cover all schools; appearance validation still
        enforces the active character's school and gender.
        """
        rights={(r[0],r[1]) for r in db.execute('SELECT slot,tier FROM equipment_unlocks WHERE account_id=?',(aid,))}
        if not rights:return
        equipment=self.read_catalog('weekend_equipment.json')
        specs={v['id'] for v in equipment.get('cosmetics',[])}
        cosmetic_ids={v['cosmetic_id'] for v in equipment.get('items',[])
                      if (v.get('slot'),v.get('tier')) in rights and v.get('cosmetic_id') in specs}
        changed=False
        for cosmetic_id in sorted(cosmetic_ids):
            if db.execute('INSERT OR IGNORE INTO cosmetic_unlocks VALUES(?,?)',(aid,cosmetic_id)).rowcount:changed=True
        if changed:db.execute('UPDATE progression_accounts SET revision=revision+1 WHERE account_id=?',(aid,))

    def preserve_equipped_cosmetics(self,db,row,character):
        """Only grandfather presentation already stored in the authoritative game DB."""
        appearance=json.loads(character['appearance'])
        gender=appearance.get('gender',row['gender'])
        unlocks=[r[0] for r in db.execute('SELECT cosmetic_id FROM cosmetic_unlocks WHERE account_id=?',(row['account_id'],))]
        changed=False
        for spec in self.read_catalog('weekend_equipment.json').get('cosmetics',[]):
            if spec.get('source')!='wardrobe' or self.cosmetic_owned(spec,unlocks) or spec.get('school','any') not in ['any',row['school']]:continue
            mapping=spec.get('appearance_by_gender',{}).get(gender,{})
            if not mapping or any(appearance.get(key)!=item for key,item in mapping.items()):continue
            trial={'appearance':appearance,'cosmetic_unlocks':unlocks+[spec['id']]}
            try:self.validate_appearance(row,mapping,trial)
            except APIError:continue
            if db.execute('INSERT OR IGNORE INTO cosmetic_unlocks VALUES(?,?)',(row['account_id'],spec['id'])).rowcount:changed=True
        if changed:db.execute('UPDATE progression_accounts SET revision=revision+1 WHERE account_id=?',(row['account_id'],))

    def validate_appearance(self,row,value,snapshot):
        if not isinstance(value,dict) or len(json.dumps(value))>16000:
            raise APIError(400,'外观格式不正确。','invalid_equipment')
        teen=self.read_catalog('teen_catalog.json')
        equipment,_=self.catalogs()
        # Explicit compatibility baseline: defaults and deliberately authored non-economic outfits.
        options={k:{v['id']:v for v in values} for k,values in teen['options'].items()}
        base={k:{v[k] for v in teen['defaults'].values() if k in v}|{'none'} for k in options}
        personal=['teen_hair','teen_skin','teen_body_shape','teen_boot_shape','teen_back_shape']
        for slot in personal:base[slot]=set(options.get(slot,{}))
        for filename in ['teen_hat_hair_catalog.json','teen_hat_hair_v2_catalog.json']:
            for item in self.read_catalog(filename).get('options',[]):
                options.setdefault('teen_hair',{})[item['id']]=item
                base.setdefault('teen_hair',set()).add(item['id'])
        for filename in ['teen_starweave_v1.json','teen_pink_sakura.json','teen_sailor_uniform.json','teen_hanbok.json']:
            addon=self.read_catalog(filename)
            for slot,items in addon.get('options',{}).items():
                options.setdefault(slot,{}).update({v['id']:v for v in items})
                base.setdefault(slot,set()).update(v['id'] for v in items if not v.get('restricted_account'))
        # Existing authored Sakura/Sailor sets use this exact base shoe from teen_catalog.
        base.setdefault('teen_boots',set()).add('baselayer_female_boots')
        # Economic cosmetic metadata is authoritative, even when it references a former free mesh.
        cosmetic_specs=equipment.get('cosmetics',[])
        if isinstance(cosmetic_specs,dict):cosmetic_specs=list(cosmetic_specs.values())
        allowed=snapshot['cosmetic_unlocks']+[v['cosmetic_id'] for v in equipment['items'] if v['tier']=='t0' and v['school']==row['school']]
        for spec in cosmetic_specs:
            for mapping in spec.get('appearance_by_gender',{}).values():
                for slot,item in mapping.items():
                    if isinstance(item,str):base.setdefault(slot,set()).discard(item)
        for spec in cosmetic_specs:
            if self.cosmetic_owned(spec,allowed) and spec.get('school') in ['any',row['school']]:
                for slot,item in spec.get('appearance_by_gender',{}).get(value.get('gender',snapshot['appearance']['gender']),{}).items():
                    if isinstance(item,str):base.setdefault(slot,set()).add(item)
        result=snapshot['appearance'].copy()
        gender=value.get('gender',result.get('gender',row.get('gender') if isinstance(row,dict) else row['gender']))
        for key,choice in value.items():
            valid=False
            if key in options:
                item=options[key].get(choice,{}) if isinstance(choice,str) else {}
                valid=isinstance(choice,str) and choice in base.get(key,set()) and (choice=='none' or bool(item)) and item.get('gender','both') in ['both',gender] and not item.get('restricted_account') and str(item.get('school','any')).replace('strom','storm') in ['', 'any',row['school']]
            elif key in ['body','hat','robe','boots','staff','aura']:valid=choice==row['school']
            elif key=='gender':valid=choice in ['male','female']
            elif key=='hairstyle':valid=choice in ['m1','m2','m3','m4','f1','f2','f3','f4']
            elif key=='model_style':valid=choice in ['teen','modular']
            elif key=='teen_hair_color':valid=isinstance(choice,str) and (not choice or re.fullmatch(r'#?[0-9a-fA-F]{6}([0-9a-fA-F]{2})?',choice) is not None)
            elif key=='teen_dyes':
                valid=isinstance(choice,dict) and len(choice)<=40 and len(json.dumps(choice))<=8000
            elif key.endswith('_fit_revision'):valid=type(choice) is int and 0<=choice<=2
            if not valid:raise APIError(403,'该外观未解锁或不属于本系：'+str(key),'invalid_equipment')
            result[key]=choice
        return result

