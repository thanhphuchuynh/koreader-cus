"""Install only Leaf presentation assets; keep runtime, books and settings intact."""
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
import hashlib,json,os,shutil

root=Path(__file__).resolve().parents[1]
stage=root/'kindle/staging'
device=Path('/Volumes/Kindle')
files={
 'documents/KOReaderCus.sh':stage/'KOReaderCus.sh',
 'documents/KOReaderCus.sh.sdr/icon.png':root/'branding/leaf-cover.png',
 'extensions/koreadercus/menu.json':stage/'kual-koreadercus/menu.json',
 'extensions/koreadercus/config.xml':stage/'kual-koreadercus/config.xml',
}
for name in ('resources/koreader.svg','resources/koreader.png',
             'profile/patches/2-leaf-branding.lua','README-KOReaderCus.txt'):
 files['koreadercus/'+name]=stage/'koreadercus'/name

def digest(path):
 with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def copy(source,target):
 with source.open('rb') as inp,target.open('xb') as out:
  shutil.copyfileobj(inp,out);out.flush();os.fsync(out.fileno())
 assert digest(source)==digest(target)

def protected():
 result={}
 for name in ('documents','koreader','koreadercus','extensions/koreadercus'):
  for p in (device/name).rglob('*'):
   if p.is_file():
    relative=p.relative_to(device).as_posix()
    if relative not in files and relative not in metadata:result[relative]=digest(p)
 return result

if __name__=='__main__':
 assert device.is_mount(),'Kindle is not mounted'
 assert (device/'koreader/git-rev').read_text().strip()=='v2026.03'
 assert (device/'koreadercus/git-rev').read_text().strip()=='v2026.07.2-280-g400ba0e_2026-10-24_kindlehf'
 assert all(p.is_file() for p in files.values())
 files={relative:source for relative,source in files.items() if not (device/relative).is_file() or digest(source)!=digest(device/relative)}
 if not files:
  print('Leaf branding is already up to date.');raise SystemExit(0)
 metadata={str(Path(p).with_name('._'+Path(p).name)) for p in files}
 backup=root/'kindle/backups'/(datetime.now(ZoneInfo('Asia/Ho_Chi_Minh')).strftime('%Y%m%d-%H%M%S')+'-leaf-branding')
 backup.mkdir(mode=0o700)
 print('Checking books, original reader and custom settings...',flush=True)
 before=protected()
 originals={}
 for relative in files.keys() | metadata:
  p=device/relative
  if p.exists():
   if relative in metadata:
    with p.open('rb') as f:assert f.read(4)==b'\x00\x05\x16\x07','Unexpected metadata file'
   saved=backup/relative;saved.parent.mkdir(parents=True,exist_ok=True)
   copy(p,saved);originals[relative]=digest(p)
  else:originals[relative]=None
 changed=[]
 try:
  for relative,source in files.items():
   target=device/relative;temp=target.with_name(target.name+'.leaf-update')
   assert not temp.exists(),'Unfinished update found'
   try:
    copy(source,temp);os.replace(temp,target);changed.append(relative)
   finally:
    temp.unlink(missing_ok=True)
  for relative in metadata:
   p=device/relative
   if p.exists():p.unlink();changed.append(relative)
  assert all(digest(device/p)==digest(source) for p,source in files.items())
  assert protected()==before,'Protected data changed unexpectedly'
 except BaseException:
  for relative in reversed(changed):
   target=device/relative
   if originals[relative] is None:target.unlink(missing_ok=True)
   else:
    temp=target.with_name(target.name+'.leaf-rollback')
    copy(backup/relative,temp);os.replace(temp,target)
  raise
 os.sync()
 result={'name':'Leaf','updated_files':list(files),'protected_files_verified':len(before),'backup':str(backup),'device_ui_tested':False}
 (backup/'result.json').write_text(json.dumps(result,indent=2))
 print(json.dumps(result,indent=2))
