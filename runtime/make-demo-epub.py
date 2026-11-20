"""Write demo/leaf-demo.epub: a short original English story for trying Leaf's reading tools.

Each chapter targets one feature: idioms and phrasal verbs (incl. inflected forms),
multi-sentence paragraphs (Sentence | Paragraph), and tricky punctuation / inline tags.
Usage: python3 runtime/make-demo-epub.py
"""
from pathlib import Path
import zipfile

chapters = [
 ('Chapter 1 · The Letter', [
  'Nora had never been good at waiting. When the letter finally arrived, she tore it open before she even took off her coat.',
  'Her grandmother wanted her to spend a week by the sea. Nora read the letter twice, then made up her mind on the spot.',
  'She had been feeling a bit under the weather for days, and the city was getting on her nerves. A week away sounded like exactly what she needed.',
  '“Pack light,” her brother said. “And don’t give up on the first day if it rains.” Nora laughed. She never gave up that easily.',
  'Once in a blue moon, a plan comes together without any trouble. This, she would soon find out, was not one of those times.',
 ]),
 ('Chapter 2 · The Village', [
  'The bus broke down halfway up the coast road. The driver looked at the engine, shook his head, and told everyone to sit tight.',
  'Nora took a deep breath. She looked forward to the sea, not to a long afternoon on a dusty road. Still, there was no point in complaining.',
  'An old man across the aisle offered her an apple to break the ice. He had lived in the village all his life, he said, and he knew every story worth telling.',
  'By the time the bus started again, the sun was going down. Nora had heard about the storm of 1962, the lost fishing boat, and the lighthouse keeper who never came back.',
  'At last the village came into view: white houses, a narrow harbour, and a lighthouse standing on its own at the end of the pier.',
 ]),
 ('Chapter 3 · The Lighthouse', [
  'Her grandmother was waiting at the door. “You made it,” she said. “I was starting to worry… but here you are.”',
  'That night Nora could not fall asleep. Through the window she could see the lighthouse. Its light was off, as it had been for years — or so everyone said.',
  'Then, just after midnight, it came on. Nora sat up in bed. She watched the beam turn slowly over the water, once, twice, three times, and then go dark again.',
  'In the morning she brought it up at breakfast. Her grandmother put down her cup and looked at her for a long time. “So you saw it too,” she said quietly.',
  'Nora did not know what to say. She had come here to slow down and get away from it all. Instead, it seemed, the week was only just beginning.',
 ]),
]
# Inline tags inside paragraphs: the word lookup must climb out of <i>/<em> to the paragraph.
chapters[2][1][1] = 'That night Nora could <i>not</i> fall asleep. Through the window she could see the lighthouse. Its light was off, as it had been for years — or so <em>everyone</em> said.'

def page(title, paragraphs):
    body = '\n'.join(f'<p>{p}</p>' for p in paragraphs)
    return f'''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head><title>{title}</title><style>p{{text-indent:1.2em;margin:0 0 .6em}}h1{{font-size:1.3em}}</style></head>
<body><h1>{title}</h1>
{body}
</body></html>'''

def write_epub(out, title, identifier, chapters, stem='ch', extra=None, doc_title=None):
    """Write an EPUB: chapters = [(title, [paragraph html])]; extra = {zip path: text}."""
    files = {f'OEBPS/{stem}{i+1}.xhtml': page(t, ps) for i, (t, ps) in enumerate(chapters)}
    items = '\n'.join(f'<item id="{stem}{i+1}" href="{stem}{i+1}.xhtml" media-type="application/xhtml+xml"/>' for i in range(len(chapters)))
    spine = '\n'.join(f'<itemref idref="{stem}{i+1}"/>' for i in range(len(chapters)))
    nav_points = '\n'.join(f'<navPoint id="n{i+1}" playOrder="{i+1}"><navLabel><text>{t}</text></navLabel><content src="{stem}{i+1}.xhtml"/></navPoint>'
                           for i, (t, _) in enumerate(chapters))
    files['OEBPS/content.opf'] = f'''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>{title}</dc:title><dc:creator>Leaf</dc:creator>
<dc:language>en</dc:language><dc:identifier id="id">{identifier}</dc:identifier>
</metadata>
<manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
{items}
</manifest>
<spine toc="ncx">
{spine}
</spine>
</package>'''
    files['OEBPS/toc.ncx'] = f'''<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<head><meta name="dtb:uid" content="{identifier}"/></head>
<docTitle><text>{doc_title or title}</text></docTitle>
<navMap>
{nav_points}
</navMap>
</ncx>'''
    files['META-INF/container.xml'] = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>'''
    files.update(extra or {})
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, 'w') as z:
        z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip')  # first and stored, per EPUB spec
        for name, text in files.items():
            z.writestr(name, text, compress_type=zipfile.ZIP_DEFLATED)

if __name__ == '__main__':
    out = Path(__file__).resolve().parents[1]/'demo/leaf-demo.epub'
    write_epub(out, 'A Week by the Sea (Leaf demo)', 'leaf-demo-1', chapters, doc_title='A Week by the Sea')
    print(out)
