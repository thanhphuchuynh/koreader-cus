# Tests tab folders and TOEIC part practice — design

Approved in conversation on 2026-11-23 (mockup: `research/tests-folders-mockup.html`).

## Intent
The Tests tab mixes every test in one capped list. The user wants folders, and wants to practise
TOEIC Listening & Reading one part at a time (Part 1–7) next to the IELTS tests.

## Goals
- Tests tab: summary, Continue card, then three folder rows: **IELTS Listening**, **IELTS Reading**, **TOEIC**.
  Each row shows its count, number done, and (IELTS) last band or (TOEIC) best accuracy.
- Tapping an IELTS folder opens a full-screen list of that skill's tests; tapping TOEIC opens Part 1–7,
  each part opens its sets. Tapping a test opens today's Start / Continue / Review·Retry dialog.
- A TOEIC set is a test book like an IELTS one, with `exam: "toeic"` and `part: 1..7` in
  `META-INF/leaf-ielts.json`. Parts 1–4 are listening (audio + saved position, as IELTS Listening);
  parts 5–7 are reading.
- Finished TOEIC sets show right answers and a percentage (`27/30 · 90%`), never a band or a scaled score.

## Non-goals
- No TOEIC 5–495 scaled score (needs the full section and unpublished tables).
- No importer for any TOEIC website; sets are written as JSON and built with `make-ielts-test.py`.
  An importer is a later project once the user picks a source.
- No TOEIC Speaking & Writing.

## Format (additions to the leaf-ielts.json schema)
- `exam`: `"toeic"` (absent = IELTS). `part`: integer 1–7, required for TOEIC.
  Parts 1–4 must have `skill: "listening"` (and `audio`); parts 5–7 must not.
- Question `image`: a file name for Part 1 photos. The builder copies it from beside the JSON into
  `OEBPS/images/` and the questions panel draws it above the options.
- Part 2: `choice` questions with `options: ["A","B","C"]` and no `text` (spoken in the real test).
- TOEIC sets may omit `passages`: the builder makes one cover page ("Part 5 · Incomplete sentences —
  open Questions to answer") covering every question. Parts 6–7 give real passages, as IELTS Reading.

## Folders on disk
Scanned: `IELTS`, `IELTS/Listening`, `IELTS/Reading`, `TOEIC`, `TOEIC/Part 1` … `TOEIC/Part 7` under the home folder.
A test lands in a folder by its own fields (`exam`, `skill`, `part`), not by where the file sits.

## Calls made by Claude (correctable)
- Percent, not scaled score, for part practice; summary "last band" stays IELTS-only.
- Part names: 1 Photographs, 2 Question–response, 3 Conversations, 4 Talks, 5 Incomplete sentences,
  6 Text completion, 7 Reading passages.
- Mode prompts and the listening title say "TOEIC Part N" instead of "IELTS …".
- The capped rows and the "All tests" button go; folders replace them.
