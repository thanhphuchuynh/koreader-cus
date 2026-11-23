# Leaf Send — Mac app that sends books and tests to the Kindle over Wi-Fi — design

Approved in conversation on 2026-11-23 (approach A).

## Intent
Copying over USB is slow, needs a careful eject, and once left the Kindle's FAT disk damaged. The user
wants to drag a book or a Leaf test onto a Mac window and have it land in the right Kindle folder over
Wi-Fi, with the Kindle found automatically.

## Approaches considered
- **A (picked): Mac app + KOReader's built-in SSH server.** No new Kindle code; SFTP with an SSH key.
  Cost: SSH must be running on the Kindle (KOReader has a start-at-launch option), discovery is a scan.
- B: a new Leaf upload server on the Kindle that announces itself. Instant discovery, but new server code,
  battery, and our own security. Rejected for now.
- C: Calibre wireless. Nothing to build, but Calibre picks folders, so tests cannot be routed. Rejected.

## Behaviour
- One window: Kindle status line, a drop area, a log of what went where.
- **Discovery:** try the last Kindle address first; otherwise scan the Mac's Wi-Fi subnet for TCP port
  2222 answering `SSH-2.0-dropbear`, then confirm with an SSH command that `/mnt/us/koreadercus` exists.
- **Routing** (by the file, not its name):
  - EPUB with `META-INF/leaf-ielts.json`: TOEIC → `documents/TOEIC/Part N`; IELTS listening →
    `documents/IELTS/Listening`; IELTS reading → `documents/IELTS`.
    A listening test also sends its audio file (`audio.file`) from beside the EPUB; missing audio is an error.
  - Any other book (`epub pdf mobi azw azw3 fb2 txt cbz djvu`) → `documents/From Mac`.
  - Anything else is refused with a reason.
- **Transfer:** macOS `sftp` in batch mode as `root`, port 2222, with the app's own key; folders made as needed.
- **One-time key setup:** the app makes an ed25519 key in `~/Library/Application Support/LeafSend/`.
  With the Kindle plugged in by USB, a button copies the public key to `koreadercus/settings/SSH/authorized_keys`
  (the path KOReader's patched dropbear reads). After that, Wi-Fi only.

## Non-goals
Sync, deleting from the Kindle, a Kindle-side plugin, App Store packaging or signing.

## Build
Swift package `mac/LeafSend` (SwiftUI, Command Line Tools only, no Xcode project). `make-app.sh` wraps
the binary into `LeafSend.app`. A check executable asserts the routing and subnet logic.

## Calls made by Claude (correctable)
- Plain books go to `documents/From Mac`.
- Login as `root` with key only; no password option is used or suggested.
