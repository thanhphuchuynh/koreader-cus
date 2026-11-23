"""Build an IELTS Reading test EPUB for Leaf from a JSON file.

Usage: python3 runtime/make-ielts-test.py <test.json> [out_dir=ielts/]
Input is the leaf-ielts.json schema (docs/superpowers/specs/2026-11-20-ielts-reading-design.md)
plus passages[i].paragraphs: [str]. Writes <out_dir>/<slug(title)>.epub: one chapter
OEBPS/passage<n>.xhtml per passage, and META-INF/leaf-ielts.json (input without paragraphs).
TOEIC part sets add exam: "toeic", part: 1-7, optional question image (Part 1 photo beside the JSON,
stored as OEBPS/images/<name>), and may omit passages (a cover page is made).
Exits 1 naming the problem on invalid input. Each evidence is rewritten to its exact passage text.
"""
from html import escape
from pathlib import Path
import importlib.util, json, re, sys

_spec = importlib.util.spec_from_file_location('make_demo_epub', Path(__file__).with_name('make-demo-epub.py'))
demo = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(demo)

def norm(s):
    """Evidence matching: curly quotes/dashes folded, whitespace collapsed (Lua side does the same)."""
    s = s.translate(str.maketrans('’‘“”–—', '\'\'""--'))
    return re.sub(r'\s+', ' ', s).strip()

def numbers(q):
    return q['n'] if isinstance(q['n'], list) else [q['n']]

def is_int(x): return isinstance(x, int) and not isinstance(x, bool)
def is_num(x): return isinstance(x, (int, float)) and not isinstance(x, bool)

def find(ev, text):
    """The exact substring of text matching ev under norm(), or None (so the device search is exact)."""
    alt = {"'": "['’‘]", '"': '["“”]', '-': '[-–—]'}
    pat = r'\s+'.join(''.join(alt.get(c, re.escape(c)) for c in w) for w in norm(ev).split(' '))
    m = re.search(pat, text)
    return m and m.group(0)

PARTS = ['Photographs', 'Question–response', 'Conversations', 'Talks',
         'Incomplete sentences', 'Text completion', 'Reading passages']

def toeic_defaults(t):
    """TOEIC part sets: check exam/part; without passages, one cover page covering every question."""
    if 'exam' not in t: return
    if t['exam'] != 'toeic': raise ValueError(f"exam must be 'toeic', not {t['exam']!r}")
    p = t.get('part')
    if not (is_int(p) and 1 <= p <= 7): raise ValueError('toeic part must be an integer 1-7')
    if (p <= 4) != (t.get('skill') == 'listening'): raise ValueError('toeic parts 1-4 are listening, 5-7 reading')
    if not t.get('passages'):
        ns = [x for q in t.get('questions') or [] for x in numbers(q)] or [1]
        t['passages'] = [{'n': 1, 'from': min(ns), 'to': max(ns), 'title': f"Part {p} · {PARTS[p-1]}",
                          'paragraphs': [t.get('title', ''), 'Open Questions at the top to answer.']}]

