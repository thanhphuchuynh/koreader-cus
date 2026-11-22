# IELTS test layout like the mockup — design

Date: 2026-11-22 · Status: approved by the user · Mockup: `research/ielts-mockup.html`
Extends: `docs/superpowers/specs/2026-11-20-ielts-reading-design.md` §4.

## Intent
Opening a test should look like the agreed mockup, not like a book with a footer item. And blanks
are answered by tapping words in the passage — no keyboard.

## Design (approved)
1. **Test bars on the reader page** (test books only, while a test is open):
   - Top bar: `[Passage] [Questions]` switch (current one inverted) + timer `MM:SS` (Practice only).
   - Bottom bar: `Questions →` and `[ Finish ]`.
   - Both are thin non-modal Leaf widgets; taps outside them go to the reader (tap-word, Sentence,
     idioms, Listen, page turns all unchanged).
   - Leaf sets extra top/bottom page margins for test books so the bars never cover text; normal
     books keep their margins and look exactly as before.
   - The old footer item (`Q 3/13 · 14:20`) and the footer-tap shortcut are removed.
2. **Questions view** uses the same bars: top `[Passage] [Questions]` (Questions selected) + timer;
   bottom `← Passage` and `[ Finish ]`. The question list in between is the existing panel content.
3. **Finish** asks `Finish and see your score?` (`Finish` / `Cancel`) before scoring.
4. **Blanks without typing:** tapping a blank switches to the passage; the top bar becomes
   `Tap the word for Q5 · Done · Cancel`. Each tapped word is appended; the last picked word stays
   highlighted in the passage. One-word blanks return to the questions automatically. `Type
   instead` is removed. Cancel restores the previous answer.
5. Normal books: no bars, no margin change, no footer change.

## Non-goals
Changing the results screen, the Tests tab, scoring, or the question list content.
