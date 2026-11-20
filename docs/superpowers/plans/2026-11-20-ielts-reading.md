# IELTS Reading Practice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Do IELTS Reading tests (one Part or a full 3-passage test) on the Kindle in Leaf: passage as a book page with all reading tools, questions in a Leaf panel, timer, scoring, band estimate, "Show in passage".

**Architecture:** A Mac script turns a test JSON into an EPUB (one chapter per passage) with the questions/key embedded at `META-INF/leaf-ielts.json`. The Leaf plugin detects that file on open, adds a footer item, a Questions panel, a word-pick mode in its existing tap hook, and stores progress in the book's own settings. Pure logic (parse, score, band, timer) lives in small modules with LuaJIT checks; widgets are thin.

**Tech Stack:** KOReader Lua plugin (LuaJIT), KOReader widgets (`ButtonTable`, `TextBoxWidget`, `ScrollableContainer`, `InputDialog`), Python 3 stdlib (`zipfile`, `json`) for the builder.

**Spec:** `docs/superpowers/specs/2026-11-20-ielts-reading-design.md`

## Global Constraints

- Plugin dir: `runtime/macos/test-data/plugins/englishpreview.koplugin` (Mac preview); staged to `runtime/kindle/staging/koreadercus/profile/plugins/englishpreview.koplugin` and installed with `runtime/kindle/update-connected.py --plugin-only`.
- Must run on Kindle `kindlehf` firmware 5.18.5 and the Mac preview; no new runtime dependencies.
- E Ink: discrete screens, no animation, tap targets ≥ 44 px, grayscale only.
- Reading tools (tap word, Sentence/Paragraph, idioms, Use AI, Listen) stay on in **both** Practice and Study.
- Non-test books behave exactly as today (footer, taps, menus).
- Test content is never committed: generated tests and private test JSON go in `ielts/` (git-ignored). Only the original sample test (written for this repo) is committed.
- JSON format `version: 1` as in the spec (types `choice`, `multi`, `gap`; top-level `passages`, `groups`).
- All checks: `python3 runtime/macos/checks/run-learning-checks.py` must stay green.

## Review Focus

1. **Curly vs straight quotes / dashes in `evidence`** copied from the web (`farmers’` vs `farmers'`) — builder validation and "Show in passage" must still find it. Test in Task 1 and Task 2.
2. **Word pick on a word with punctuation** (`footprints,`, `farmers’`, `“Hello`) — the stored answer is the bare word. Test in Task 5.
3. **Normal or broken EPUBs** (no JSON, invalid JSON, `version: 2`) — book opens as a normal book, no footer item, taps unchanged. Test in Task 5.
4. **Timer across close / sleep / reopen** — elapsed time persists, never double counts, and reaching zero does not lock answering. Test in Task 3.
5. **Answer formatting** (`" Footprints."`, extra spaces, a 2-word answer in a 1-word gap) — scored by normalized match; over-limit is flagged, not rejected. Test in Task 2.

---

### Task 1: Test builder script and sample test

**Files:**
- Create: `runtime/make-ielts-test.py`
- Create: `runtime/ielts-sample.json` (original sample, the sea-turtle passage from `research/ielts-mockup.html`, 6 questions covering `choice`, `multi`, `gap`, a `groups` entry with `list` and one with `text`)
- Create: `runtime/macos/checks/ielts-builder.py`
- Modify: `runtime/macos/checks/run-learning-checks.py` (also run `*.py` checks in that folder with `python3 -I`, except the runner itself)
- Modify: `.gitignore` (add `ielts/`)

**Interfaces:**
- Produces: `python3 runtime/make-ielts-test.py <test.json> [out_dir=ielts/]` → writes `<out_dir>/<slug(title)>.epub`, prints its path; exit 1 with a message naming the problem on invalid input.
- Produces: input JSON = spec schema plus `passages[i].paragraphs: [str]`. The EPUB gets `OEBPS/passage<n>.xhtml` per passage (title `h1` + `p` per paragraph, reuse `page()` / packaging approach of `runtime/make-demo-epub.py` — import it or factor a shared helper, do not copy), spine in passage order, and `META-INF/leaf-ielts.json` = the input **without** `paragraphs`.

