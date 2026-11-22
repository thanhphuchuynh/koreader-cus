"""Rearrange the Kindle library into folders, keeping reading progress.

Dry run by default; `--apply` performs it. Every removed file and every edited settings file is
backed up (and verified) under runtime/kindle/backups/<time>-library first.

Progress lives in three places, all handled:
- `<book>.sdr` next to the book (original KOReader "doc" mode + Kindle's own reader data);
  FAT is case-insensitive, so two formats of one title can share one .sdr.
- Leaf: koreadercus/profile/docsettings/mnt/us/<path>.sdr ("dir" mode, keyed by path).
- Paths in history.lua / settings.reader.lua / settings/collection.lua of both readers.
"""
from pathlib import Path
from datetime import datetime
import hashlib, json, os, shutil, sys, unicodedata

K = Path('/Volumes/Kindle')
D = 'documents'
EXT = f'{D}/External'
MOVES = {  # source (relative to the Kindle root) -> folder in documents/
    'Essential Grammar in Use 2nd Edition by R. Murphy - Book.pdf': 'English',
    f'{D}/Educated - Tara Westover [eBook].epub': 'English',
    f'{D}/leaf-demo.epub': 'English',
    f'{EXT}/[KorPiracy - KorPiracy] Harry Potter and the Philosopher&_039_s Stone{{J.K. Rowling}}{{111196988}} libgen.li.epub': 'English',
    f'{EXT}/Dune.epub': 'English',
    f'{EXT}/Dune Messiah - Frank Herbert.mobi': 'English',
    f'{EXT}/Children of Dune - Frank Herbert.mobi': 'English',
    f'{EXT}/Atomic Habits by James Clear (James Clear) (books-here.com).pdf': 'English',
    f'{EXT}/The 7 Habits of Highly Effective People PDF.pdf': 'English',
    f'{EXT}/Kubernetes-Patterns-ER-e-book-Red-Hat-Developer.pdf': 'Tech & Business',
    f'{EXT}/Gitops-cookbook-ebook-Red-Hat-Developer.pdf': 'Tech & Business',
    f'{EXT}/xx735.Eric.Evans.Domaindriven.Design.Tackling.Complexity.in.the.Heart.of.Software.pdf': 'Tech & Business',
    f'{EXT}/Martin Kleppmann-Designing Data-Intensive Applications_ The Big Ideas Behind Reliable, Scalable, and Maintainable Systems-O’Reilly Media (2017).epub': 'Tech & Business',
    f'{EXT}/Hacking- The Art of Exploitation (2nd ed. 2008) - Erickson.pdf': 'Tech & Business',
    f'{EXT}/Traction-1-3.pdf': 'Tech & Business',
    f'{D}/Lao Tu - Dao Duc Kinh - Nguyen Hien Le.epub': 'Tiếng Việt',
    f'{EXT}/Bo Gia - Mario Puzo (11).epub': 'Tiếng Việt',
    f'{EXT}/Kafka Ben Bo Bien - Haruki Murakami.azw3': 'Tiếng Việt',
    f'{EXT}/Ong tram tuoi boc hoi qua cua so - Jonas Jonasson (13).epub': 'Tiếng Việt',
    f'{EXT}/SachMoi.net-Trang-Trinh-sam-va-ky.epub': 'Tiếng Việt',
    f'{EXT}/Ngo Sa Thach - Luat Tam Thuc_compressed.pdf': 'Tiếng Việt',
    f'{D}/thietkenguoidung.azw3': 'Tiếng Việt',
    f'{D}/KindleShare - The Ke nguoi dung lam trung tam.azw3': 'Tiếng Việt',
    f'{D}/co-chan-nhan_bilingual.epub': 'Truyện',
    f'{D}/kiem-lai_bilingual.epub': 'Truyện',
    f'{EXT}/Co Chan Nhan - Co Chan Nhan (17).epub': 'Truyện',
    f'{EXT}/Kiếm Lai - Phong Hỏa Hí Chư Hầu.epub': 'Truyện',
    f'{EXT}/Cau Ma - Nhi Can (15).epub': 'Truyện',
    f'{EXT}/cauma_bilingual.epub': 'Truyện',
    f'{EXT}/Tiên Nghịch - Nhĩ Căn.azw3': 'Truyện',
    f'{EXT}/Nhiều Năm Rồi Ta Không Dùng Kiếm - Anan.azw3': 'Truyện',
    f'{EXT}/Dung Den Buc Ta, Ta Chi Muon Nam Ngua Tu - Tam Luong Me Tuu (12).epub': 'Truyện',
}
REMOVE = [  # extra copies: kept copy noted; backed up to the Mac, then removed
    f'{EXT}/Harry Potter and the Philosopher\'s Stone - J.K. Rowling (16).epub',  # KorPiracy copy has progress
    f'{EXT}/Dune - Frank Herbert.mobi',          # Dune.epub has progress
    f'{D}/Bo Gia - Mario Puzo.azw3',             # (11).epub kept (EPUB)
    f'{EXT}/Kafka ben bo bien - Haruki Murakami.epub',  # azw3 has Kindle reading data
    f'{EXT}/Kafka ben bo bien - Haruki Murakami.prc',   # 0-byte, broken
    f'{EXT}/SachMoi.net-Trang-Trinh-sam-va-ky.azw3',    # epub has 25% progress
    f'{EXT}/Kiếm Lai - Phong Hỏa Hí Chư Hầu.azw3',      # epub kept (in history)
    f'{EXT}/Kiem Lai - Phong Hoa Hi Chu Hau (14).epub',
    f'{EXT}/Cầu Ma - Nhĩ Căn.azw3',             # (15).epub kept (EPUB)
    f'{EXT}/Cầu Ma - Nhĩ Căn_bilingual.azw3',    # cauma_bilingual.epub has 24% progress
]
FOLDERS = ['English', 'Tech & Business', 'Tiếng Việt', 'Truyện', 'IELTS']
PATH_FILES = ['koreadercus/profile/history.lua', 'koreader/history.lua',
              'koreadercus/profile/settings.reader.lua', 'koreader/settings.reader.lua',
              'koreadercus/profile/settings/collection.lua', 'koreader/settings/collection.lua']
