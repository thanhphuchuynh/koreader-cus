"""Install new files only, verify them, and archive two named crash dumps before removal."""
from pathlib import Path
import hashlib, json, shutil, datetime, os

root=Path(__file__).resolve().parent
stage=root/'staging'
device=Path('/Volumes/Kindle')
assert device.is_mount(), 'Kindle is not mounted'
assert (device/'koreader/git-rev').read_text().strip()=='v2026.03', 'Original version changed; inspect first'
assert '5.18.5.0.1' in (device/'system/version.txt').read_text(), 'Unexpected device firmware'
pairs=[(stage/'koreadercus',device/'koreadercus'),
       (stage/'KOReaderCus.sh',device/'documents/KOReaderCus.sh'),
       (stage/'kual-koreadercus',device/'extensions/koreadercus')]
for src,dst in pairs:
    assert src.exists() and not dst.exists(), f'Refusing overwrite: {dst}'
assert not list((stage/'koreadercus/profile').rglob('*.key'))
backup=root/'backups'/datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backup.mkdir(parents=True,mode=0o700)
os.chmod(backup,0o700)

def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()

def manifest(directory):
    return {p.relative_to(directory).as_posix():{'size':p.stat().st_size,'sha256':digest(p)}
            for p in sorted(directory.rglob('*')) if p.is_file()}

def verify_copy(directory, expected):
    actual=manifest(directory)
    # macOS can create AppleDouble metadata on FAT even for a data-only copy.
    # Remove only extra, recognized metadata files inside our new installation.
    assert expected.keys() <= actual.keys(), 'Missing program files'
    assert all(actual[name]==value for name,value in expected.items()), 'Program bytes differ'
    for name in actual.keys()-expected.keys():
        path=directory/name
        assert path.name.startswith('._'), f'Unexpected extra file: {name}'
        with path.open('rb') as f:assert f.read(4)==b'\x00\x05\x16\x07', 'Not AppleDouble metadata'
        path.unlink()
    assert manifest(directory)==expected, f'Copy verification failed: {directory}'

print('Fingerprinting original KOReader before installation...',flush=True)
original=manifest(device/'koreader')
launcher_hash=digest(device/'documents/koreader.sh')
(backup/'original-reader-manifest.json').write_text(json.dumps(original,indent=2))
(backup/'original-launcher.sha256').write_text(launcher_hash+'\n')
print('Copying KOReaderCus into a new directory...',flush=True)
installed={}
for src,dst in pairs:
    if src.is_dir():
        expected=manifest(src)
        temporary=dst.with_name(dst.name+'.installing')
        if not temporary.exists():
            shutil.copytree(src,temporary,copy_function=shutil.copyfile)
        verify_copy(temporary,expected)
        temporary.rename(dst)
        installed[str(dst.relative_to(device))]=expected
    else:
        # Exclusive creation also protects against an unexpected concurrent file.
        with dst.open('xb') as out,src.open('rb') as inp:shutil.copyfileobj(inp,out)
        assert digest(dst)==digest(src), 'Launcher verification failed'
        installed[str(dst.relative_to(device))]={'sha256':digest(dst)}
    print('Verified '+str(dst.relative_to(device)),flush=True)
(backup/'installed-manifest.json').write_text(json.dumps(installed,indent=2))
print('Checking original installation is unchanged...',flush=True)
assert manifest(device/'koreader')==original, 'Original reader changed unexpectedly'
assert digest(device/'documents/koreader.sh')==launcher_hash, 'Original launcher changed unexpectedly'

# Only these explicitly audited dumps may be removed; their verified backups stay on the Mac.
dumps={
 'mesquite_19162_001-juno_18050001_cava_bellatrix-455678.core':90876312,
 'wifilocker_3365_001-juno_18050001_cava_bellatrix-455678.core':47671000,
}
cleanup=[]
for name,size in dumps.items():
    src=device/name;dst=backup/name
    assert src.is_file() and src.stat().st_size==size, 'Crash dump changed; leaving it in place'
    before=digest(src)
    shutil.copyfile(src,dst);os.chmod(dst,0o600)
    assert digest(dst)==before and digest(src)==before, 'Backup verification failed; leaving original'
    cleanup.append({'kindle_path':str(src),'backup_path':str(dst),'size':size,'sha256':before})
(backup/'cleanup-restore-map.json').write_text(json.dumps(cleanup,indent=2))
for item in cleanup:
    src=Path(item['kindle_path'])
    assert digest(src)==item['sha256'], 'Dump changed; stop cleanup'
    src.unlink()
os.sync()
result={'backup':str(backup),'reclaimed_bytes':sum(x['size'] for x in cleanup),
        'free_bytes':shutil.disk_usage(device).free,
        'installed_files':sum(len(v) if isinstance(v,dict) and 'sha256' not in v else 1 for v in installed.values()),
        'original_reader_verified_unchanged':True,'physical_launch_tested':False}
(backup/'result.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2),flush=True)
