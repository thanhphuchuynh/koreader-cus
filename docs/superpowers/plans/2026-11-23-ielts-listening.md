# IELTS Listening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** IELTS Listening tests (Exam/Study) on Leaf, imported from youpass.vn, audio over Bluetooth.

**Architecture:** The importer converts audio to raw PCM beside the test EPUB. A new `english_ielts_audio.lua` streams it through the Kindle player route `english_voca.lua` already uses (Mac: `afplay`). The questions panel gets a listening form (audio row, keyboard gaps, replay); `main.lua` runs the audio lifecycle.

**Tech Stack:** Python 3 stdlib + macOS `afconvert` (importer); KOReader Lua plugin (LuaJIT).

**Spec:** `docs/superpowers/specs/2026-11-23-ielts-listening-design.md`; mockup `research/ielts-listening-mockup.html`.

P = `runtime/macos/test-data/plugins/englishpreview.koplugin`; checks in `runtime/macos/checks/` (register new ones in `run-learning-checks.py`).

## Global Constraints
- Copy (exact): modes `Exam` / `Study`; exam row `▶ mm:ss / mm:ss · plays once`; study buttons `−10s`, `▶` / `❚❚`; replay `↺ m:ss`; results `▶ Hear it`, `Transcript`; after-finish tab label `Transcript`; finish confirm as reading.
- PCM: 16-bit little-endian mono, `rate` 16000, file named in `audio.file`, beside the EPUB.
- Exam auto-finish 120 s after the audio ends; exam countdown = audio left + 120 s.
- Audio row refreshes in place every 10 s (`'ui'` on its own region); never redraw the whole panel for time.
- Reading tests behave exactly as before (all existing checks stay green).
- Test content is never committed (`ielts/` is gitignored); importer fixtures in checks are invented text.
- Text never reaches a shell (file paths only, quoted like `english_voca.lua`).

## Review Focus
1. **Closing the book / sleeping while audio plays** — audio process killed, position saved, nothing scheduled left. Task 2 + 4.
2. **Tapping a gap while audio plays, then the 10 s tick fires** — keyboard stays on top, answer not lost. Task 3.
3. **Exam reopened after the audio already ended** — finishes/scores, no negative times. Task 4.
4. **Seek past the end / `at` missing on a question** — no crash; replay hidden when no `at`. Task 2 + 3.
5. **Listen (speech) tapped during test audio** — one sound at a time. Task 4.

---

### Task 1: Importer + builder (Python)

**Files:** Modify `runtime/youpass-import.py`, `runtime/make-ielts-test.py`; Create `runtime/macos/checks/youpass-listening.py`; Modify `runtime/macos/checks/ielts-builder.py`.

**Interfaces — Produces:**
- `youpass-import.py --listening [--count N] [ids…]`: list API `/v1/public/quizzes/list/2,10/3/{page}/true/null/null/null/null` (skip PRO-tagged). Per quiz: `/v1/public/quizzes/{id}`; transcript = `part.vocabs` from `https://youpass.vn/practice/listening/{id}` (same RSC decoding as reading); audio = `https://cms.youpass.vn/assets/{part.file_id}` → `afconvert -f WAVE -d LEI16@16000 -c 1` → frames via `wave` → `<slug>.pcm`. Writes `ielts/listening/<slug>.epub` + `.pcm`.
- Pure `convert_listening(quiz, transcripts, durations) -> test dict` (no network): `transcripts[part_id]` = vocabs tree (level 1 paragraphs, level 2 sentences with `meta.from/to`); `durations[part_id]` = seconds of that part's audio, parts joined in order (offset = sum of earlier durations).
  - `skill:"listening"`, `audio:{file,rate:16000,seconds}`, passages = parts (`title` = part title or `Section k`), paragraphs = `"[m:ss] " + sentences joined` (time of first sentence + offset).
  - Questions as reading's `convert` (choice/multi/gap) plus `at=[from+offset, to+offset]` from `locate_info.time_ranges`; gap `answer` = `correct_answers[0]`, `accept` = the rest (deduped, case-insensitively); evidence from `paragraph_ranges` (sentence text, without the `[m:ss]` prefix).
  - Raises `ValueError` on any `MAP_DIAGRAM_LABEL` question (test skipped).
- `make-ielts-test.py validate`: if `skill=="listening"`: `audio.file` non-empty str, `audio.rate` int > 0, `audio.seconds` number > 0; each `at` (if present) = 2 numbers, `0 <= from <= to <= seconds`; `accept` (if present) = list of str. Reading input unchanged.
- [ ] Step 1: failing checks — `youpass-listening.py` imports the script by path, feeds an invented 2-part fixture (a gap with 2 correct answers, a choice, a multi), asserts offsets on part 2 `at`, `[0:05]`-style prefixes, `accept`, evidence text, MAP_DIAGRAM_LABEL → ValueError; `ielts-builder.py`: listening sample builds; bad `at` (> seconds) and missing `audio.rate` fail.
- [ ] Step 2: FAIL. Step 3: implement. Step 4: runner PASS. Step 5: commit `feat(ielts-listening): importer and builder`.
- [ ] Step 6 (network, not a check): `python3 runtime/youpass-import.py --listening --count 3` produces 3 EPUB + PCM pairs; report sizes.

### Task 2: Audio player + parse

**Files:** Modify `P/english_ielts.lua`, `P/english_voca.lua`; Create `P/english_ielts_audio.lua`, `runtime/macos/checks/english-ielts-audio.lua`; Modify `runtime/macos/checks/english-ielts.lua`.