LEAF_DOCSETTINGS = K / 'koreadercus/profile/docsettings/mnt/us'
APPLEDOUBLE = b'\x00\x05\x16\x07'

def sha(p):
    with open(p, 'rb') as f: return hashlib.file_digest(f, 'sha256').hexdigest()

def sdr_of(rel):
    """The .sdr folder beside a book, matched case-insensitively (FAT), or None."""
    p = K / rel
    key = lambda n: unicodedata.normalize('NFC', n).casefold()  # macOS may report NFD names
    want = key(p.stem + '.sdr')
    for e in p.parent.iterdir():
        if e.is_dir() and key(e.name) == want: return e
    return None

def real(rel):
    """rel with each part spelled exactly as stored (FAT may hold NFD; rename needs the exact form)."""
    out = K
    for part in Path(rel).parts:
        hit = [e.name for e in out.iterdir()] if out.is_dir() else []
        match = [n for n in hit if unicodedata.normalize('NFC', n) == unicodedata.normalize('NFC', part)]
        out = out / (match[0] if match else part)
    return str(out.relative_to(K))

def kindle_path(rel): return '/mnt/us/' + rel

def main(apply):
    assert K.is_mount(), 'Kindle is not mounted'
    done = lambda rel, folder: not (K / rel).exists() and (K / D / folder / Path(rel).name).exists()
    for rel, folder in MOVES.items(): assert (K / rel).is_file() or done(rel, folder), f'missing: {rel}'
    for rel in REMOVE: assert (K / rel).is_file(), f'missing: {rel}'
    pending = {real(r): f for r, f in MOVES.items() if not done(r, f)}
    kept_sdrs = {sdr_of(r) for r in pending} - {None}
    plan = []
    for rel, folder in pending.items():
        new = f'{D}/{folder}/{Path(rel).name}'
        plan.append(('move', rel, new))
        s = sdr_of(rel)
        if s: plan.append(('move-sdr', str(s.relative_to(K)), f'{D}/{folder}/{s.name}'))
        leaf = LEAF_DOCSETTINGS / (str(Path(rel).with_suffix('')) + '.sdr')
        if leaf.is_dir(): plan.append(('move-leaf', str(leaf.relative_to(K)),
                                       str((LEAF_DOCSETTINGS / (str(Path(new).with_suffix('')) + '.sdr')).relative_to(K))))
    for rel in map(real, REMOVE):
        plan.append(('remove', rel, None))
        s = sdr_of(rel)
        if s and s not in kept_sdrs: plan.append(('remove-sdr', str(s.relative_to(K)), None))
    for kind, a, b in plan: print(f'{kind:10} {a}' + (f'\n{"":10} -> {b}' if b else ''))
    freed = sum((K / r).stat().st_size for r in REMOVE)
    done_moves = [(f'{r}', f'{D}/{f}/{Path(r).name}') for r, f in MOVES.items() if done(r, f)]
    print(f'\n{len(pending)} books to move ({len(MOVES)-len(pending)} already moved), {len(REMOVE)} extra copies removed ({freed/1e6:.0f} MB freed)')
    if not apply: print('Dry run. Re-run with --apply.'); return

    backup = Path(__file__).resolve().parent / 'backups' / (datetime.now().strftime('%Y%m%d-%H%M%S') + '-library')
    backup.mkdir(parents=True, mode=0o700)
    def keep_copy(rel):
        src, dst = K / rel, backup / 'removed' / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if src.is_dir(): shutil.copytree(src, dst)
        else:
            shutil.copyfile(src, dst); assert sha(dst) == sha(src), f'backup differs: {rel}'
    # 1. Back up everything that will be removed or edited.
    for kind, a, _ in plan:
        if kind.startswith('remove'): keep_copy(a)
    edits = [p for p in PATH_FILES if (K / p).is_file()]
    for p in edits:
        dst = backup / 'settings' / p; dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(K / p, dst); assert sha(dst) == sha(K / p)
    (backup / 'plan.json').write_text(json.dumps(plan, ensure_ascii=False, indent=1))
    # 2. Move (same volume: renames) and remove.
    for f in FOLDERS: (K / D / f).mkdir(exist_ok=True)
    sizes = {a: (K / a).stat().st_size for k, a, _ in plan if k == 'move'}
    for kind, a, b in plan:
        if kind.startswith('move'):
            (K / b).parent.mkdir(parents=True, exist_ok=True)
            assert not (K / b).exists(), f'target exists: {b}'
            os.rename(K / a, K / b)
        elif kind == 'remove': (K / a).unlink()
        elif kind == 'remove-sdr': shutil.rmtree(K / a)
    # 3. Point saved paths (history, last file, collections) at the new locations.
    renames = [(kindle_path(a), kindle_path(b)) for k, a, b in plan if k == 'move'] + \
              [(kindle_path(a), kindle_path(b)) for a, b in done_moves]
    for p in edits:
        text = (K / p).read_text(encoding='utf-8')
        new = text
        for old, nw in renames:
            for form in ('NFC', 'NFD'):  # the reader wrote whichever form the filename had
                new = new.replace(f'"{unicodedata.normalize(form, old)}"', f'"{unicodedata.normalize(form, nw)}"')
        if new != text:
            tmp = (K / p).with_name((K / p).name + '.rearrange')
            tmp.write_text(new, encoding='utf-8'); os.replace(tmp, K / p)
    # 4. Verify; drop macOS metadata files created in the new folders.
    for k, a, b in plan:
        if k == 'move': assert (K / b).stat().st_size == sizes[a] and not (K / a).exists(), f'move failed: {a}'
        if k.startswith('move-'): assert (K / b).is_dir() and not (K / a).exists(), f'move failed: {a}'
        if k.startswith('remove'): assert not (K / a).exists() and (backup / 'removed' / a).exists()
    for f in FOLDERS:
        for m in (K / D / f).glob('._*'):
            if m.is_file() and m.read_bytes()[:4] == APPLEDOUBLE: m.unlink()
    os.sync()
    print(f'Done. Backup: {backup}')

if __name__ == '__main__':
    main('--apply' in sys.argv)
