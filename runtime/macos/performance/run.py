from pathlib import Path
import json, os, re, shutil, subprocess, time
root=Path(__file__).resolve().parent.parent
bench=root/'performance'
source=root/'test-data'
bookdir=bench/'books';bookdir.mkdir(exist_ok=True)
book=bookdir/'Sample.epub'
shutil.copy2(root/'books/The Other Side of the Bridge.epub',book)
if os.getenv('PERF_PAGING_ONLY'):
    from zipfile import ZipFile, ZIP_DEFLATED
    from html import escape
    with ZipFile(book) as z: contents={name:z.read(name) for name in z.namelist()}
    paragraph='Mara reluctantly agreed to leave the familiar village behind. Her bag waited by the door. Beyond the bridge, every path looked unfamiliar. She paused at the threshold and took one last look inside. By noon, the road had narrowed into a trail. '
    contents['OEBPS/chapter.xhtml']=('<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Long synthetic reading fixture</title></head><body><h1>Reading benchmark</h1>'+''.join('<p>'+str(i)+'. '+escape(paragraph*2)+'</p>' for i in range(1,121))+'</body></html>').encode()
    with ZipFile(book,'w',ZIP_DEFLATED) as z:
        for name,content in contents.items():z.writestr(name,content)
for variant in ('stock','simpleui','current'):
    target=bench/variant
    target.mkdir(exist_ok=True)
    settings=(source/'settings.reader.lua').read_text()
    settings=re.sub(r'\["extra_plugin_paths"\] = \{.*?\n    \},','["extra_plugin_paths"] = { "'+str(target/'plugins')+'" },',settings,flags=re.S)
    (target/'settings.reader.lua').write_text(settings)
    for dirname in ('settings','cache'):
        if (source/dirname).exists():shutil.copytree(source/dirname,target/dirname,dirs_exist_ok=True,ignore=shutil.ignore_patterns('english-ai.key*'))
    (target/'data').mkdir(exist_ok=True)
    link=target/'data/dict'
    if not link.exists():link.symlink_to(source/'data/dict',target_is_directory=True)
    (target/'plugins').mkdir(exist_ok=True)
    if variant in ('simpleui','current'):shutil.copytree(source/'plugins/simpleui.koplugin',target/'plugins/simpleui.koplugin',dirs_exist_ok=True)
    if variant=='current':shutil.copytree(source/'plugins/englishpreview.koplugin',target/'plugins/englishpreview.koplugin',dirs_exist_ok=True)
    (target/'patches').mkdir(exist_ok=True)
    shutil.copy2(bench/'probe.lua',target/'patches/2-performance.lua')
    if variant!='stock':shutil.copy2(source/'patches/2-dictionary-results.lua',target/'patches/2-dictionary-results.lua')
results=[]
# Rotate order so later variants do not always inherit warmer filesystem caches.
orders=(('stock','simpleui','current'),) if os.getenv('PERF_PAGING_ONLY') else (('stock','simpleui','current'),('current','stock','simpleui'),('simpleui','current','stock'))
for run,order in enumerate(orders,1):
    for variant in order:
        env=os.environ.copy();env.update(KO_HOME=str(bench/variant),EMULATE_READER_W='600',EMULATE_READER_H='800',EMULATE_READER_DPI='167')
        env.pop('KINDLE_ENGLISH_PREVIEW',None);env.pop('KINDLE_ENGLISH_WORD',None)
        started=time.monotonic(); ready=None;output=[];metrics=None
        proc=subprocess.Popen(['/usr/bin/time','-l',str(root/'KOReader.app/Contents/MacOS/koreader'),str(book)],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        for line in proc.stdout:
            output.append(line)
            if line.strip()=='PERF_READY':ready=(time.monotonic()-started)*1000
            if line.startswith('PERF_RESULT '):metrics=json.loads(line[len('PERF_RESULT '):])
        code=proc.wait(timeout=60)
        (bench/f'{variant}-{run}{"-paging" if os.getenv("PERF_PAGING_ONLY") else ""}.log').write_text(''.join(output))
        rss=re.search(r'(\d+)\s+maximum resident set size',''.join(output))
        record=dict(variant=variant,run=run,ready_wall_ms=ready,exit_code=code,peak_rss_bytes=int(rss.group(1)) if rss else None,metrics=metrics)
        results.append(record)
        (bench/('paging-results.json' if os.getenv('PERF_PAGING_ONLY') else 'results.json')).write_text(json.dumps(results,indent=2))
        print(json.dumps({k:v for k,v in record.items() if k!='metrics'}),flush=True)
        if not metrics:raise RuntimeError('Missing probe results; inspect log')
