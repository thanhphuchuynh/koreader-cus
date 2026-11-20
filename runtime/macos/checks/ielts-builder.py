"""Check runtime/make-ielts-test.py: packaging, embedded JSON, validation, quote normalization."""
import copy, json, subprocess, sys, tempfile, zipfile
from pathlib import Path
root = Path(__file__).resolve().parents[3]
script, sample = root/'runtime/make-ielts-test.py', root/'runtime/ielts-sample.json'
src = json.loads(sample.read_text())
tmp = Path(tempfile.mkdtemp(prefix='ielts-builder-'))

def build(data, name='t'):
    f = tmp/f'{name}.json'
    f.write_text(json.dumps(data, ensure_ascii=False))
    out = tmp/f'out-{name}'
    return subprocess.run([sys.executable, '-I', str(script), str(f), str(out)], text=True, capture_output=True), out

r, out = build(src, 'ok')
assert r.returncode == 0, r.stderr
epub = Path(r.stdout.strip())
assert epub.exists() and epub.parent == out, r.stdout
z = zipfile.ZipFile(epub)
first = z.infolist()[0]
assert first.filename == 'mimetype' and first.compress_type == zipfile.ZIP_STORED
assert 'OEBPS/passage1.xhtml' in z.namelist()
expect = copy.deepcopy(src)
for p in expect['passages']: p.pop('paragraphs')
assert json.loads(z.read('META-INF/leaf-ielts.json')) == expect

def expect_fail(mutate, *words, name):
    d = copy.deepcopy(src); mutate(d)
    r, _ = build(d, name)
    assert r.returncode == 1, (name, r.returncode, r.stderr)
    for w in words: assert w in r.stderr, (name, w, r.stderr)

def q(d, n): return next(x for x in d['questions'] if x['n'] == n or x['n'] == [n, n+1])
expect_fail(lambda d: q(d, 3).pop('answers'), 'question 3', name='noanswer')
expect_fail(lambda d: q(d, 1).update(evidence='nothing like this in the text'), 'evidence', '1', name='badev')
expect_fail(lambda d: d['passages'][0].update({'to': 5}), 'question 6', name='range')

d = copy.deepcopy(src)
d['passages'][0]['paragraphs'][0] += ' It’s “fine” – really.'
q(d, 1)['evidence'] = 'It\'s "fine" - really.'
r, _ = build(d, 'quotes')
assert r.returncode == 0, r.stderr
print('PASS: ielts-builder')
