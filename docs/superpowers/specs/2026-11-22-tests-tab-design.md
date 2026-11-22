# Tests tab in Leaf (SimpleUI) — design

Date: 2026-11-22 · Status: draft for approval · Mockup: `research/tests-tab-mockup.html` (option A)

## Intent
IELTS / English tests get their own place, separate from the book library: a **Tests** tab right
after **Home** in SimpleUI's bottom bar, showing every test with its status and score and a
one-tap Start / Continue / Review / Retry. Taking a test is unchanged (passage page + Questions
panel from the IELTS feature).

## Goals / non-goals / anti-goals
- Goals: Tests tab after Home; a page that looks like Home (tab bar stays visible); per test:
  title, kind, question count, time, status (not started / in progress with answered dots and time
  left / finished with score and band); a summary row (tests, finished, last band); empty state.
- Non-goals: new test-taking layout; syncing; editing tests on the device.
- Anti-goals: changing SimpleUI's own code; slowing down Home or page turns; the tab reappearing
  after the user deliberately removes it.

## Approaches (user picked A)
| | Approach | Trade-off |
|---|---|---|
| **A (chosen)** | SimpleUI **Custom Screen** "Tests" holding a **Leaf module** registered through SimpleUI's external-module API; the screen's Quick Action placed after Home in the tab bar | Native look, tab bar stays, uses SimpleUI's public extension points only. Needs module + screen + tab setup. |
| B | Tab calls a Leaf method that shows a full-screen Leaf page | Simplest, but covers the tab bar (inconsistent with Home/Library/History). |
| C | Folder Quick Action to `documents/IELTS` | No code, but no status/score/Continue; looks like any folder. |

## Design (decided)
1. **Module** `english_tests_module.lua` (Leaf plugin), registered with
   `require("modules/moduleregistry").register(module)` when SimpleUI is present (pcall; no-op
   otherwise). Contract per `simpleui.koplugin/modules/moduleregistry.lua` (id, name, build(w, ctx),
   getHeight(ctx)). Layout as the mockup: summary row, "Continue" (most recent in-progress test),
   "All tests" (not started first, then in progress, then finished).
2. **Finding tests:** every `.epub` in `<home_dir>/IELTS/` (home_dir = KOReader home, i.e.
   `/mnt/us/documents` on the Kindle). Read `META-INF/leaf-ielts.json` straight from the zip with
   KOReader's archive reader (no document open), parse with `english_ielts.parse`. Cache per file by
   (path, size, mtime) in memory.
3. **Status:** from the progress Leaf already saves per book (`DocSettings` → `leaf_ielts`):
   answered count, time left (practice), finished → `english_ielts.score` + `band`.
4. **Actions:** Start / Continue open the test in the reader. Review opens it and shows the results
   screen. Retry resets the saved progress (with a confirm) and opens it.
5. **Tab setup, once:** on first run with SimpleUI present, Leaf creates a Custom Screen "Tests"
   (through `infra/sui_custom_screens`), puts the module on its layout, and inserts the screen's
   Quick Action right after Home in the tab bar. A Leaf setting records that this was done, so a tab
   the user removes is not re-added. If the bar is full, Tests replaces nothing and Leaf shows a
   one-time hint instead.
6. **Empty state:** "No tests yet — put test files in documents/IELTS".
7. **Checks:** test scanning/status/summary as pure logic with LuaJIT checks (fake archive + fake
   DocSettings); module build with stub widgets; tab setup idempotent and respects removal.
   End-to-end on the Mac preview (screenshots), then install on the Kindle.

## Left to the builder
- Exact SimpleUI ids (Home tab id, Custom Screen layout format) — read them from SimpleUI's code.
- Widget composition for cards (reuse SimpleUI module chrome where it fits).
- Archive reader choice (`ffi/archiver` vs other bundled zip reader) — whichever exists on Kindle.
