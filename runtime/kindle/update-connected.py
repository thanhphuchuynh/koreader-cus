"""Apply the prepared plugin update without replacing device settings or reading data."""
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
import hashlib,json,os,shutil,sys

root=Path(__file__).resolve().parent
stage=root/'staging/koreadercus'
device=Path('/Volumes/Kindle')
assert device.is_mount(), 'Kindle is not mounted'
assert '5.18.5.0.1' in (device/'system/version.txt').read_text()
assert (device/'koreader/git-rev').read_text().strip()=='v2026.03'
assert (device/'koreadercus/git-rev').read_text().strip()=='v2026.07.2-280-g400ba0e_2026-10-24_kindlehf'
backup=root/'backups'/(datetime.now(ZoneInfo('Asia/Ho_Chi_Minh')).strftime('%Y%m%d-%H%M%S')+'-update')
backup.mkdir(parents=True,mode=0o700)
os.chmod(backup,0o700)

def digest(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def copy_data(src,dst):
    with src.open('rb') as inp,dst.open('xb') as out:
        shutil.copyfileobj(inp,out)
        out.flush();os.fsync(out.fileno())

def archive(relative):
    src=device/relative;dst=backup/relative
    dst.parent.mkdir(parents=True,exist_ok=True)
    expected=digest(src)
    copy_data(src,dst);os.chmod(dst,0o600)
    assert digest(dst)==expected and digest(src)==expected, 'Backup verification failed'
    return expected

plugin=Path('profile/plugins/englishpreview.koplugin')
# New dependencies first; entry point last. Never copy profile settings or databases.
# Offline voice (voca binary + model) before the Lua that uses it.
updates=sorted(p.relative_to(stage) for p in (stage/plugin/'voca').rglob('*') if p.is_file() and not p.name.startswith('._'))
updates.append(plugin/'english_phrases.tsv')  # offline idiom index
updates+=sorted((p.relative_to(stage) for p in (stage/plugin).glob('*.lua')),key=lambda p:(p.name=='main.lua',p.name))
updates.extend(Path('profile/patches')/name for name in ('2-dictionary-results.lua','2-hide-crash-reports.lua'))
updates.append(Path('profile/plugins/simpleui.koplugin/screens/sui_settings_window.lua'))
updates.append(Path('README-KOReaderCus.txt'))
if '--ai-only' in sys.argv:
    updates=[plugin/'english_ai.lua',plugin/'english_ai_client.lua',Path('README-KOReaderCus.txt')]
expected_updates=list(updates)
updates=[p for p in updates if not (device/'koreadercus'/p).exists() or digest(stage/p)!=digest(device/'koreadercus'/p)]
update_paths={str(Path('koreadercus')/p) for p in updates}
metadata_paths={str(Path('koreadercus')/p.parent/('._'+p.name)) for p in updates}
for p in ('frontend/docsettings.lua','frontend/ui/otamanager.lua','launch.sh'):
    assert digest(stage/p)==digest(device/'koreadercus'/p), 'Custom isolation changed; inspect before updating'
logs={} if '--plugin-only' in sys.argv or '--ai-only' in sys.argv else {'adbreak.log':554,'koreadercus/crash.log':19306,'koreader/crash.log':178744}
for name,size in logs.items():assert (device/name).stat().st_size==size, 'Audit candidate changed'

# Record and later verify everything in the original reader and custom profile,
# except the explicitly updated plugin and the standalone log selected for removal.
def protected():
    result={}
    for base in (device/'koreader',device/'koreadercus/profile'):
        for p in base.rglob('*'):
            if not p.is_file():continue
            rel=p.relative_to(device).as_posix()
            if rel in logs or rel in update_paths or rel in metadata_paths:continue
            result[rel]=digest(p)
    for name in ('documents/koreader.sh','documents/KOReaderCus.sh','koreadercus/launch.sh'):
        result[name]=digest(device/name)
    return result

print('Fingerprinting original reader and custom reading data...',flush=True)
before=protected()
(backup/'protected-manifest.json').write_text(json.dumps(before,indent=2))
journal=[]
for rel in updates:
    target=Path('koreadercus')/rel
    exists=(device/target).exists()
    old=archive(target) if exists else None
    journal.append({'path':str(target),'previous_sha256':old,'new_sha256':digest(stage/rel)})
for name in logs:archive(name)
(backup/'update-journal.json').write_text(json.dumps(journal,indent=2))
cleanup=[{'path':name,'bytes':size,'sha256':digest(backup/name)} for name,size in logs.items()]
(backup/'cleanup-restore-map.json').write_text(json.dumps(cleanup,indent=2))

changed=[]
try:
    for entry,rel in zip(journal,updates):
        dst=device/entry['path'];temp=dst.with_name(dst.name+'.cus-update')
        dst.parent.mkdir(parents=True,exist_ok=True)
        assert not temp.exists(), 'An unfinished update needs inspection'
        copy_data(stage/rel,temp)
        assert digest(temp)==entry['new_sha256'], 'Staged device copy differs'
        os.replace(temp,dst);changed.append(entry)
        assert digest(dst)==entry['new_sha256']
    for rel in expected_updates:
        assert digest(stage/rel)==digest(device/'koreadercus'/rel), 'Installed update differs'
    # Clean metadata generated only for the explicitly updated code and README.
    for rel in updates:
        target=device/'koreadercus'/rel
        metadata=target.with_name('._'+target.name)
        if metadata.exists():
            with metadata.open('rb') as f:assert f.read(4)==b'\x00\x05\x16\x07'
            archive(metadata.relative_to(device))
            metadata.unlink()
    print('Plugin files verified. Checking books/settings/profile protection...',flush=True)
    assert protected()==before, 'Protected files changed unexpectedly'
except Exception:
    for entry in reversed(changed):
        dst=device/entry['path']
        if entry['previous_sha256'] is None:dst.unlink()
        else:
            temp=dst.with_name(dst.name+'.rollback')
            copy_data(backup/entry['path'],temp);os.replace(temp,dst)
    raise

for entry in cleanup:
    p=device/entry['path']
    assert digest(p)==entry['sha256'], 'Log changed; leaving original in place'
    p.unlink()
os.sync()
result={'updated_files':len(updates),'plugin_verified':True,'protected_files_verified':len(before),
        'removed_log_bytes':sum(logs.values()),'free_bytes':shutil.disk_usage(device).free,
        'backup':str(backup),'physical_launch_tested':False}
(backup/'result.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2),flush=True)
