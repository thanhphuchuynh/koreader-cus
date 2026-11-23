# Adding a test

A Leaf test is an EPUB with the answer key inside it (`META-INF/leaf-ielts.json`). You write one JSON
file, build it with `runtime/make-ielts-test.py`, and copy the EPUB (plus its audio, for listening)
to the Kindle. The Tests tab finds it by itself.

## 1. Pick the kind of test

| Kind | `exam` | `skill` | `part` | Needs | Kindle folder |
|---|---|---|---|---|---|
| IELTS Reading | — | — | — | passages with paragraphs | `documents/IELTS` (or `IELTS/Reading`) |
| IELTS Listening | — | `"listening"` | — | audio, passages = transcript | `documents/IELTS/Listening` |
| TOEIC Part 1 Photographs | `"toeic"` | `"listening"` | `1` | audio, a photo per question | `documents/TOEIC/Part 1` |
| TOEIC Part 2 Question–response | `"toeic"` | `"listening"` | `2` | audio, options `A`/`B`/`C`, no text | `documents/TOEIC/Part 2` |
| TOEIC Part 3 Conversations | `"toeic"` | `"listening"` | `3` | audio | `documents/TOEIC/Part 3` |
| TOEIC Part 4 Talks | `"toeic"` | `"listening"` | `4` | audio | `documents/TOEIC/Part 4` |
| TOEIC Part 5 Incomplete sentences | `"toeic"` | — | `5` | nothing extra | `documents/TOEIC/Part 5` |
| TOEIC Part 6 Text completion | `"toeic"` | — | `6` | passages (the texts) | `documents/TOEIC/Part 6` |
| TOEIC Part 7 Reading passages | `"toeic"` | — | `7` | passages (the texts) | `documents/TOEIC/Part 7` |

The folder only keeps things tidy: the Tests tab sorts a test by its `exam`, `skill` and `part`.

## 2. Write the JSON

Start from an example: `runtime/ielts-sample.json` (IELTS Reading) or `runtime/toeic-sample-part5.json`
(TOEIC Part 5).

Top level:
- `version`: always `1`.
- `title`: shown in the Tests tab. It also names the file (`"Part 5 · Set 2"` → `part-5-set-2.epub`),
  so give every test a different title.
- `minutes`: the time limit for Practice/Exam mode.
- `passages`: `[{n, title, from, to, paragraphs: [str]}]`. `n` counts 1, 2, 3…; `from`/`to` are the
  question numbers the passage covers. TOEIC sets may leave `passages` out; the builder adds a cover page.
- `groups` (optional): `[{from, to, title, instructions, text, list}]`, a header shown before
  questions `from`–`to`. Write `{7}` inside `text` to put the gap for question 7 in that text.
- `questions`: see below.

Question types:
- **choice**: `{"n": 1, "type": "choice", "text": "...", "options": ["(A) by", "(B) until"], "answer": "(A) by"}`.
  `answer` must be exactly one of the `options`. Short options (letters, TRUE/FALSE) share one row;
  worded options get a row each.
- **multi** (choose two or more): `{"n": [3, 4], "type": "multi", "options": ["A","B","C","D","E"], "answers": ["A","C"]}`.
  Optional `picks` caps how many can be chosen.
- **gap**: `{"n": 5, "type": "gap", "words": 1, "answer": "amber", "accept": ["amber lights"]}`.
  `words` is the word limit. Optional `before`/`after` text goes around the blank. In reading tests the
  learner taps a word in the passage to fill a gap; in listening tests they type it.

Optional on any question:
- `evidence`: the words in the passage that prove the answer. It must appear in one paragraph of that
  question's passage; the builder checks it, and Results shows "Show in passage".
- `at` (listening): `[from, to]` seconds in the audio where the answer is heard; enables "▶ Hear it"
  and the replay button in Study mode.
- `image` (TOEIC Part 1): a `.jpg`/`.png` file name. Put the photo next to the JSON; the builder stores it
  in the book, and the question shows it above the options.

## 3. Listening audio

The audio is a raw 16-bit mono PCM file next to the EPUB on the Kindle. Convert an MP3 on a Mac:

```sh
afconvert -f WAVE -d LEI16@16000 -c 1 audio.mp3 audio.wav
python3 -c "import wave,sys;w=wave.open(sys.argv[1]);open(sys.argv[2],'wb').write(w.readframes(w.getnframes()));print(round(w.getnframes()/w.getframerate(),2))" audio.wav audio.pcm
```

The second command prints the length in seconds. Put it in the JSON:
`"audio": {"file": "audio.pcm", "rate": 16000, "seconds": 151.4}`. `file` is a plain file name,
no folders.

## 4. Build and check

```sh
python3 runtime/make-ielts-test.py my-test.json toeic/part-5
```

The builder stops and names the problem if something is wrong: an answer not among the options, a
question outside every passage's range, evidence that is not in the passage, a missing photo, a TOEIC
part that does not match its skill. The EPUB goes in the folder you give it (default `ielts/`).

To see it before copying, start the Mac KOReader (`runtime/macos/Launch KOReader.command`) and open the EPUB from its file browser.

## 5. Copy to the Kindle

**Over Wi-Fi (Leaf Send):** build the Mac app once with `mac/LeafSend/make-app.sh` and open
`mac/LeafSend/build/LeafSend.app`. First time only: plug the Kindle in by USB, tap **Set up key (USB)**,
eject. Then on the Kindle start KOReader → Network → SSH server (or turn on its start-with-KOReader option),
and drop EPUBs on the Leaf Send window: it finds the Kindle on your Wi-Fi and puts each test in its folder
(a listening test's `.pcm` must sit next to its EPUB). Other books go to `documents/From Mac`.

**By USB:** copy the EPUB, and for listening its `.pcm`, into the Kindle folder from the table. Eject the
Kindle before unplugging it.

Open the Tests tab: the test appears in its folder.

## Rules

- **Never commit someone else's test.** Questions, passages, audio and photos from books or websites
  (Cambridge, ETS, YouPass, Study4…) stay on your computer and Kindle. Build them into `ielts/` or
  `toeic/`, which git ignores. Only original content you wrote, like the two samples in `runtime/`,
  goes in the repo.
- **Importers write JSON in this format** and call `make-ielts-test.py`; see `runtime/youpass-import.py`.
  A new question type or field needs the builder (`validate`), the parser (`english_ielts.lua` `parse`),
  the questions panel and their checks changed together.
- **Run the checks** after changing the builder or the plugin: `python3 runtime/macos/checks/run-learning-checks.py`.
