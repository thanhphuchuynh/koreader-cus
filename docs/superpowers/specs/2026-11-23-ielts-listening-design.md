# IELTS Listening on Leaf — design

Date: 2026-11-23 · Status: approved by the user (mockup `research/ielts-listening-mockup.html`, "ok build it")
Extends: `2026-11-20-ielts-reading-design.md`, `2026-11-22-ielts-test-layout-design.md`.

## Intent
Practise IELTS Listening on the Kindle Basic with Bluetooth headphones, using tests imported from
youpass.vn (audio, questions, answers, timed transcript). Two modes, as chosen: **Exam** (audio plays
once, no controls) and **Study** (pause, −10 s, replay the part for one question).

## Approaches (chosen: A)
- **A. Convert audio on the Mac to raw PCM; stream it through the Kindle player Leaf already uses**
  (`gst-launch … mixersink`, proven by Listen). Seek = start the stream at an offset. ~10 MB per section.
- B. Ship the original AAC/M4A and decode on the Kindle — unknown decoder support on 5.18; rejected.
- C. Play from the web — the Kindle is offline when reading; rejected.

## Data
- Test EPUB as for reading (`META-INF/leaf-ielts.json`), plus:
  - `"skill": "listening"`; `"audio": {"file": "<slug>.pcm", "rate": 16000, "seconds": <float>}` —
    16-bit little-endian mono PCM, stored next to the EPUB.
  - Each question may have `"at": [from, to]` (seconds in that audio). Gap answers may have `accept`.
  - Passages = sections; their chapters hold the transcript, one paragraph per speaker turn, each
    starting with its time `[m:ss]`. Evidence = the answer sentence(s) of the transcript.
- Full tests (4 sections): the importer joins the section audio into one file and shifts times.
- Importer: `runtime/youpass-import.py --listening …` (audio = `cms.youpass.vn/assets/<file_id>`,
  converted with macOS `afconvert`). Tests with map/diagram questions are skipped (need a picture).
  Output: `ielts/listening/` (gitignored). On the Kindle: `documents/IELTS/Listening/`.

## Screens (as the mockup)
1. **Start** — opening a listening test the first time asks **Exam** / **Study**; the choice starts
   the audio and shows the Questions view. Reopening resumes at the saved position (Exam: plays on).
2. **Questions view** (no Passage tab before Finish): top bar = title + (Exam) countdown =
   audio left + 2:00 check time; audio row under it:
   - Exam: `▶ mm:ss / mm:ss · plays once` (no buttons).
   - Study: `−10s` `▶/❚❚` `mm:ss / mm:ss`; each question shows `↺ m:ss` (its `at[1]`) that plays from there.
   - The row updates in place every 10 s (E Ink), never by redrawing the whole panel.
3. **Gaps** — tap opens the Kindle keyboard (InputDialog) with the word limit in its title; audio
   keeps playing; Save stores the answer (over the limit shows `!` as in reading).
4. **Finish** — same confirm as reading. Exam also finishes by itself 2:00 after the audio ends.
   Finishing stops the audio.
5. **Results** — score/band as reading; each row has `▶ Hear it` (plays `at[1]`…`at[2]`+1 s) and
   `Transcript` (opens the transcript at the evidence, like *Show in passage*).
6. **Transcript** — the book's own pages (reading tools on). After Finish the reading bars come
   back with the tab labelled `Transcript` instead of `Passage`.

## Behaviour rules
- Audio stops on close/suspend; position is saved in the test record; resume continues there.
- Only one sound at a time: starting test audio stops Listen speech and vice versa.
- Reading tests are unchanged.

## Non-goals (v1)
Map/diagram questions; a player on the transcript page; Bluetooth pairing UI; speaker names.

## Left to the builder
Widget details, how the progress row is laid out, exact countdown text.
