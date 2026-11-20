# IELTS Reading practice in Leaf — design

Date: 2026-11-20 · Status: draft for approval

## Intent

The user prepares for IELTS and finds Reading tests online (e.g. YouPass: a passage with
questions 1–13 of mixed types). They want to do these tests on their jailbroken Kindle Basic
in Leaf (KOReader fork, E Ink 600×800, ~167 dpi, touch only) instead of on a computer.

The goal is **learning, not exam simulation**: while doing a test, every Leaf reading tool must
work on the passage exactly as in a normal book — tap a word for the compact dictionary with
idiom detection, **Sentence** / **Paragraph** translation, **Use AI**, **Listen**.

Reference mockup (agreed direction): `research/ielts-mockup.html`.

## Goals

- Turn a test copied from the internet into a file the Kindle opens like a book.
- Answer questions on the Kindle with as little typing as possible.
- Get a score, a rough band estimate, and see where in the passage each answer is.
- Keep all existing Leaf reading tools working on the passage, in both modes.

## Non-goals (v1)

- Automatically scraping or parsing arbitrary websites. Conversion from copied text to the
  test format is done once per test on the Mac (by hand with a template, or with AI help).
- Listening / Writing / Speaking.
- Exact official band scores (only a rough estimate).
- Syncing tests or results between devices.

## Anti-goals (failure even if it "works")

- The passage stops behaving like a book page (losing tap-word, Sentence, idioms, highlights).
- Answering requires the on-screen keyboard for normal cases.
- Copyrighted test content ends up in the public GitHub repo.
- Normal books change behaviour (footer, taps) when they are not tests.

## Constraints

- KOReader Lua plugin (`runtime/macos/test-data/plugins/englishpreview.koplugin`), same
  conventions as the rest of Leaf; must run on Kindle (`kindlehf`, firmware 5.18.5) and in the
  Mac preview. No new runtime dependencies.
- E Ink: discrete screens, no animation, ≥ 44 px targets, grayscale, minimal refreshes.
- Existing tap hook (`Preview:installTapLookup` in `main.lua`) owns word taps; the test feature
  must cooperate with it, not replace it.
- Tests are personal study material: generated test files live in `demo/` or a git-ignored
  folder, never committed (add `ielts/` to `.gitignore`).

## Approaches

| | Approach | Trade-off |
|---|---|---|
| **A (chosen)** | **Passage as an EPUB; questions + key ride inside the same EPUB as JSON; a Leaf panel shows the questions** | Passage gets every reading tool for free (it is a book page). New code only for the questions panel, timer and results. |
| B | Leaf draws passage and questions in a custom screen | Full layout control, but the passage stops being a book page, so word taps, Sentence/Paragraph, idioms and highlights must be rebuilt. Much more work for the same result. |
| C | Everything inside the EPUB (questions as a chapter, answer by highlighting) | Almost no code, but no scoring, no timer, clumsy answering. |

The user picked **A**.

## Design (decided)

### 1. Test file

One EPUB per test, built on the Mac by a new script `runtime/make-ielts-test.py`:

