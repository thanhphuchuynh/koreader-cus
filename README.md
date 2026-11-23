# koreader-cus

**Leaf** — a KOReader-based reader for learning English on a jailbroken Kindle Basic (2023, firmware 5.18.x, `kindlehf`).

Tap a word for a compact dictionary popup with idiom detection, tap **Sentence** to translate the
sentence (or **Paragraph**) with Google, **Use AI** for explanations, **Listen** for offline speech
(tiny-voca). Everything runs as a KOReader plugin: `runtime/macos/test-data/plugins/englishpreview.koplugin`.

## Layout
- `runtime/macos/test-data/plugins/englishpreview.koplugin` — the Leaf plugin (Lua)
- `runtime/macos/test-data/patches` — KOReader user patches (dictionary results, branding, hide crash files)
- `runtime/macos/checks` — checks: `python3 runtime/macos/checks/run-learning-checks.py`
- `runtime/kindle` — build / install / update scripts for the Kindle (`build-custom.py`, `update-connected.py`)
- `runtime/build-phrases.py` — builds the offline idiom index from the en-en StarDict dictionary
- `runtime/make-demo-epub.py` — writes `demo/leaf-demo.epub`, an original story for trying the features
- `research/` — investigation report and mockups
- `mac/LeafSend` — Mac app: drop books/tests, sends them to the Kindle over Wi-Fi (KOReader SSH); `make-app.sh` builds it
- `docs/adding-tests.md` — how to add an IELTS or TOEIC test (JSON format, audio, build, copy to the Kindle)

## Not in the repo (rebuild or download)
- KOReader runtime (`runtime/macos/KOReader.app`, Kindle staging) — official KOReader releases
- `englishpreview.koplugin/voca/` binary + model — build https://github.com/sultson/voca
  (`cargo build --release --target armv7-unknown-linux-musleabihf`) and its `voca-data.tar.gz` release
- `englishpreview.koplugin/english_phrases.tsv` — `python3 runtime/build-phrases.py`
- en-en dictionary (koreader-dicts), Kindle backups, API keys
