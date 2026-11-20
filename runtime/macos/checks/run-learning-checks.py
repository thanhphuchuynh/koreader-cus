"""Run reader checks using the bundled LuaJIT and isolated temporary profiles."""
from pathlib import Path
import os,subprocess,tempfile,sys
root=Path(__file__).resolve().parents[3]
app=root/'runtime/macos/KOReader.app/Contents/koreader'
plugin=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else root/'runtime/macos/test-data/plugins/englishpreview.koplugin'
checks=Path(__file__).resolve().parent
failed=False
cases=[('english-preview.lua',plugin/'main.lua'),('tap-dictionary.lua',plugin/'main.lua'),
       ('english-ai-client.lua',plugin/'english_ai_client.lua'),('english-ai-ui.lua',None),
       ('english-vocabulary.lua',plugin),('english-cache.lua',plugin)]
if (checks/'english-performance.lua').exists():cases.append(('english-performance.lua',plugin))
if (checks/'english-speech.lua').exists():cases.append(('english-speech.lua',plugin))
if (checks/'english-voca.lua').exists():cases.append(('english-voca.lua',plugin))
if (checks/'english-context.lua').exists():cases.append(('english-context.lua',plugin))
if (checks/'english-ielts.lua').exists():cases.append(('english-ielts.lua',plugin))
if (checks/'english-phrases.lua').exists():cases.append(('english-phrases.lua',plugin))
cases.append(('simpleui-ai-settings.lua',plugin.parent/'simpleui.koplugin/screens/sui_settings_window.lua'))
for name,arg in cases:
 with tempfile.TemporaryDirectory(prefix='kindle-learning-') as directory:
  env=os.environ.copy();env.update(KO_HOME=directory,DYLD_LIBRARY_PATH=str(app/'libs'),
   LUA_PATH=f'{plugin}/?.lua;{app}/?.lua;{app}/frontend/?.lua;{app}/common/?.lua;;',LUA_CPATH=f'{app}/common/?.so;;')
  result=subprocess.run([str(app/'luajit'),str(checks/name),str(arg or directory)],env=env,cwd=app,text=True,capture_output=True)
  print(name+': '+('PASS' if result.returncode==0 else 'FAIL'))
  print('\n'.join(line for line in result.stdout.splitlines() if line.startswith('PASS:')))
  if result.returncode:failed=True;print(result.stderr)
for check in sorted(checks.glob('*.py')):
 if check.name==Path(__file__).name:continue
 result=subprocess.run([sys.executable,'-I',str(check)],text=True,capture_output=True)
 print(check.name+': '+('PASS' if result.returncode==0 else 'FAIL'))
 if result.returncode:failed=True;print(result.stdout+result.stderr)
raise SystemExit(int(failed))