def validate(t):
    """Checks everything the Kindle panel relies on; rewrites each evidence to its exact passage text."""
    toeic_defaults(t)
    ps = t.get('passages') or []
    if not ps: raise ValueError('no passages')
    for i, p in enumerate(ps, 1):
        if p.get('n') != i: raise ValueError(f'passages[{i-1}].n must be {i} (1-based, in order)')
        if not (is_int(p.get('from')) and is_int(p.get('to')) and p['from'] <= p['to']):
            raise ValueError(f'passage {i}: from/to must be integers with from <= to')
        if not p.get('paragraphs'): raise ValueError(f"passage {i} has no paragraphs")
    if t.get('skill') == 'listening':
        a = t.get('audio') if isinstance(t.get('audio'), dict) else {}
        if not (isinstance(a.get('file'), str) and a['file']): raise ValueError('audio.file must be a non-empty string')
        if not (is_int(a.get('rate')) and a['rate'] > 0): raise ValueError('audio.rate must be a positive integer')
        if not (is_num(a.get('seconds')) and a['seconds'] > 0): raise ValueError('audio.seconds must be a positive number')
    qs, seen = t.get('questions') or [], set()
    if not qs: raise ValueError('no questions')
    for q in qs:
        ns = numbers(q)
        if not ns or not all(is_int(x) for x in ns): raise ValueError(f"question {q.get('n')!r}: n must be an integer (multi: a list)")
        n, kind = ns[0], q.get('type')
        if seen & set(ns): raise ValueError(f'question {n}: number used twice')
        seen |= set(ns)
        if kind not in ('choice', 'multi', 'gap'): raise ValueError(f'question {n}: type must be choice, multi or gap, not {kind!r}')
        key = 'answers' if kind == 'multi' else 'answer'
        if not q.get(key): raise ValueError(f'question {n}: missing {key}')
        if kind == 'gap':
            if not (is_int(q.get('words')) and q['words'] > 0): raise ValueError(f'question {n}: gap needs words, a positive integer')
        else:
            opts = q.get('options')
            if not (isinstance(opts, list) and opts): raise ValueError(f'question {n}: {kind} needs non-empty options')
            want = q['answers'] if kind == 'multi' else [q['answer']]
            if not isinstance(want, list) or any(a not in opts for a in want):
                raise ValueError(f'question {n}: {key} {want!r} not among options {opts!r}')
        img = q.get('image')
        if img is not None and not (isinstance(img, str) and re.fullmatch(r'[\w.-]+\.(jpe?g|png)', img, re.I)):
            raise ValueError(f'question {n}: image must be a .jpg/.png file name beside the JSON')
        if kind == 'multi':
            if not isinstance(q['n'], list): raise ValueError(f'question {n}: multi n must be a list')
            if 'picks' in q and not (is_int(q['picks']) and 0 < q['picks'] <= len(ns)):
                raise ValueError(f'question {n}: picks must be 1..{len(ns)}')
        homes = [p for p in ps if all(p['from'] <= x <= p['to'] for x in ns)]
        if not homes: raise ValueError(f'question {n} is in no passage range')
        if t.get('skill') == 'listening':
            at = q.get('at')
            if at is not None and not (isinstance(at, list) and len(at) == 2 and all(is_num(x) for x in at)
                                       and 0 <= at[0] <= at[1] <= t['audio']['seconds']):
                raise ValueError(f"question {n}: at must be [from, to] seconds within the audio, 0 <= from <= to")
            acc = q.get('accept')
            if acc is not None and not (isinstance(acc, list) and all(isinstance(x, str) for x in acc)):
                raise ValueError(f'question {n}: accept must be a list of strings')
        ev = q.get('evidence')
        if ev:
            hit = next((h for h in (find(ev, x) for x in homes[0]['paragraphs']) if h), None)
            if not hit: raise ValueError(f'question {n}: evidence not found in one paragraph of passage {homes[0]["n"]}: {ev!r}')
            q['evidence'] = hit
    gaps = {x for q in qs if q['type'] == 'gap' for x in numbers(q)}
    for i, g in enumerate(t.get('groups') or []):
        if not (is_int(g.get('from')) and is_int(g.get('to')) and g['from'] <= g['to']):
            raise ValueError(f'groups[{i}]: from/to must be integers with from <= to')
        for k in ('title', 'instructions', 'text'):
            if k in g and not isinstance(g[k], str): raise ValueError(f'groups[{i}]: {k} must be a string')
        for m in re.findall(r'\{(\d+)\}', g.get('text', '')):
            if int(m) not in gaps: raise ValueError(f'groups[{i}]: {{{m}}} is not a gap question')

def main(argv):
    if not 2 <= len(argv) <= 3:
        sys.exit(__doc__)
    try:
        t = json.loads(Path(argv[1]).read_text(encoding='utf-8'))
        validate(t)
    except (OSError, ValueError, KeyError, TypeError) as e:
        print(f'error: {type(e).__name__ + ": " if not isinstance(e, ValueError) else ""}{e}', file=sys.stderr)
        return 1
    chapters = [(escape(p['title']), [escape(x) for x in p['paragraphs']]) for p in t['passages']]
    key = json.loads(json.dumps(t))
    for p in key['passages']: p.pop('paragraphs')
    images = {}
    for q in t['questions']:
        if q.get('image'):
            try: images['OEBPS/images/' + q['image']] = (Path(argv[1]).parent/q['image']).read_bytes()
            except OSError as e:
                print(f"error: question image {q['image']!r}: {e.strerror}", file=sys.stderr); return 1
    slug = re.sub(r'[^a-z0-9]+', '-', t['title'].lower()).strip('-')
    out = Path(argv[2] if len(argv) == 3 else 'ielts')/f'{slug}.epub'
    demo.write_epub(out, escape(t['title']), f'leaf-ielts-{slug}', chapters, stem='passage',
                    extra={'META-INF/leaf-ielts.json': json.dumps(key, ensure_ascii=False, indent=1), **images})
    print(out)
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))