- [ ] **Step 1: Write the failing check** `ielts-builder.py` (stdlib only, assert-based):
  - builds `runtime/ielts-sample.json` into a temp dir; the EPUB's first entry is `mimetype` stored; it contains `OEBPS/passage1.xhtml` and `META-INF/leaf-ielts.json`; the embedded JSON has no `paragraphs` key and equals the input otherwise.
  - a copy whose question 3 has no `answer` → exit code 1, stderr contains `question 3`.
  - a copy whose evidence for question 1 is not in its passage → exit 1, stderr contains `evidence` and `1`.
  - a copy whose evidence uses `'` where the passage has `’` → builds fine (quotes/dashes normalized for the comparison: `’‘`→`'`, `“”`→`"`, `–—`→`-`, whitespace collapsed).
  - a question number in no `passages` range → exit 1.
- [ ] **Step 2: Run** `python3 runtime/macos/checks/ielts-builder.py` — expected FAIL (script missing).
- [ ] **Step 3: Implement** `make-ielts-test.py` and `ielts-sample.json`; add `ielts/` to `.gitignore`; extend the runner to run `.py` checks.
- [ ] **Step 4: Run** `python3 runtime/macos/checks/run-learning-checks.py` — expected: all PASS including `ielts-builder.py`.
- [ ] **Step 5: Commit** `feat(ielts): test builder script and original sample test`

---

### Task 2: Test logic module

**Files:**
- Create: `runtime/macos/test-data/plugins/englishpreview.koplugin/english_ielts.lua`
- Create: `runtime/macos/checks/english-ielts.lua` (register in runner like `english-context.lua`)

**Interfaces:**
- Produces (pure, no KOReader requires except `json`):
  - `M.parse(text: string) -> test|nil, err` — `nil` for invalid JSON, `version ~= 1`, no questions. Adds `test.byNumber[n] = question` (a `multi` question is indexed under each of its numbers) and `test.total` (count of numbers).
  - `M.normalize(s: string) -> string` — lowercase, quotes/dashes as in Task 1, strip leading/trailing spaces and punctuation, collapse inner spaces.
  - `M.passageOf(test, n: number) -> passage table|nil`
  - `M.overLimit(question, answer: string) -> boolean` — `gap` only: word count > `question.words`.
  - `M.score(test, answers: {[n]=string|table}) -> {right=, total=, passages={{n=,right=,total=}}, rows={{n=, answer=, correct=, ok=}}}` — `choice`: normalized equality; `gap`: equal to `answer` or any `accept`; `multi`: `answers[first n]` is a list of picked letters, one point per correct pick, rows per number.
  - `M.band(right: number, total: number) -> number, rough: boolean` — if `total ~= 40` scale `right*40/total` (round down), `rough=true`. Academic table: 39–40→9, 37–38→8.5, 35–36→8, 33–34→7.5, 30–32→7, 27–29→6.5, 23–26→6, 19–22→5.5, 15–18→5, 13–14→4.5, 10–12→4, 8–9→3.5, 6–7→3, 4–5→2.5, else 2.

