---
target: Leaf UI/UX and theme (KOReader E Ink)
total_score: 23
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
target_identity: "file:/Users/tphuc/coding/kindle/runtime/macos/test-data/plugins/englishpreview.koplugin"
timestamp: 2026-11-19T10-20-32Z
slug: test-data-plugins-englishpreview-koplugin-0787c1b8
---
# Leaf (KOReader fork, Kindle Basic E Ink) — UI/UX & theme critique

Method: design review only (detector not applicable: KOReader Lua UI, not web markup). Evidence: 12 screenshots captured in-app on the 600x800 Mac emulator + source.

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Loading…/Translating states good; translated sentence not marked on page; subtitle shows dict id "en-en" |
| 2 | Match System / Real World | 2 | Raw dictionary dump ("/nɜːf/n. 1. (slang)… etc.v. 1."), "en-en", "API base URL / Model ID" |
| 3 | User Control and Freedom | 3 | X + tap-outside work; translation "Back" jumps to an unexpected Sentence-help screen |
| 4 | Consistency and Standards | 2 | Two dictionary UIs (compact square popup vs stock rounded popup); "Save word" vs "Add to vocabulary builder", "Sentence" vs "Sentence help" |
| 5 | Error Prevention | 3 | Sensible defaults; key storage disclosed |
| 6 | Recognition Rather Than Recall | 2 | Review/saved words buried in Tools icon tab; nothing on Home |
| 7 | Flexibility and Efficiency | 2 | Drag still translates; no per-user tuning of popup content |
| 8 | Aesthetic and Minimalist Design | 2 | Dense run-on definition, heavy scrollbar, 6 actions in translation popup, 9 in stock popup |
| 9 | Error Recovery | 3 | Plain messages with next step ("Check Wi-Fi and try again") |
| 10 | Help and Documentation | 1 | No in-app hint for tap→Sentence, idioms, Listen |
| **Total** | | **23/40** | **Acceptable** |

## Priority issues
- [P1] Word popup body is a raw dictionary dump (senses run together, IPA glued to POS, irrelevant first sense, "en-en" subtitle). Fix: headword + IPA + POS in header; 1-2 senses, one per line; drop dict id; idiom as a distinct block. /impeccable typeset, /impeccable distill
- [P1] Two dictionary worlds: compact popup → More → stock KOReader popup (9 actions, rounded, different labels) → near-empty Word details screen. Fix: More opens one Leaf sheet with all senses + same actions; retire Word details. /impeccable distill, /impeccable clarify
- [P1] Translation popup: 6 actions in 2 rows; Sentence|Paragraph looks like buttons (bold-only selection); EN and VI same style; Back semantics. Fix: header segmented switch with inverted selected state; VI visually distinct; drop Back. /impeccable layout
- [P2] Learning invisible outside the popup: no Home presence for saved words/review; English tools in Tools icon tab; review empty state dead end. /impeccable onboard
- [P2] Reader defaults: ~10px side margins at 600px, justified without hyphenation (rivers), footer has no page/chapter info. /impeccable typeset
- [P3] Home cover placeholders break mid-word ("KORead er Quicksta rt Guide"); AI settings jargon. /impeccable polish, /impeccable clarify
