"""Build Leaf's offline idiom/phrase index from the installed en-en StarDict dictionary.

Output: englishpreview.koplugin/english_phrases.tsv, lines "form<TAB>headword" (headword empty
when equal to form), sorted by
byte order so the plugin can binary-search it with file seeks (no memory, no startup cost).
Forms are multi-word headwords plus their inflections from the .syn file
(gave up -> give up, kicked the bucket -> kick the bucket).

Usage: python3 runtime/build-phrases.py [dict_dir] [plugin_dir]
"""
from pathlib import Path
import re, sys

root = Path(__file__).resolve().parent
dict_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else root/'macos/test-data/data/dict/en-en'
plugin = Path(sys.argv[2]) if len(sys.argv) > 2 else root/'macos/test-data/plugins/englishpreview.koplugin'

# A phrase made only of these is grammar ("of the", "in a"), not an idiom.
FUNCTION = set('''a an the of in on at to for from by with as and or but if so than then that this these those
it its it's i me my you your he him his she her we us our they them their is are was were be been being am
do does did not no nor there here what which who whom whose when where why how all any some each one'''.split())
PHRASE = re.compile(r"[a-z]+(?:['-][a-z]+)*(?: [a-z]+(?:['-][a-z]+)*){1,4}")  # 2-5 lowercase words

def entries(path, tail):
    data = path.read_bytes(); i = 0
    while i < len(data):
        j = data.index(b'\0', i)
        yield data[i:j].decode('utf-8', 'replace'), data[j+1:j+1+tail]
        i = j + 1 + tail

def keep(phrase):
    return PHRASE.fullmatch(phrase) and not all(w in FUNCTION for w in phrase.split())

headwords = [w for w, _ in entries(dict_dir/'en-en.idx', 8)]
forms = {w: w for w in headwords if keep(w)}   # lowercase headwords only: skips names like "New York"
for form, ref in entries(dict_dir/'en-en.syn', 4):
    head = headwords[int.from_bytes(ref, 'big')]
    low = form.lower()
    if head in forms and keep(low):
        forms.setdefault(low, head)

lines = sorted(f'{f}\t{h if h != f else ""}\n'.encode() for f, h in forms.items())  # empty = same as form
out = plugin/'english_phrases.tsv'
out.write_bytes(b''.join(lines))
print(f'{len(lines)} phrase forms ({len(set(forms.values()))} headwords), {out.stat().st_size/1e6:.1f} MB -> {out}')
