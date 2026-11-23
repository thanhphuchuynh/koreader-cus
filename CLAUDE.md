# koreader-cus

- Adding or importing a test (IELTS, TOEIC): follow `docs/adding-tests.md`. Build into `ielts/` or `toeic/` (gitignored).
- Never commit third-party test content (questions, passages, audio, photos). Only original samples go in `runtime/`.
- A new test field or question type changes `runtime/make-ielts-test.py` (validate), `english_ielts.lua` (parse),
  the questions panel, and their checks together.
- Run `python3 runtime/macos/checks/run-learning-checks.py` after plugin or builder changes.
