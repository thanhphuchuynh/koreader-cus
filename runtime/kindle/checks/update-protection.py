from pathlib import Path
import ast,hashlib,tempfile
source=Path(__file__).resolve().parents[1]/'update-connected.py'
functions=ast.Module(body=[n for n in ast.parse(source.read_text()).body if isinstance(n,ast.FunctionDef) and n.name in ('digest','protected')],type_ignores=[])
with tempfile.TemporaryDirectory() as directory:
 device=Path(directory)
 paths=['koreader/reader.lua','koreadercus/profile/settings/english-ai.key','koreadercus/profile/patches/2-hide-crash-reports.lua','documents/koreader.sh','documents/KOReaderCus.sh','koreadercus/launch.sh']
 for name in paths:
  p=device/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('fixture')
 owned='koreadercus/profile/patches/2-hide-crash-reports.lua'
 metadata='koreadercus/profile/patches/._2-hide-crash-reports.lua'
 scope={'device':device,'logs':{},'update_paths':{owned},'metadata_paths':{metadata},'hashlib':hashlib}
 exec(compile(functions,str(source),'exec'),scope)
 before=scope['protected']()
 (device/owned).write_text('updated patch');(device/metadata).write_bytes(b'AppleDouble fixture')
 assert scope['protected']()==before,'owned code and its transfer metadata belong to the update'
 key=device/'koreadercus/profile/settings/english-ai.key';key.write_text('changed fixture')
 assert scope['protected']()!=before,'unrelated credentials must remain protected'
print('PASS: only owned update paths and their metadata are excluded; unrelated credentials stay protected')