**Interfaces — Produces:**
- `english_ielts.parse`: keeps `skill`, `audio`, `at`, `accept`; a listening test without a valid `audio` → `nil,'listening test without audio'`.
- `english_voca` exports (refactor, behaviour unchanged): `M.spawn(command)->pid|nil`, `M.alive(pid)->bool`, `M.gstVersion()->'0.10'|'1.0'|nil` (uses `M.bin_dir`), `M.musicFocus()` (the lipc setFocus call).
- `english_ielts_audio.new{path=, rate=, seconds=, kindle=bool} -> a`:
  - `a:play(from, to)` — starts at `from` s (clamped to `[0, seconds)`), stops at `to` if given; stops any current play first. Kindle: `dd if=<path> bs=<rate*2> skip=<floor(from)> [count=<n>] 2>/dev/null | <bin_dir>/gst-launch-<v> fdsrc ! capsfilter caps=<same caps as voca> ! mixersink stream-type=Music sync=true`; Mac: writes a WAV slice to `/tmp/leaf-ielts-audio.wav` and runs `afplay`.
  - `a:pause() -> pos`, `a:stop()`, `a:position() -> seconds` (start + wall time while playing; frozen when paused), `a:isPlaying()`, `a.on_end` (called once when playback reaches `to`/end on its own, not on pause/stop).
  - Polls process with `UIManager:scheduleIn(0.5, …)`; `stop`/`pause` unschedule and kill.
  - Module-level `M.now` (wall clock, like `english_voca.M.now`) replaceable by checks.
- [ ] Step 1: failing checks — parse keeps fields / rejects bad audio; audio with fake `gst-launch-0.10` (`cat > out`) on a 3 s PCM file: `play(1)` writes bytes from 1 s; `to` limits; `position` moves with fake clock and freezes on pause; `on_end` once on natural end, not on stop; stop kills and leaves nothing scheduled; voca checks unchanged.
- [ ] Steps 2–5: FAIL, implement, PASS (all), commit `feat(ielts-listening): audio player`.

### Task 3: Listening panel

**Files:** Modify `P/english_ielts_panel.lua`, `P/english_ielts_bars.lua`; Modify `runtime/macos/checks/english-ielts-panel.lua`, `runtime/macos/checks/english-ielts-bars.lua`.

**Interfaces — Consumes:** Task 2 audio object, passed as `o.audio`. **Produces** (`P.show(o)` when `test.skill=='listening'`):
- Bars: `Bars.top(w,{title=s, timer=t})` → title + timer, no tabs; `Bars.bottom(w,{view='listening',on_finish=})` → only `Finish`; `Bars.top` normal form accepts `passage_label` (default `Passage`).
- Questions view: audio row under the top bar (exam/study forms, exact copy); study `−10s` = `audio:play(max(0,pos-10))`, `▶/❚❚` toggles; `↺ m:ss` after a question with `at` (study only) = `audio:play(at[1])`. Exam timer text from `o.exam_left()` (seconds) → `mm:ss`.
- `widget:updateAudio()` updates the row/timer text in place + `setDirty(widget,'ui',row region)`; the panel schedules it every 10 s while shown and unschedules on close (`onCloseWidget`).
- Gap tap → `InputDialog` titled `Q<n> · up to <words> word(s)`, input = current answer; Save → `setAnswer` + redraw; Cancel → nothing. Not `on_pick`.
- Results (listening): each row also `▶ Hear it` → `o.on_hear(q)` (only when `q.at`), and `Transcript` replaces `Show in passage` (same `on_evidence`).
- Reading form unchanged.
- [ ] Steps 1–5: failing checks (listening top/bottom, row copy per mode, study buttons call audio, replay hidden without `at`, InputDialog save/cancel, tick updates in place without closing the panel and is unscheduled on close, results buttons), FAIL, implement, PASS, commit `feat(ielts-listening): questions view`.

### Task 4: Reader wiring

**Files:** Modify `P/main.lua`, `P/english_tests_module.lua`, `P/english_tests.lua`; Modify `runtime/macos/checks/english-ielts-reader.lua`, `runtime/macos/checks/english-tests*.lua` as needed.

**Interfaces — Consumes:** Tasks 2–3. **Produces:**
- `loadIelts` for `skill=='listening'` (not finished): no bars/margins; first open asks `IELTS Listening` with `Exam` (mode `practice`) / `Study` (mode `study`); then `showQuestions()` and `audio:play(saved pos)`. Reopen with a mode: questions + play from saved position (exam auto, study paused until ▶).
- Audio path = directory of `self.ui.document.file` + `/` + `audio.file`; missing file → info message `Audio file not found: <file>` and the test opens as reading-style (no crash).
- Position saved in the session record (`audio_pos`) on pause/stop/close/suspend; `onSuspend`/`onCloseDocument` stop audio; `onResume` (exam, unfinished) plays on.
- Exam: `exam_left = seconds - pos + 120`; when audio ends, schedule auto-finish at 120 s (also on reopen if already past the end): pause clock, finish, show results.
- `on_hear(q)` plays `q.at[1]`…`q.at[2]+1`. Starting test audio stops speech; Listen during test audio stops test audio (`getSpeech().speak` wrapper stops it).
- After finish: reading bars with `passage_label='Transcript'`.
- Tests tab scans `IELTS` and `IELTS/Listening`; listening items' meta begins `Listening ·`.
- [ ] Steps 1–5: failing checks (mode prompt copy and modes, missing audio message, suspend/close stop + save pos, exam auto-finish after end+120, resume plays on, on_hear range, transcript label, Tests scans both folders), FAIL, implement, PASS, commit `feat(ielts-listening): reader wiring`.

### Task 5: End to end (controller)
- [ ] Import 2 sections + 1 full test; Mac app screenshots: start prompt, exam row, study row, keyboard, results, transcript. Audio plays on Mac (afplay).
- [ ] Kindle (when connected): sync staging, `update-connected.py --plugin-only`, copy tests to `documents/IELTS/Listening/`.
