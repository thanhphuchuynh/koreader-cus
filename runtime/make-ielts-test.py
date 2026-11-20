"""Build an IELTS Reading test EPUB for Leaf from a JSON file.

Usage: python3 runtime/make-ielts-test.py <test.json> [out_dir=ielts/]
Input is the leaf-ielts.json schema (docs/superpowers/specs/2026-11-20-ielts-reading-design.md)
plus passages[i].paragraphs: [str]. Writes <out_dir>/<slug(title)>.epub: one chapter
OEBPS/passage<n>.xhtml per passage, and META-INF/leaf-ielts.json (input without paragraphs).
Exits 1 naming the problem on invalid input.
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

def validate(t):
    ps = t.get('passages') or []
    if not ps: raise ValueError('no passages')
    for p in ps:
        if not p.get('paragraphs'): raise ValueError(f"passage {p.get('n')} has no paragraphs")
    for q in t.get('questions', []):
        n = numbers(q)[0]
        key = 'answers' if q['type'] == 'multi' else 'answer'
        if not q.get(key): raise ValueError(f'question {n}: missing {key}')
        homes = [p for p in ps if all(p['from'] <= x <= p['to'] for x in numbers(q))]
        if not homes: raise ValueError(f'question {n} is in no passage range')
        ev = q.get('evidence')
        if ev and norm(ev) not in norm(' '.join(homes[0]['paragraphs'])):
            raise ValueError(f'question {n}: evidence not found in passage {homes[0]["n"]}: {ev!r}')

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
    slug = re.sub(r'[^a-z0-9]+', '-', t['title'].lower()).strip('-')
    out = Path(argv[2] if len(argv) == 3 else 'ielts')/f'{slug}.epub'
    demo.write_epub(out, escape(t['title']), f'leaf-ielts-{slug}', chapters, stem='passage',
                    extra={'META-INF/leaf-ielts.json': json.dumps(key, ensure_ascii=False, indent=1)})
    print(out)
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))