- Input: a plain-text test file in a small fixed format (template in the script's docstring):
  title, time limit, passage paragraphs, then questions with the answer key.
- One file holds **either one Part or a full test** (user's answer): 1–3 passages.
- Output: `<title>.epub` with
  - `OEBPS/passage1.xhtml` … `passage3.xhtml`: one chapter per passage (same EPUB skeleton as
    `runtime/make-demo-epub.py`; reuse its helpers rather than duplicating them).
  - `META-INF/leaf-ielts.json`: questions and answer key (schema below).
- The script validates the input (every question has an answer; every `evidence` string is
  found verbatim in the passage) and fails loudly otherwise.

`leaf-ielts.json`:

```json
{
  "version": 1,
  "title": "Bees on guard",
  "minutes": 20,
  "passages": [{"n": 1, "title": "Bees on guard", "from": 1, "to": 13}],
  "questions": [
    {"n": 1, "type": "choice", "text": "…statement…",
     "options": ["TRUE", "FALSE", "NOT GIVEN"], "answer": "TRUE",
     "evidence": "exact sentence fragment from the passage"},
    {"n": 7, "type": "gap", "before": "counts of elephant", "after": "",
     "words": 1, "answer": "footprints", "accept": ["footprint"],
     "evidence": "counting the footprints that the animals had left"}
  ]
}
```

- `choice` covers TRUE/FALSE/NOT GIVEN, YES/NO/NOT GIVEN, multiple choice and matching
  (options are the labels to tap; their meaning lives in the group's `list`).
- `multi` covers "Choose TWO/THREE letters": one entry with `"picks": 2`,
  `"answers": ["B","D"]`, numbered as its range (`"n": [20, 21]`); order-free scoring, one
  point per correct letter. *(Builder-check call.)*
- `gap` covers sentence/table/note/summary completion; `words` is the word limit
  ("ONE WORD ONLY" = 1); `accept` lists other accepted spellings. Table completion is one gap
  per row with `before`/`after` (as in the YouPass screenshot); no table drawing on E Ink.
- `groups` (top level) carry content shared by several questions *(builder-check call)*:
  ```json
  "groups": [{"from": 7, "to": 13, "title": "Questions 7–13",
              "instructions": "Complete the table. Choose ONE WORD ONLY from the passage.",
              "list": ["i  The cost of fences", "ii  Bees and crops"],
              "text": "Beehive fences protect {7} near Tsavo, but drought reduced {8}."}]
  ```
  `list` shows above the group (matching headings/features); `text` with `{n}` markers renders
  summaries with the blanks inline (those gaps then omit `before`/`after`).
- `passages` maps question numbers to passages (full test: 1–13, 14–26, 27–40, `minutes` 60).
  Each question's `evidence` is searched only inside its own passage.

### 2. Detecting a test

On `onReaderReady`, Leaf calls `document:getDocumentFileContent('META-INF/leaf-ielts.json')`
(EPUB only). If it parses and `version == 1`, the book is a test; otherwise nothing changes.

### 3. Starting

First open of a test shows a small Leaf popup: **Practice** (timer) or **Study** (no timer).
Reading tools are on in both (user's choice). The choice is saved per book.

### 4. Reading and the questions panel

- The passage is the normal reader page; nothing about reading changes.
- The footer gets one extra item while a test is open: `Q 3/13 · 14:20` in Practice,
  `Q 3/13` in Study (`ReaderFooter:addAdditionalFooterContent`).
- **Opening the questions** (my call, to be confirmed in testing): tapping the footer area
  opens the Questions panel when the book is a test (non-test books keep normal footer
  behaviour). The same panel is also reachable from **English tools → Questions**.
- Questions panel: full-screen Leaf widget, scrollable, styled like the mockup:
  group headers, numbered questions, `choice` as a row of equal tap buttons (selected = black
  fill), `gap` as an inline blank. Top bar: **← Passage**, progress dots, timer. Bottom:
  **Finish**.
- Full tests: the panel opens on the questions for the passage you are reading (chapter of
  the current page), with a **Passage 1 · 2 · 3** switch; **← Passage** returns to the page you
  were on. One timer for the whole test; **Finish** scores all questions.
- Filling a `gap`: tap the blank → the panel closes, a one-line banner
  "Q7 · *footprints* · Done · Clear · Type instead" shows at the top of the page. Each word tap
  appends that word to the answer (instead of opening the dictionary); **Done** returns to the
  panel at that question. One-word gaps return automatically after the first tap. Hold-drag
  keeps its normal translate behaviour. **Type instead** opens a one-line input. Answers longer
  than `words` are allowed but flagged. *(Builder-check call.)*

### 5. Timer (Practice)

Counts down from `minutes`; survives sleep and closing the book (stores elapsed seconds). At
zero, a message says time is up; answering is still allowed (learning, not locking).

### 6. Results

**Finish** shows: score `9/13` or `31/40` (with one line per passage for full tests), a band
estimate (standard Academic raw-score table; a single Part is scaled to 40 first and labelled
rough), time used, and one row per question: ✓/✗, your answer, the correct
answer. **Show in passage** finds the `evidence` text (`findText`), jumps there and highlights
it temporarily. **Try again** clears answers and the timer; **Done** returns to the passage.

Matching is case-insensitive, trims spaces and punctuation, and accepts `accept` variants.

### 7. Persistence

Answers, mode, elapsed time and finished state live in the book's own settings
(`self.ui.doc_settings`), so they survive restarts and stay with the file.

### 8. Getting tests onto the Kindle

The user copies the test text into a file on the Mac (or into chat for conversion), runs
`make-ielts-test.py`, and copies the EPUB into `documents/IELTS/` on the Kindle (manual copy,
or a small `--install` flag reusing the safe-copy pattern from `update-connected.py`).

### 9. Checks

A new `runtime/macos/checks/english-ielts.lua` (registered in `run-learning-checks.py`):
JSON parsing/validation, answer matching (case, punctuation, `accept`), band estimate, word
pick filling a gap instead of opening the dictionary, persistence round-trip, non-test books
unchanged. `make-ielts-test.py` validates its own input.

## Left to the builder

- Verify early, on the Kindle, that `getDocumentFileContent('META-INF/leaf-ielts.json')`
  returns the file; if not, move the JSON to `OEBPS/` (not listed in the spine).
- Generated tests go to a git-ignored `ielts/` folder in the repo.
- The timer counts only while the book is open and the Kindle is awake.

- Exact widget composition for the panel (reuse `english_popup.lua` styles and KOReader
  `ButtonTable`/`ScrollableContainer` as fits).
- The precise raw-score → band table values (use the commonly published Academic table).
- Banner widget choice for word-pick mode, as long as it does not cover the passage text being
  read and is dismissable.
- Whether footer tap or another gesture is the most reliable way to open the panel on the
  device; keep the English tools entry regardless.
