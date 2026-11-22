"""Import public IELTS Reading/Listening tests from youpass.vn into Leaf test EPUBs (personal use).

Usage: python3 runtime/youpass-import.py [--listening] [--count N] [quiz_id ...]
No ids: takes the newest N (default 10) free tests from the reading (or listening) list. Skips PRO
tests and tests with question types Leaf can't show (diagram labels). Writes ielts/<slug>.epub
(listening: ielts/listening/<slug>.epub + .pcm; macOS afconvert needed), gitignored, via
make-ielts-test.py; the intermediate JSON goes to ielts/json/.
"""
from pathlib import Path
import html, importlib.util, json, re, subprocess, sys, tempfile, urllib.request, wave

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location('mk', Path(__file__).with_name('make-ielts-test.py'))
mk = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(mk)

def fetch_bytes(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'}), timeout=60).read()

def fetch(url): return fetch_bytes(url).decode()

def api(path): return json.loads(fetch('https://api.youpass.vn' + path))['data']

def text(h):
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', h or ''))).strip()

def vocabs(skill, quiz_id, part_ids):
    """Passage/transcript text is only in the practice page payload: part.vocabs = paragraphs > sentences."""
    page = fetch(f'https://youpass.vn/practice/{skill}/{quiz_id}')
    rsc = ''.join(json.loads('"' + m + '"') for m in re.findall(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)', page))
    out = {}
    for pid in part_ids:
        i = rsc.find(f'"id":{pid},"quiz_id"')
        if i < 0: raise ValueError(f'part {pid} text not found')
        j = rsc.find('"vocabs":[', i) + len('"vocabs":')
        tree, _ = json.JSONDecoder().raw_decode(rsc[j:])
        out[pid] = [p for p in tree if p['children']]
    return out

def paragraphs(quiz_id, part_ids):
    return {pid: [[s['value'].strip() for s in p['children']] for p in tree]
            for pid, tree in vocabs('reading', quiz_id, part_ids).items()}

def words(desc):
    d = desc.upper()
    if 'ONE WORD AND/OR A NUMBER' in d: return 2
    for w, n in (('ONE WORD', 1), ('TWO WORDS', 2), ('THREE WORDS', 3)):
        if w in d: return n
    return 3

def add_questions(t, p, paras, extra=lambda q, item: None):
    """Append part p's questions/groups to t; paras = sentence lists for evidence. Returns (first, last) number."""
    lo = hi = None
    for s in p['question_sets']:
        desc, opts = text(s['description']), s['options'] or []
        kind = s['questions'][0]['question_type'] if s['questions'] else ''
        if kind == 'MAP_DIAGRAM_LABEL': raise ValueError('map/diagram labelling')
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
            extra(q, item)
            t['questions'].append(item)
            lo = min(lo or ns[0], ns[0]); hi = max(hi or ns[-1], ns[-1])
        nums = [x for q in s['questions'] for x in ([q['order']] if kind != 'MULTIPLE_CHOICE_MANY' else range(q['order'], q['order'] + int(s['question_count'])))]
        g['from'], g['to'] = min(nums), max(nums)
        t['groups'].append(g)
    return lo, hi

def title_of(d): return re.sub(r'^\[[^\]]*\]\s*', '', d['title']).strip()

def slugify(title): return re.sub(r'[^a-z0-9]+', '-', title.lower()).strip('-')

def convert(d):
    parts = d['parts'] or []
    sents = paragraphs(d['id'], [p['id'] for p in parts])
    t = {'version': 1, 'title': title_of(d), 'minutes': d['time'] or 20,
         'passages': [], 'groups': [], 'questions': []}
    for pn, p in enumerate(parts, 1):
        paras = sents[p['id']]
        lo, hi = add_questions(t, p, paras)
        t['passages'].append({'n': pn, 'title': p['title'], 'from': lo, 'to': hi, 'paragraphs': [' '.join(x) for x in paras]})
    return t

def stamp(sec): return f'{int(sec) // 60}:{int(sec) % 60:02d}'

def convert_listening(d, transcripts, durations):
    """transcripts[part_id] = vocabs tree; durations[part_id] = seconds; parts' audio is joined in order."""
    title = title_of(d)
    t = {'version': 1, 'title': title, 'skill': 'listening', 'minutes': d['time'] or 10,
         'audio': {'file': slugify(title) + '.pcm', 'rate': 16000, 'seconds': sum(durations[p['id']] for p in d['parts'])},
         'passages': [], 'groups': [], 'questions': []}
    off = 0.0
    for pn, p in enumerate(d['parts'], 1):
        tree = transcripts[p['id']]
        paras = [[s['value'].strip() for s in x['children']] for x in tree]
        def extra(q, item, off=off):
            r = (q.get('locate_info') or {}).get('time_ranges')
            if r: item['at'] = [r['from'] + off, r['to'] + off]
            if item['type'] == 'gap':
                got = q.get('correct_answers') or [item['answer']]
                item['answer'] = got[0].strip()
                item['accept'] = list({x.strip().lower(): x.strip() for x in got[1:]
                                       if x.strip().lower() != item['answer'].lower()}.values())
        lo, hi = add_questions(t, p, paras, extra)
        t['passages'].append({'n': pn, 'title': p['title'] or f'Section {pn}', 'from': lo, 'to': hi,
                              'paragraphs': [f"[{stamp(x['children'][0]['meta']['from'] + off)}] " + ' '.join(paras[i])
                                             for i, x in enumerate(tree)]})
        off += durations[p['id']]
    return t

def audio_pcm(file_id):
    """Download a part's audio and convert it to 16 kHz mono s16le; returns (seconds, raw frames)."""
    with tempfile.TemporaryDirectory() as tmp:
        src, wav = Path(tmp, 'a.m4a'), Path(tmp, 'a.wav')
        src.write_bytes(fetch_bytes(f'https://cms.youpass.vn/assets/{file_id}'))
        subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', str(src), str(wav)], check=True)
        with wave.open(str(wav)) as w:
            frames = w.readframes(w.getnframes()); return len(frames) / 2 / w.getframerate(), frames

def build(t, out):
    (out / 'json').mkdir(parents=True, exist_ok=True)
    f = out / 'json' / f'{slugify(t["title"])}.json'
    f.write_text(json.dumps(t, ensure_ascii=False, indent=1), encoding='utf-8')
    try:
        mk.validate(json.loads(f.read_text()))
    except ValueError as e:  # evidence that doesn't match exactly: keep the test, drop the evidence
        if 'evidence' not in str(e): raise
        for q in t['questions']: q.pop('evidence', None)
        f.write_text(json.dumps(t, ensure_ascii=False, indent=1), encoding='utf-8')
    if mk.main(['', str(f), str(out)]): raise ValueError('build failed')

def listening(d, out):
    if 'MAP_DIAGRAM_LABEL' in json.dumps(d): raise ValueError('map/diagram labelling')  # before the downloads
    parts = d['parts']
    trees = vocabs('listening', d['id'], [p['id'] for p in parts])
    audio = {p['id']: audio_pcm(p['file_id']) for p in parts}
    t = convert_listening(d, trees, {k: v[0] for k, v in audio.items()})
    build(t, out)
    (out / t['audio']['file']).write_bytes(b''.join(audio[p['id']][1] for p in parts))

def main(argv):
    count, ids, lst = 10, [], False
    args = iter(argv[1:])
    for a in args:
        if a == '--count': count = int(next(args))
        elif a == '--listening': lst = True
        else: ids.append(int(a))
    if not ids:
        page = 1
        while len(ids) < count:
            items = api(f'/v1/public/quizzes/list/{'2,10' if lst else '1,9'}/3/{page}/true/null/null/null/null')['items']
            if not items: break
            ids += [it['id'] for it in items if not any('PRO' in tg['title'] for tg in it['tags'])]
            page += 1
        ids = ids[:count]
    out, bad = ROOT / 'ielts' / ('listening' if lst else ''), 0
    for i in ids:
        try:
            d = api(f'/v1/public/quizzes/{i}')
            listening(d, out) if lst else build(convert(d), out)
        except Exception as e:
            bad += 1; print(f'skip {i}: {e}', file=sys.stderr)
    return 1 if bad == len(ids) else 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))
