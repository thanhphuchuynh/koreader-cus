"""Remove verified orphan metadata for deleted Kindle reports, never book sidecars."""
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
import hashlib,json,os,re,shutil

volume=Path('/Volumes/Kindle');assert volume.is_mount()
documents=volume/'documents'
pattern=re.compile(r'^(pillowd|mesquite|wifilocker)_\d+_\d+-.+_crash_.+\.sdr$')
folders=sorted(p for p in documents.iterdir() if p.is_dir() and pattern.fullmatch(p.name))
assert len(folders)==38
for p in folders:
 assert not p.is_symlink() and p.parent==documents
 for suffix in ('.txt','.tgz','.core','.txt.asc','.tgz.asc'):
  assert not p.with_suffix(suffix).exists(), 'Report still exists; not an orphan'
metadata=sorted(p for p in documents.glob('._*') if p.is_file())
assert len(metadata)==4
for p in metadata:
 with p.open('rb') as f:assert f.read(4)==b'\x00\x05\x16\x07'
 # Includes two inspected orphan AppleDouble files; all four are metadata only.
backup=Path(__file__).resolve().parent/'backups'/(datetime.now(ZoneInfo('Asia/Ho_Chi_Minh')).strftime('%Y%m%d-%H%M%S')+'-orphan-diagnostics')
backup.mkdir(parents=True,mode=0o700);os.chmod(backup,0o700)

def digest(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def owned(p):
 return p in metadata or any(p.is_relative_to(folder) for folder in folders)
def protected():
 return {str(p.relative_to(documents)):(p.stat().st_size,p.stat().st_mtime_ns)
  for p in documents.rglob('*') if p.is_file() and not owned(p)}
before=protected()
records=[]
for src in [p for folder in folders for p in folder.rglob('*') if p.is_file()]+metadata:
 dst=backup/src.relative_to(documents);dst.parent.mkdir(parents=True,exist_ok=True)
 expected=digest(src)
 with src.open('rb') as inp,dst.open('xb') as out:shutil.copyfileobj(inp,out)
 os.chmod(dst,0o600)
 assert digest(dst)==expected and digest(src)==expected
 records.append({'path':str(src.relative_to(volume)),'bytes':src.stat().st_size,'sha256':expected})
(backup/'restore-map.json').write_text(json.dumps(records,indent=2))
for record in records:assert digest(volume/record['path'])==record['sha256']
for folder in folders:shutil.rmtree(folder)
for p in metadata:p.unlink()
assert protected()==before, 'Other Documents files changed'
os.sync()
result={'orphan_report_folders_removed':len(folders),'macos_metadata_files_removed':len(metadata),
 'backed_up_files':len(records),'other_files_preserved':len(before),'backup':str(backup)}
(backup/'result.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
