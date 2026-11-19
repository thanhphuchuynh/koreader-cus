KOReader native Mac preview

Launch: double-click Launch KOReader.command.

Runtime: official Apple Silicon nightly v2026.07.2-280-g400ba0e_2026-10-24.
The app bundle signature and release archive SHA-256 were verified before launch.

This is not a complete native build of our fork. It uses the official native
runtime with the exact startSdcv method from fork commit 44da9a6 loaded as a
supported user patch in test-data/patches/2-dictionary-results.lua.
The nightly method was confirmed to match the fork baseline before overlaying.
The preview log confirms the overlay loaded and the sample EPUB opened.

All preview settings, caches and dictionary data are under test-data via KO_HOME.
The book and three-entry English-Vietnamese dictionary contain original sample
content. No real Kindle files or Calibre library are used by this launcher.

Long-press reluctantly, unfamiliar or threshold to try the sample dictionary.
Mac interaction and rendering do not simulate the Kindle display's latency.
The HTML reading/lookup redesign remains a prototype. The native Home screen
now uses SimpleUI 3.0.0 with an Omarchy-inspired grayscale preset.

Archive and overlay identities: preview-manifest.json.
Launch output: preview.log (development log; keep local).

SimpleUI / Omarchy-inspired native preview
-----------------------------------------
Open Launch SimpleUI.command to start on Home. Launch KOReader.command opens
the sample book directly. Both use the same isolated test-data directory.

SimpleUI 3.0.0 came from its official GitHub release. Archive SHA-256:
c5b1a622d2a4a8c68a1b959c8725cde4e29f8788e7297dcee82e11aa0661945a

Preset source: presets/omarchy-grayscale.lua. Applied through SimpleUI's own
settings/simpleui/sui_settings.lua store. It is a fresh-preview preset, not a
merge tool for an existing Kindle configuration. White surfaces, framed
full-width navigation, Geist Pixel tab labels, Inter UI, currently reading
and recent books only; quick settings and automatic update checks disabled.
Existing KOReader book typography and dictionary patch are preserved.
Style reference: https://vi.omarchy.org/ (pixel typography and crisp controls).

Compatibility repair: the installed plugin's sui_foldercovers.lua preserves
the second genItemTableFromPath return value on both cache hits and misses.
The nightly consumes this readability flag; dropping it caused a false folder
warning. Reusable diff: presets/simpleui-3.0.0-folder-cache.patch.
Check: luajit checks/folder-cache-contract.lua \
  test-data/plugins/simpleui.koplugin/features/library/sui_foldercovers.lua
The check failed before the repair and passed after it. Syntax check passed.
Native screenshot: simpleui-omarchy-preview.png; startup warning absent.

Rollback: quit KOReader, move test-data/plugins/simpleui.koplugin out of the
plugins directory and restore settings.reader.lua from backups/before-simpleui.
Keep logs and full test settings local; reusable preset contains no device IDs.
This is a Mac visual preview. Kindle installation and E Ink timing are untested.

Native English-learning UI mockup
--------------------------------
Open Launch English Preview.command. It opens the original sample EPUB and
automatically looks up reluctantly in the real native dictionary popup.
The native English learning preview plugin adds Word details and Sentence
help for the three sample words. Other dictionaries keep their native layout.
Tools > More tools > English learning preview also exposes the demo screens.

Word details shows fixed sample base word, formation, word family and source
sentence. Sentence help offers fixed Vietnamese translation and grammar
explanation in native TextViewer screens. No networking or audio is added.
Save word retains KOReader Vocabulary Builder's callback and storage. A lookup
launched automatically has no real word-selection context; use a normal word
selection when checking Vocabulary Builder's context capture.

This is a native UI prototype, not a general language-analysis implementation.
Content is limited to reluctantly, unfamiliar, and threshold. Nothing has been
installed on the Kindle. Native screenshots: english-native-lookup.png,
english-native-details.png, english-native-sentence.png.
Check: luajit checks/english-preview.lua \
  test-data/plugins/englishpreview.koplugin/main.lua
Checks cover sample scoping, preserving native save callbacks, detail content
and sentence-result callbacks. Native screens were visually checked; complete
end-to-end vocabulary saving and Kindle timing remain unverified.
Remove test-data/plugins/englishpreview.koplugin after quitting to roll back.

