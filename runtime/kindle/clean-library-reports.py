"""Archive exact Kindle diagnostic reports; keep every other Documents entry."""
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
import hashlib,json,os,re,shutil

root=Path(__file__).resolve().parent
volume=Path('/Volumes/Kindle')
assert volume.is_mount()
documents=volume/'documents'
pattern=re.compile(r'^(pillowd|mesquite|wifilocker)_\d+_.+_crash_.+\.(txt|tgz)(\.asc)?$')
files=sorted(p for p in documents.iterdir() if p.is_file() and pattern.fullmatch(p.name))
assert len(files)==73 and sum(p.stat().st_size for p in files)==138306832, 'Audit changed; inspect first'
backup=root/'backups'/(datetime.now(ZoneInfo('Asia/Ho_Chi_Minh')).strftime('%Y%m%d-%H%M%S')+'-library-reports')
backup.mkdir(parents=True,mode=0o700);os.chmod(backup,0o700)

def digest(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def preserve():
 return {str(p.relative_to(documents)):(p.stat().st_size,p.stat().st_mtime_ns)
         for p in documents.rglob('*') if p.is_file() and p not in files}
protected=preserve()
clippings=documents/'My Clippings.txt'
clippings_hash=digest(clippings)
records=[]
print('Backing up 73 diagnostic reports and verifying hashes...',flush=True)
for src in files:
 dst=backup/src.name
 expected=digest(src)
 with src.open('rb') as inp,dst.open('xb') as out:shutil.copyfileobj(inp,out)
 os.chmod(dst,0o600)
 assert digest(dst)==expected and digest(src)==expected
 records.append({'path':str(src.relative_to(volume)),'backup':str(dst),'bytes':src.stat().st_size,'sha256':expected})
(backup/'restore-map.json').write_text(json.dumps(records,indent=2))
# Install the narrow native file-exclusion patch without replacing other settings.
source=root/'staging/koreadercus/profile/patches/2-hide-crash-reports.lua'
target=volume/'koreadercus/profile/patches'/source.name
assert not target.exists(), 'Filter already exists; inspect instead of overwriting'
with source.open('rb') as inp,target.open('xb') as out:shutil.copyfileobj(inp,out)
assert digest(source)==digest(target)
print('Backups verified; removing only the audited reports...',flush=True)
for record in records:
 p=volume/record['path']
 assert digest(p)==record['sha256']
 p.unlink()
# Remove only metadata generated for this new patch, if macOS created it.
metadata=target.with_name('._'+target.name)
if metadata.exists():
 with metadata.open('rb') as f:assert f.read(4)==b'\x00\x05\x16\x07'
 with metadata.open('rb') as inp,(backup/'patch-appledouble').open('xb') as out:shutil.copyfileobj(inp,out)
 assert digest(metadata)==digest(backup/'patch-appledouble')
 metadata.unlink()
assert preserve()==protected and digest(clippings)==clippings_hash, 'Other Documents entries changed'
assert not any(pattern.fullmatch(p.name) for p in documents.iterdir() if p.is_file())
os.sync()
result={'removed_reports':len(records),'reclaimed_bytes':sum(r['bytes'] for r in records),
        'other_documents_preserved':len(protected),'clippings_verified':True,
        'future_report_filter_installed':True,'backup':str(backup),'free_bytes':shutil.disk_usage(volume).free}
(backup/'result.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2),flush=True)