- [ ] **Step 1: Write the failing check** `english-ielts.lua` using the embedded JSON from the Task 1 sample (read `runtime/ielts-sample.json`, strip `paragraphs` in Lua or use the built EPUB's JSON):
  - `parse` of `'{'`, `'{"version":2,"questions":[{}]}'` and `'{"version":1,"questions":[]}'` → `nil`.
  - `normalize(" Footprints. ")=="footprints"`, `normalize("farmers’")=="farmers'"`.
  - gap with `accept={"footprint"}`: `"Footprint"` scores, `"tracks"` does not.
  - `overLimit({type='gap',words=1},"two words")==true`, `overLimit(...,"word")==false`.
  - multi `n={20,21}`, `answers={"B","D"}`: picks `{"D","A"}` → 1 right of 2.
  - `score` returns per-passage totals for a 2-passage test fixture (inline in the check).
  - `band(40,40)==9`, `band(30,40)==7`, `band(9,13)` → `27/40` → `6.5, true`.
- [ ] **Step 2: Run** the runner — expected FAIL (`english-ielts.lua`: module not found).
- [ ] **Step 3: Implement** `english_ielts.lua`.
- [ ] **Step 4: Run** the runner — expected all PASS.
- [ ] **Step 5: Commit** `feat(ielts): parse, score and band estimate`

---

### Task 3: Session (answers, mode, timer, persistence)

**Files:**
- Create: `runtime/macos/test-data/plugins/englishpreview.koplugin/english_ielts_session.lua`
- Modify: `runtime/macos/checks/english-ielts.lua` (add session cases)

**Interfaces:**
- Consumes: `english_ielts` (Task 2).
- Produces: `Session.new(test, store) -> session` where `store` has `readSetting(key)` / `saveSetting(key, value)` (KOReader `doc_settings`); key `"leaf_ielts"` holding `{mode=, answers=, elapsed=, finished=}`.
  - `session:mode() -> "practice"|"study"|nil`, `session:setMode(m)`
  - `session:answer(n) -> string|table|nil`, `session:setAnswer(n, value)` (saves immediately)
  - `session:answered() -> number` (count of numbers with a non-empty answer)
  - `session:start(now)`, `session:pause(now)` — accumulate `elapsed` seconds between start/pause; `pause` without `start` is a no-op (no double counting).
  - `session:remaining(now) -> seconds` (`minutes*60 - elapsed`, never below 0; `nil` in study mode)
  - `session:footer(now) -> string` — practice `"Q 3/13 · 14:20"`, study `"Q 3/13"`.
  - `session:finish()`, `session:reset()` (clears answers, elapsed, finished; keeps mode).

- [ ] **Step 1: Write the failing cases** with a table-backed fake store:
  - setAnswer → a new `Session.new` on the same store sees it (persistence).
  - `start(0)`, `pause(100)`, `pause(200)`, `start(300)`, `pause(350)` → elapsed 150.
  - practice 20 min, elapsed 1300 → `remaining == 0` and `setAnswer` still works (no lock).
  - `footer` strings exactly as above for both modes.
  - `reset()` keeps mode, clears answers and elapsed.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** `english_ielts_session.lua`.
- [ ] **Step 4: Run** — expected all PASS.
- [ ] **Step 5: Commit** `feat(ielts): session state and timer`

---

### Task 4: Questions panel and results screen

**Files:**
- Create: `runtime/macos/test-data/plugins/englishpreview.koplugin/english_ielts_panel.lua`
- Create: `runtime/macos/checks/english-ielts-panel.lua` (stub widgets the same way `english-preview.lua` does; find buttons/texts by label)

**Interfaces:**
- Consumes: Tasks 2–3.
- Produces: `Panel.show{test=, session=, passage=n, on_pick=function(n), on_passage=function(), on_evidence=function(question), now=function()}` → full-screen widget.
  - Top: **← Passage** (calls `on_passage`), progress dots (filled = answered), timer text from `session:footer`.
  - Passage switch **Passage 1 · 2 · 3** only when `#test.passages > 1`; selected one shown inverted.
  - Per group: title, instructions, `list` lines, `text` with `{n}` replaced by the blank.
  - `choice`: one equal-width button row of `options`; selected button inverted; tap → `session:setAnswer` and redraw.
  - `multi`: same row, up to `picks` selections toggled.
  - `gap`: blank shows answer or `____`; tap → `on_pick(n)`; over-limit answers shown with a `!` marker.
  - Bottom: **Finish** → results view: `right/total`, per-passage lines when several passages, `Band ≈ x` (+ `(rough)`), time used, one row per number `✓/✗ n. your → correct`, each with **Show in passage** (`on_evidence(question)`); buttons **Try again** (`session:reset()` then panel) and **Done** (`on_passage`).

- [ ] **Step 1: Write the failing check**: build the sample test + fake session; assert dots count = `test.total`; tapping `TRUE` on Q1 stores it and shows it selected; tapping a blank calls `on_pick(4)`; a 2-passage fixture shows the passage switch, a 1-passage one does not; **Finish** shows `"/6"` and a `Show in passage` that calls `on_evidence` with question 1; **Try again** empties answers.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** the panel; reuse `english_popup.lua` fonts/sizes (`cfont` 18 body, `tfont` 22 titles) and `ScrollableContainer` for the list.
- [ ] **Step 4: Run** — expected all PASS.
- [ ] **Step 5: Commit** `feat(ielts): questions panel and results`

---

### Task 5: Wire into the reader (detect, footer, open, word pick, show in passage)

**Files:**
- Modify: `runtime/macos/test-data/plugins/englishpreview.koplugin/main.lua` (`Preview:onReaderReady`, `Preview:installTapLookup`, `Preview:addToMainMenu`, new `Preview:ielts*` methods)
- Modify: `runtime/macos/checks/english-preview.lua` (or new `english-ielts-reader.lua`) for wiring cases

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces:
  - `Preview:loadIelts()` — in `onReaderReady`, when `self.ui.rolling`: `self.ui.document:getDocumentFileContent('META-INF/leaf-ielts.json')` → `english_ielts.parse`; on success set `self._ielts={test=, session=Session.new(test, self.ui.doc_settings)}`, add footer content (`self.ui.view.footer:addAdditionalFooterContent(fn)` returning `session:footer(os.time())`), and call `session:start(os.time())`; ask **Practice / Study** (Leaf popup) if `session:mode()` is nil. Any failure → no `_ielts`, nothing else changes.
  - `onCloseDocument` / `onSuspend`: `session:pause(os.time())`; `onResume`: `session:start(os.time())`; remove footer content on close.
  - Practice: a once-per-minute check (`UIManager:scheduleIn(60, …)`, cancelled on close) shows an `InfoMessage` "Time is up — you can keep answering." the first time `remaining` reaches 0 (remember it in the session store so it shows once). Check: remaining 0 → message shown once, second check → not shown again.
  - `Preview:showQuestions()` — current passage = chapter index of the current page (`self.ui.toc` / document fragment index of the current xpointer, 1-based in spine order); opens `Panel.show` with callbacks below.
  - Footer tap opens the panel only when `self._ielts` is set (wrap `ReaderFooter:onTapFooter`; otherwise call the original). **English tools → Questions** menu entry, enabled only for tests.
  - Word pick: `self._ielts.picking = n`. In the tap hook, when `picking` is set and a word is tapped: append the bare word (strip leading/trailing punctuation and quotes, `’`→`'`) to `session:answer(n)` with a space, do **not** open the dictionary; if `question.words == 1` finish picking and reopen the panel at `n`. A top banner (Leaf popup at the top, small) shows `Q7 · <answer> · Done · Clear · Type instead`; **Type instead** opens an `InputDialog`. Hold-drag keeps translating.
  - `Preview:showEvidence(question)` — `findText(evidence)` restricted to the question's passage chapter (try exact, then the normalized form from Task 2); go to the hit and set `self.view.highlight.temp[page]` like `readersearch.lua` does; clear on next page turn or tap.

- [ ] **Step 1: Write the failing checks** with a stubbed `ui`:
  - document returning no file / `"{"` / `{"version":2}` → `_ielts` nil, no footer content added, tap hook opens the dictionary as before.
  - valid test → footer content returns `"Q 0/6 · 20:00"` in practice.
  - picking Q4 then tapping a word whose text is `amber,` → answer `"amber"`, panel reopened, dictionary not called; a 2-word gap: two taps → `"motion sensors"`, still picking until **Done**.
  - `showEvidence` with a curly-quote passage and straight-quote evidence finds it.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** the wiring in `main.lua`.
- [ ] **Step 4: Run** the runner — expected all PASS.
- [ ] **Step 5: Commit** `feat(ielts): reader integration`

---

### Task 6: End-to-end on the Mac preview and the Kindle

**Files:**
- Modify: `runtime/kindle/staging/...` via copy of the plugin `.lua` files (no source changes expected)
- Create (git-ignored): `ielts/night-lights-and-sea-turtles.epub` from the sample

- [ ] **Step 1:** `python3 runtime/make-ielts-test.py runtime/ielts-sample.json` → prints the EPUB path.
- [ ] **Step 2:** Open it in the Mac preview (`KO_HOME=runtime/macos/test-data … koreader ielts/<file>.epub`). Verify by hand: mode popup → footer `Q 0/6 · 20:00` → footer tap opens the panel → TFNG tap, gap pick from passage, Finish → results → Show in passage highlights the sentence. Normal book (`demo/leaf-demo.epub`) shows no footer item.
- [ ] **Step 3:** Copy plugin `.lua` files to staging; with the Kindle mounted run `python3 runtime/kindle/update-connected.py --plugin-only` → result JSON with `"plugin_verified": true`; copy the EPUB to `/Volumes/Kindle/documents/IELTS/` (exclusive create, sha256 compare, remove AppleDouble).
- [ ] **Step 4:** On the Kindle: open the test; confirm `META-INF/leaf-ielts.json` is detected (footer item appears). If not, switch the builder and `loadIelts` to `OEBPS/leaf-ielts.json` (spec fallback) and repeat Steps 1–3.
- [ ] **Step 5: Commit** `chore(ielts): verified on Mac preview and Kindle`
