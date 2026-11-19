from pathlib import Path
import json,subprocess,time
root=Path(__file__).resolve().parent.parent
rows=[]
for repeat in range(5):
 for word in ('noon','reluctantly','unfamiliar','threshold','qzxqzxmissing'):
  started=time.perf_counter()
  result=subprocess.run([str(root/'KOReader.app/Contents/koreader/sdcv'),'--utf8-input','--utf8-output','--json-output','--non-interactive','--exact-search','--data-dir',str(root/'test-data/data/dict'),'--',word],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  rows.append(dict(word=word,repeat=repeat,ms=(time.perf_counter()-started)*1000,exit_code=result.returncode,output_bytes=len(result.stdout)))
(root/'performance/direct-sdcv.json').write_text(json.dumps(rows,indent=2))
print('Measured',len(rows),'direct dictionary processes')
