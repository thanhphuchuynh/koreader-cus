# IELTS Test Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tests look like the mockup: top bar `[Passage] [Questions]` + timer and bottom bar `Questions →` / `[ Finish ]` on the reader page and in the Questions view; blanks answered by tapping words, no keyboard.

**Architecture:** A new `english_ielts_bars.lua` builds the two bars (shared by the reader overlay and the Questions panel) and a reader overlay that forwards all other input to the reader. `main.lua` shows the overlay for test books, reserves page margins, drops the footer item, and runs pick mode through the top bar. `english_ielts_panel.lua` draws the same bars.

**Tech Stack:** KOReader Lua plugin (LuaJIT), KOReader widgets, `ReaderTypeset` margin events.

**Spec:** `docs/superpowers/specs/2026-11-22-ielts-test-layout-design.md` (extends `docs/superpowers/specs/2026-11-20-ielts-reading-design.md`); mockup `research/ielts-mockup.html`.

## Global Constraints
- Copy (exact): tabs `Passage`, `Questions`; bottom `Questions →`, `Finish`, `← Passage`; finish confirm `Finish and see your score?` with `Finish` / `Cancel`; pick bar `Tap the word for Q<n>` with `Done` / `Cancel`; timer `MM:SS` (Practice only, nothing in Study).
- Selected tab = inverted (Button `preselect`, as in `english_ielts_panel.lua`); tap targets ≥ 44 px; grayscale; no animation.
- Normal (non-test) books: no bars, no margin change, no footer change, taps unchanged.
- Reading tools stay on in tests: taps outside the bars reach the reader unchanged.
- `Type instead` and `Preview:ieltsType` are removed; no keyboard anywhere in the test flow.
- Checks green: `python3 runtime/macos/checks/run-learning-checks.py`; new checks registered with the plugin dir.

## Review Focus
1. **Closing the book or suspending while the overlay or pick bar is up** — bars close, no widget left on another book. Task 2.
2. **Page turns, hold-drag translate and tap-word while the overlay is shown** — still reach the reader. Task 1 (forwarding) + Task 2.
3. **Cancel in pick mode after picking two words** — answer restored to what it was before. Task 2.
4. **Finish from either bar on an unfinished test, then Cancel** — nothing scored, timer keeps running. Task 2/3.
5. **Margins on a test book that already has user margins** — the bars' height is added to the user's top/bottom margins once (not again on every open). Task 2.

---

### Task 1: Bars module

**Files:** Create `runtime/macos/test-data/plugins/englishpreview.koplugin/english_ielts_bars.lua`; Create `runtime/macos/checks/english-ielts-bars.lua` (register in runner).

**Interfaces — Produces:**
- `Bars.top(w, o) -> widget` — `o = {tab="passage"|"questions", timer=string|nil, on_passage=fn, on_questions=fn}`; or pick form `o = {pick=n, on_done=fn, on_cancel=fn}` → `Tap the word for Q<n>` + `Done` + `Cancel`.
- `Bars.bottom(w, o) -> widget` — `o = {view="passage"|"questions", on_questions=fn, on_passage=fn, on_finish=fn}`: passage view `Questions →` + `Finish`; questions view `← Passage` + `Finish`.
- `Bars.confirmFinish(on_yes)` — ConfirmBox with the exact copy.
- `Bars.overlay(o) -> handle` — shows top (y=0) and bottom (y=screen_h - bottom_h) as one non-modal widget; `handle:update(o)` rebuilds bars in place (`'ui'` refresh of their regions only), `handle:heights() -> top_h, bottom_h`, `handle:close()`. Gestures and key events NOT inside a bar are forwarded to `o.forward(event)` (the reader); inside a bar they go to its buttons.
- [ ] Step 1: failing check — top/bottom texts per form; selected tab preselected; timer omitted when nil; overlay forwards a tap outside the bars and keeps a tap inside; `update` changes the timer text; `close` closes once; confirmFinish copy and callbacks.
- [ ] Step 2: run runner → FAIL. Step 3: implement (style like `english_ielts_panel.lua`). Step 4: runner → PASS. Step 5: commit `feat(ielts-layout): bars module`.

### Task 2: Reader wiring

**Files:** Modify `runtime/macos/test-data/plugins/englishpreview.koplugin/main.lua` (loadIelts/closeIelts, tick, pick mode, remove footer item, TapFooter wrapper, ieltsBanner, ieltsType); Modify `runtime/macos/checks/english-ielts-reader.lua`.

**Interfaces — Consumes:** Task 1 `Bars.*`. **Produces:** overlay shown after a test loads (and after mode choice), `tab="passage"`; `Questions →`/`Questions` open `showQuestions()`; `Finish` → `confirmFinish` → pause+finish → results; timer text refreshed by the existing minute tick via `handle:update`; overlay closed in `closeIelts` and on suspend, re-shown on resume.
- Margins: on first load of a test book add the overlay's `top_h`/`bottom_h` (converted the way ReaderTypeset expects) to the book's current top/bottom margins via `onSetPageTopMargin`/`onSetPageBottomMargin` events, and remember it in the session store (`margins_added=true`) so it is never added twice.
- Pick mode: top bar switches to the pick form; each tapped word appends (existing bareWord logic), the last picked word is highlighted with `document:getTextFromXPointers(pos0,pos1,true)` + `setDirty`; `Done` → back to questions at that question; `Cancel` → restore the answer saved when pick started, back to questions; one-word blanks return automatically. Remove `ieltsBanner`, `ieltsType`, `Type instead`.
- Remove the footer additional content and the `TapFooter` diversion.
- [ ] Step 1: failing checks — overlay shown for a test book and not for a normal book; footer content no longer added; Finish asks then scores; Cancel on confirm leaves it unfinished; pick: two taps then Cancel restores; Done returns to questions; margins added once across two loads; close/suspend closes the overlay; no `Type instead` text anywhere.
- [ ] Steps 2–5: run FAIL, implement, PASS (all runner checks), commit `feat(ielts-layout): reader bars, margins, tap-only blanks`.

### Task 3: Questions view bars

**Files:** Modify `runtime/macos/test-data/plugins/englishpreview.koplugin/english_ielts_panel.lua`; Modify `runtime/macos/checks/english-ielts-panel.lua`.

**Interfaces — Consumes:** `Bars.top` (`tab="questions"`), `Bars.bottom` (`view="questions"`), `Bars.confirmFinish`. Replace the panel's own top row (`← Passage`, dots, timer) and bottom `Finish` with the bars; keep progress dots under the top bar; the list scrolls between the bars. `Passage` tab and `← Passage` call `on_passage`; `Finish` confirms first. Results screen unchanged.
- [ ] Steps 1–5: failing check (tabs present with Questions selected, `← Passage` + `Finish` at bottom, Finish asks first), FAIL, implement, PASS, commit `feat(ielts-layout): questions view bars`.

### Task 4: End to end (controller)
- [ ] Mac preview screenshots: passage view with bars (no text covered), Questions view, pick bar, Finish confirm; normal book unchanged. Compare with `research/ielts-mockup.html`.
- [ ] Kindle: sync staging, `update-connected.py --plugin-only` when connected.
