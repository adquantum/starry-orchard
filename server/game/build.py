"""Build a portable, data-only Godot server project. No client graphics or accounts DB."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import zipfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'builds/island-server'
RUNTIME_LOCK=ROOT/'tools/server_update/runtime.lock.json'
RUNTIME_APPS=[ROOT/'server/game/run_server.py',ROOT/'server/game/progression_service.py',ROOT/'server/progression_ledger.py']

def copy(p):
    dest=OUT/p.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)

def content_runtime_id(lock):
    digest=hashlib.sha256()
    for path in sorted(RUNTIME_APPS,key=lambda value:value.name):
        digest.update(path.name.encode('utf-8')+b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return lock['runtime_id']+'-app-'+digest.hexdigest()[:12]

def write_global_class_cache():
    """Write the Godot 4 global class registry required by standalone script checks."""
    entries=[]
    for path in sorted((OUT/'scripts').rglob('*.gd')):
        source=path.read_text(encoding='utf-8-sig')
        class_match=re.search(r'^class_name\s+([A-Za-z_]\w*)\s*$',source,re.MULTILINE)
        if class_match is None:
            continue
        base_match=re.search(r'^extends\s+([A-Za-z_]\w*)\s*$',source,re.MULTILINE)
        if base_match is None:
            raise ValueError(f'Global class has no simple extends declaration: {path}')
        entries.append({
            'base':base_match.group(1),
            'class':class_match.group(1),
            'path':'res://'+path.relative_to(OUT).as_posix(),
        })
    if not entries:
        raise RuntimeError('No global GDScript classes found in server package')
    entries.sort(key=lambda item:item['class'].lower())
    blocks=[]
    for item in entries:
        blocks.append('''{
"base": &%s,
"class": &%s,
"icon": "",
"is_abstract": false,
"is_tool": false,
"language": &"GDScript",
"path": %s
}'''%(json.dumps(item['base']),json.dumps(item['class']),json.dumps(item['path'])))
    cache=OUT/'.godot/global_script_class_cache.cfg'
    cache.parent.mkdir(parents=True,exist_ok=True)
    cache.write_text('list=['+', '.join(blocks)+']\n',encoding='utf-8',newline='\n')
    return len(entries)

def write_manifest():
    files=sorted(p for p in OUT.rglob('*') if p.is_file() and p.name!='manifest.json')
    manifest={p.relative_to(OUT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8',newline='\n')
    return files

def write_archive():
    """Use stable member order and metadata so approval and upload hashes agree."""
    archive=OUT.with_suffix('.zip')
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as package:
        for path in sorted(p for p in OUT.rglob('*') if p.is_file()):
            name=path.relative_to(OUT).as_posix()
            info=zipfile.ZipInfo(name,date_time=(1980,1,1,0,0,0))
            info.compress_type=zipfile.ZIP_DEFLATED
            info.external_attr=(0o100644 << 16)
            package.writestr(info,path.read_bytes(),compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
    return archive

def write_runtime_start():
    lock=json.loads(RUNTIME_LOCK.read_text(encoding='utf-8'))
    runtime_id=content_runtime_id(lock)
    report_path=ROOT/'builds'/('game-runtime-'+runtime_id+'.json')
    if not report_path.is_file():
        raise RuntimeError('Build the locked game runtime first: python tools/server_update/build_game_runtime.py')
    report=json.loads(report_path.read_text(encoding='utf-8'))
    archive=Path(report['archive'])
    if report.get('runtime_id')!=runtime_id or not archive.is_file():
        raise RuntimeError('Game runtime report does not match runtime.lock.json')
    actual=hashlib.sha256(archive.read_bytes()).hexdigest()
    if actual!=report.get('sha256'):
        raise RuntimeError('Game runtime archive SHA256 differs from its report')
    expected={
        'app/run_server.py':RUNTIME_APPS[0],
        'app/progression_service.py':RUNTIME_APPS[1],
        'app/progression_ledger.py':RUNTIME_APPS[2],
    }
    recorded=report.get('manifest',{}).get('application_sha256',{})
    for name,path in expected.items():
        if hashlib.sha256(path.read_bytes()).hexdigest()!=recorded.get(name):
            raise RuntimeError('Game runtime is stale; rebuild after source change: '+name)
    template=(ROOT/'server/game/start-runtime.sh.in').read_text(encoding='utf-8')
    rendered=(template.replace('@RUNTIME_ID@',runtime_id)
              .replace('@RUNTIME_ARCHIVE@',archive.name)
              .replace('@RUNTIME_SHA256@',actual)
              .replace('@LOCKED_SUPERVISOR_CODE@',(ROOT/'server/game/locked_supervisor.py').read_text(encoding='utf-8').rstrip()))
    (OUT/'start.sh').write_text(rendered,encoding='utf-8',newline='\n')
    return runtime_id

def main():
    if OUT.exists():
        if OUT.parent!=ROOT/'builds' or OUT.name!='island-server':
            raise RuntimeError(f'Refusing to clean unexpected output path: {OUT}')
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'.gdignore').write_text('',encoding='utf-8') # Exclude this nested project from client scans.
    for folder in ['core','model','content','effects','ai']:
        for p in (ROOT/'scripts/battle_v2'/folder).rglob('*.gd'):copy(p)
    for p in (ROOT/'scripts/server').glob('*.gd'):copy(p)
    copy(ROOT/'scripts/worlds/orchard_journey_rules.gd')
    copy(ROOT/'resources/fusion_3d/orchard_wilderness.json')
    for name in ['town_network','battle_wire','fusion_engine','world_one_ai','wardrobe_store']:
        copy(ROOT/f'scripts/fusion_3d/{name}.gd')
    # Keep authority/loadout helpers explicit.  Do not rely on a UI-side literal
    # reference to pull an economy dependency into the data-only server package.
    for name in ['island_loadout','island_ai_allies','equipment_rules']:
        copy(ROOT/f'scripts/worlds/{name}.gd')
    for p in (ROOT/'resources/battle_v2').rglob('*.json'):copy(p)
    for name in ['party_decks','showcase_decks','chapter_encounters','frost_encounter_progression','frost_circled_encounters','wing_mounts','teen_dye_catalog','teen_catalog','teen_hair_dye_catalog','teen_hat_hair_catalog','teen_hat_hair_v2_catalog','wardrobe_catalog','teen_sets','weekend_equipment','weekend_treasure_economy','weekend_shop_catalog','weekend_boss_wings']:
        copy(ROOT/f'resources/fusion_3d/{name}.json')
    copy(ROOT/'resources/fusion_3d/frost_starter_decks.json')
    # SO1's authenticated catalog shares the island process and must ship with it.
    copy(ROOT/'resources/fusion_3d/star_orchard_world1_server.json')
    copy(ROOT/'resources/fusion_3d/orchard_finale.json')
    wardrobe_source=(ROOT/'scripts/fusion_3d/wardrobe_store.gd').read_text(encoding='utf-8-sig')
    for relative in sorted(set(re.findall(r'res://(resources/fusion_3d/[^"\s]+\.json)',wardrobe_source))):
        copy(ROOT/relative)
    world=ROOT/'assets/worlds/frostroarisland_teen/world.json'
    data=json.loads(world.read_text(encoding='utf-8'))
    thin={k:data[k] for k in ['tile_size','origin']}
    thin['terrain']=[{k:t[k] for k in ['tile','height']} for t in data['terrain']]
    dest=OUT/world.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(json.dumps(thin),encoding='utf-8')
    for t in thin['terrain']:copy(ROOT/t['height'].removeprefix('res://'))
    (OUT/'project.godot').write_text('''config_version=5
[application]
config/name="Arcane Academy Island Server"
run/main_scene="res://server.tscn"
[autoload]
Wardrobe="*res://scripts/server/server_wardrobe.gd"
[rendering]
renderer/rendering_method="gl_compatibility"
''',encoding='utf-8')
    (OUT/'server.tscn').write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/server/island_server.gd" id="1"]
[node name="IslandServer" type="Node"]
script = ExtResource("1")
''',encoding='utf-8')
    # Keep the headless clients in the portable package so network regressions test the shipped files.
    for name in ['test_rules.gd','network_client.gd','multi_room_client.gd','flee_network_client.gd','connection_probe.gd','test_pvp.gd','pvp_network_client.gd']:copy(ROOT/'tests/server'/name)
    # The deployed helper permits test scripts only below tests/server/.
    for name in ['test_star_orchard_tutorial.gd','test_star_orchard_tutorial_room.gd','test_star_orchard_lesson_proposals.gd','test_orchard_live_resolution.gd','test_orchard_journey.gd','test_orchard_journey_reachability.gd','test_orchard_wilderness.gd']:
        copy(ROOT/'tests/server'/name)
    shutil.copy2(ROOT/'tests/battle_v2/test_frost_balance.gd',OUT/'tests/server/test_frost_balance.gd')
    shutil.copy2(ROOT/'tests/frost_t5/test_equipment.gd',OUT/'tests/server/test_t5_equipment.gd')
    for name in ['README.md','arcane-island.service']:
        p=ROOT/'server/game'/name
        if p.exists():shutil.copy2(p,OUT/name)
    write_runtime_start()
    class_count=write_global_class_cache()
    files=write_manifest()
    archive=write_archive()
    print(f'SERVER_PACKAGE {OUT} files={len(files)+1} bytes={sum(p.stat().st_size for p in files)+(OUT/"manifest.json").stat().st_size} global_classes={class_count} archive={archive}')
if __name__=='__main__':main()
