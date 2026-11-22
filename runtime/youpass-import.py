"""Import public IELTS Reading tests from youpass.vn into Leaf test EPUBs (personal use).

Usage: python3 runtime/youpass-import.py [--count N] [quiz_id ...]
No ids: takes the newest N (default 10) free tests from the reading list. Skips PRO tests and
tests with question types Leaf can't show (diagram labels). Writes ielts/<slug>.epub (gitignored)
via make-ielts-test.py; the intermediate JSON goes to ielts/json/.
"""
from pathlib import Path
import html, importlib.util, json, re, sys, urllib.request

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location('mk', Path(__file__).with_name('make-ielts-test.py'))
mk = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(mk)

def fetch(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'}), timeout=30).read().decode()

def api(path): return json.loads(fetch('https://api.youpass.vn' + path))['data']

def text(h):
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', h or ''))).strip()

def paragraphs(quiz_id, part_ids):
    """Passage text is only in the practice page payload: part.vocabs = paragraphs > sentences."""
    page = fetch(f'https://youpass.vn/practice/reading/{quiz_id}')
    rsc = ''.join(json.loads('"' + m + '"') for m in re.findall(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)', page))
    out = {}
    for pid in part_ids:
        i = rsc.find(f'"id":{pid},"quiz_id"')
        if i < 0: raise ValueError(f'part {pid} text not found')
        j = rsc.find('"vocabs":[', i) + len('"vocabs":')
        tree, _ = json.JSONDecoder().raw_decode(rsc[j:])
        out[pid] = [[s['value'].strip() for s in p['children']] for p in tree if p['children']]
    return out

def words(desc):
    d = desc.upper()
    if 'ONE WORD AND/OR A NUMBER' in d: return 2
    for w, n in (('ONE WORD', 1), ('TWO WORDS', 2), ('THREE WORDS', 3)):
        if w in d: return n
    return 3

def convert(d):
    parts = d['parts'] or []
    sents = paragraphs(d['id'], [p['id'] for p in parts])
    t = {'version': 1, 'title': re.sub(r'^\[[^\]]*\]\s*', '', d['title']).strip(), 'minutes': d['time'] or 20,
         'passages': [], 'groups': [], 'questions': []}
    for pn, p in enumerate(parts, 1):
        paras = sents[p['id']]
        lo = hi = None
        for s in p['question_sets']:
            desc, opts = text(s['description']), s['options'] or []
            kind = s['questions'][0]['question_type'] if s['questions'] else ''
            g = {'title': s['title'], 'instructions': desc}
            if opts and any(o['text'].strip() != o['option'] for o in opts):
                g['list'] = [f"{o['option']}  {o['text'].strip()}" for o in opts]
            for q in s['questions']:
                n = q['order']
                if kind == 'MULTIPLE_CHOICE_MANY':
                    k = int(s['question_count']); ns = list(range(n, n + k))
                    g['list'] = [f"{o['option']}  {o['text'].strip()}" for o in q['options']]
                    item = {'n': ns, 'type': 'multi', 'picks': k, 'text': q['text'],
                            'options': [o['option'] for o in q['options']],
                            'answers': [o['option'] for o in q['options'] if o.get('is_correct')]}
                elif q.get('options'):  # multiple choice, one answer: option texts under the question
                    ns = [n]
                    item = {'n': n, 'type': 'choice', 'options': [o['option'] for o in q['options']],
                            'text': q['text'] + ''.join(f"\n{o['option']}  {o['text'].strip()}" for o in q['options']),
                            'answer': q['correct_answer']}
                elif opts:
                    ns = [n]
                    item = {'n': n, 'type': 'choice', 'text': q['text'], 'options': [o['option'] for o in opts],
                            'answer': q['correct_answer']}
                else:
                    ns = [n]
                    if not q['correct_answer'] or '___' not in q['text']:
                        raise ValueError(f'Q{n}: {kind} without text/answer (diagram?)')
                    before, after = q['text'].split('___', 1)
                    item = {'n': n, 'type': 'gap', 'words': words(desc), 'before': before.strip(),
                            'after': after.strip(' _'), 'answer': q['correct_answer'].strip()}
                ev = (q.get('locate_info') or {}).get('paragraph_ranges') or []
                if ev:
                    a, b = ev[0]['start'], ev[0]['end']
                    para = paras[a['paragraph'] - 1] if 0 < a['paragraph'] <= len(paras) else []
                    if a['paragraph'] == b['paragraph'] and para:
                        item['evidence'] = ' '.join(para[a['sentence'] - 1:b['sentence']])
                t['questions'].append(item)
                lo = min(lo or ns[0], ns[0]); hi = max(hi or ns[-1], ns[-1])
            nums = [x for q in s['questions'] for x in ([q['order']] if kind != 'MULTIPLE_CHOICE_MANY' else range(q['order'], q['order'] + int(s['question_count'])))]
            g['from'], g['to'] = min(nums), max(nums)
            t['groups'].append(g)
        t['passages'].append({'n': pn, 'title': p['title'], 'from': lo, 'to': hi, 'paragraphs': [' '.join(x) for x in paras]})
    return t

def build(t, out):
    (out / 'json').mkdir(parents=True, exist_ok=True)
    slug = re.sub(r'[^a-z0-9]+', '-', t['title'].lower()).strip('-')
    f = out / 'json' / f'{slug}.json'
    f.write_text(json.dumps(t, ensure_ascii=False, indent=1), encoding='utf-8')
    try:
        mk.validate(json.loads(f.read_text()))
    except ValueError as e:  # evidence that doesn't match exactly: keep the test, drop the evidence
        if 'evidence' not in str(e): raise
        for q in t['questions']: q.pop('evidence', None)
        f.write_text(json.dumps(t, ensure_ascii=False, indent=1), encoding='utf-8')
    if mk.main(['', str(f), str(out)]): raise ValueError('build failed')

def main(argv):
    count, ids = 10, []
    args = iter(argv[1:])
    for a in args:
        if a == '--count': count = int(next(args))
        else: ids.append(int(a))
    if not ids:
        page = 1
        while len(ids) < count:
            items = api(f'/v1/public/quizzes/list/1,9/3/{page}/true/null/null/null/null')['items']
            if not items: break
            ids += [it['id'] for it in items if not any('PRO' in tg['title'] for tg in it['tags'])]
            page += 1
        ids = ids[:count]
    out, bad = ROOT / 'ielts', 0
    for i in ids:
        try:
            build(convert(api(f'/v1/public/quizzes/{i}')), out)
        except Exception as e:
            bad += 1; print(f'skip {i}: {e}', file=sys.stderr)
    return 1 if bad == len(ids) else 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))