Alternative native study UX (current launcher default)
-----------------------------------------------------
Launch English Preview.command now starts the separate Study view. Sample
passage occupies the top pane; Meaning, Word family and Sentence tabs occupy
the lower pane. Closing/Return to book dismisses the view without modifying
book pagination or navigating the document. It does not float over the page.
This mockup uses fixed sample context rather than extracting live selections.
Sentence results remain samples with no networking. Save dispatches the native
Vocabulary Builder event with the sample word and current book title; context
capture from this mockup is not implemented. The existing popup remains usable
through normal lookup, or KINDLE_ENGLISH_PREVIEW=lookup with the launcher.
Checks cover full-screen ownership, tab context preservation, native save-event
arguments and closing the study view. Native layout was visually verified.
Screenshot: english-native-study.png.

Current choice: small native popup
---------------------------------
The user's preferred default is now the compact popup (launcher scene small),
not the Study view. It contains only word, IPA/part of speech, short English
and Vietnamese meanings, Save word and More. Close uses the title-bar X.
More opens word details; Sentence help is reachable there. The popup uses
native widgets at the bottom and was visually checked at roughly one quarter
of the display height. Sample content and native vocabulary event limitations
above still apply. Other alternative scenes remain available explicitly.
Screenshot: english-native-small-popup.png.

Default text-tap dictionary behavior
------------------------------------
The English preview plugin now intercepts ordinary text taps in the interior
of EPUB pages using ReaderHighlight's native selection/lookup path. Existing
highlight handling runs first. Outer 8% side margins, top 8%, bottom 6%, links
handled by native link zones, whitespace and PDF gestures retain native behavior.
The compact popup receives actual offline dictionary results; long entries use
a capped scrolling text area. More transfers the original results/selection to
the complete native dictionary popup. Closing the compact lookup clears the
selection and calls the dictionary close callback. Save uses native vocabulary
storage while the original selection is available for context capture.
The three demo words still have curated short summaries; other entries show
plain text converted from the installed dictionary. The included sample
dictionary has only three words; no-result handling remains native.

Launch English Preview.command now opens the book without a demo popup. This
behavior also applies when opening an EPUB through the ordinary local launcher.
KINDLE_ENGLISH_PREVIEW=lookup remains an opt-in integration preview.
Checks: checks/tap-dictionary.lua and checks/english-preview.lua pass. Real
StarDict lookup through the compact result path was visually verified. Native
mouse automation returned noWindowsAvailable, so a physical tap/click still
needs checking on the Mac, and Kindle installation/touch timing remain untested.
Screenshot: english-native-default-dictionary.png.

Missing-word fix and full English dictionary
-------------------------------------------
Fixed compact lookup fallback: no_result entries now use the same small popup
instead of falling back to the large native window. Missing results never use
sample definitions. Regression checks pass, including a missing known sample.

Installed English (WordNet + Wiktionary) from the KOReader download catalog:
https://github.com/DanielGregorini/koreader-dicts/releases/latest/download/en-en.zip
815,066 entries, plus inflected forms. Local directory: test-data/data/dict/en-en.
Archive SHA256: 142327769b0f4e2cd0e442a826bc6e561e5246a7796934ff23618c1c6984ab3c
CC BY-SA 4.0 and source notices retained in LICENSE and ATTRIBUTION alongside
the dictionary. This is English-English; Vietnamese definitions remain sample
content only. The archive is data; no downloaded scripts were executed.

Verified real offline lookup of noon now returns a definition in the compact
popup. Screenshot: english-native-noon-definition.png. Native tap behavior
is also supported by the user's screenshot of noon reaching dictionary lookup.
No Kindle installation or hardware timing test has been performed.

Optional AI translation and sentence explanation
------------------------------------------------
Implemented native settings for an OpenAI-compatible Chat Completions service.
Tools / More tools > English AI settings (also available inside Sentence help).
Enter the provider's HTTPS base URL including its API prefix (often /v1), model
name and API key. The plugin appends /chat/completions. Responses API-only,
Gemini-native, non-Bearer authentication, HTTP endpoints and streaming APIs are
not supported by this client.

Long-press and select text, then choose AI sentence help. Or tap a word > More >
Sentence help. The native EPUB sentence-extension API supplies surrounding
sentence text where available. Review the passage and destination, then choose
Translate to Vietnamese or Explain sentence. Only that passage is sent, not
book files, library records or vocabulary history. No request is automatic.
Requests run in a cancellable child process; dictionary lookup stays offline.
There is no response cache and no key/passage logging in the new client.

The masked key field always opens empty. Normal settings store only URL/model
in test-data/settings/english-ai.lua. The key is in english-ai.key alongside
that file, plaintext with owner-only 0600 permissions, written atomically and
without .old backups. Do not publish/copy the secret file in shared backups.
Changing the provider URL without entering a replacement key clears the old
key. Test profiles skip english-ai.key* when copying settings.
HTTPS requests enforce the bundled CA trust store and certificate SAN DNS
hostname matching; redirects are disabled so the key stays with the configured
endpoint. API URLs with credentials, query strings and fragments are rejected.

Client tests use mocked transport: request structure, certificate verification
settings and hostname mismatch, validation, response limits, bad JSON/response
shapes, auth/credit errors, empty responses. UI tests use a separate temporary
directory and a fake key to verify storage, mode 0600, explicit-send-only,
provider changes, missing configuration and cancellation. No real API key or
paid request was used; provider compatibility and live results remain untested.
Use the native settings form to enter your own details; never paste the key in
chat. AI settings screenshot: english-native-ai-settings.png.

Also corrected the custom long-definition scroll widget's missing dialog owner,
identified in the earlier performance report. That report is a historical
measurement before this AI change; no new performance improvement is claimed.

Translation without AI setup
----------------------------
When URL/model/key are incomplete, the Sentence help preview identifies Google
Translate and Translate calls KOReader's native showTranslation(text,false,
'en','vi'). No API key required. Explain sentence is disabled until AI is ready.
If AI settings change after a preview, a refreshed preview is shown before any
request; configured AI errors never silently switch to another provider.
Native selection action is now named Sentence help, since translation also
works without AI. Google uses the existing native translator/network handling.
The default native translation server is translate.googleapis.com.

Verified a real English-to-Vietnamese translation of the original sample
sentence in the native app with no AI configured. First network request failed;
a second returned HTTP 200 and displayed the translation. No cause for the
transient failure was established and no retry loop was added. Temporary
transport diagnostics were removed. Screenshot: english-native-google-translation.png.
Unit coverage includes no request on preview, Google fallback with explicit
language arguments, disabled analysis without AI, configured AI selection,
provider changes and no silent fallback after configured AI errors.

Compact sentence-help and translation UI
----------------------------------------
Word lookup, sentence preview, Google translation and AI output now share
english_popup.lua: a bottom popup with a capped text area, native scrolling,
close X, and one action row. Full-screen output is only opened through More.
Sentence preview keeps the destination in its subtitle and shows Translate /
Explain (disabled without AI). AI settings remain available in the tools menu.

Google fallback now calls the existing Translator:translate(text,'vi','en')
in the cancellable worker and displays its string in our compact popup; it no
longer uses the built-in full-screen showTranslation viewer. Native networking
modules are loaded before starting the forked worker. Loading them in the child
produced an empty-result failure in the Mac test; preloading in the parent
allowed the live translation to complete. No network retry loop was added.

Verified a live Google result in the compact native popup. Unit checks cover
compact preview/result routing for Google and AI, unchanged dictionary actions,
long-text height cap, scroll dialog ownership, and module loading before the
worker. Screenshot: english-native-compact-translation.png. Kindle timing and
live AI provider compatibility are still untested.

Compact loading state
---------------------
Google translation and configured AI requests now show the shared compact
popup with Translating… / Analysing sentence…, provider, Waiting for a response…,
and a Cancel button. The popup is painted before starting the native worker.
Cancel, Back and the X invoke Trapper's dismiss callback. Loading closes on
success, provider error, cancellation or missing worker output. Closing now
refreshes the affected region so stale loading pixels do not remain.

Native loading layout was visually verified with a temporary 12-second test
hold, removed afterward. Subsequent live Google checks returned missing worker
output (Request failed); the error cleanup and restored reading region were
visually verified. The intermittent native worker/request failure remains
unresolved and no network reliability improvement is claimed. AI result paths
use mocked tests because no provider is configured. Checks cover loading before
worker start, Cancel dispatch, all completion paths, idempotent close and redraw.
Screenshot: english-native-loading.png. Production code has no artificial delay
or animation loop; the static status suits E Ink refresh constraints.
