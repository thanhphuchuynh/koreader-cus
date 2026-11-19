"""Assemble a separate Kindle reader from the verified official ARM runtime."""
from pathlib import Path
import shutil, json, base64, re

root = Path(__file__).resolve().parent
program = root / 'staging/koreadercus'
mac = root.parent / 'macos'
profile = program / 'profile'
for directory in ('settings/simpleui', 'patches', 'plugins', 'data/dict'):
    (profile / directory).mkdir(parents=True, exist_ok=True)
for plugin in ('simpleui.koplugin', 'englishpreview.koplugin'):
    shutil.copytree(mac / 'test-data/plugins' / plugin, profile / 'plugins' / plugin,
                    dirs_exist_ok=True, ignore=shutil.ignore_patterns('.DS_Store', '__pycache__', '.git'))
shutil.copy2(mac / 'presets/omarchy-grayscale.lua', profile / 'settings/simpleui/sui_settings.lua')
for patch in ('2-dictionary-results.lua', '2-hide-crash-reports.lua', '2-leaf-branding.lua'):
    shutil.copy2(mac / 'test-data/patches' / patch, profile / 'patches')
for name in ('en-en', 'sample-english'):
    shutil.copytree(mac / 'test-data/data/dict' / name, profile / 'data/dict' / name,
                    dirs_exist_ok=True, ignore=shutil.ignore_patterns('*.oft', '.DS_Store'))
(profile / 'settings.reader.lua').write_text('''return {
    ["start_with"] = "homescreen_simpleui",
    ["home_dir"] = "/mnt/us/documents",
    ["document_metadata_folder"] = "dir",
    ["language"] = "en",
}
''')
(profile / 'settings/english-ai.lua').write_text('''-- Optional OpenAI-compatible service. Blank uses Google Translate for translation.
return { base_url = "", model = "" }
''')
# Enforce isolation in the owning modules, even when user patches are disabled.
docsettings = program / 'frontend/docsettings.lua'
source = docsettings.read_text()
original = 'local location = force_location or G_reader_settings:readSetting("document_metadata_folder", "doc")'
replacement = 'local location = "dir" -- KOReaderCus: never read, migrate, or purge the original reader sidecars.'
assert original in source or replacement in source
source = source.replace(original, replacement)
source = source.replace('doc_path .. ".kpdfview.lua",', '"", -- KOReaderCus: do not import legacy settings beside the book.')
docsettings.write_text(source)
ota = program / 'frontend/ui/otamanager.lua'
source = ota.read_text()
if '-- KOReaderCus: official OTA archives' not in source:
    source = source.replace('return OTAManager', '''-- KOReaderCus: official OTA archives target /mnt/us/koreader, so updates belong on the PC.
function OTAManager:getOTAType() return "none" end
function OTAManager:checkUpdate() return nil end
function OTAManager:fetchAndProcessUpdate()
    UIManager:show(InfoMessage:new{text = "Update Leaf from your computer."})
end
function OTAManager:getOTAMenuTable()
    return {text = "Leaf updates managed on PC", enabled = false}
end
return OTAManager''')
    ota.write_text(source)
(program / 'launch.sh').write_text('''#!/bin/sh
export KOREADER_DIR=/mnt/us/koreadercus
export KO_HOME=/mnt/us/koreadercus/profile
# Refuse an official update archive: its root folder belongs to the original reader.
if [ -f "$KOREADER_DIR/ota/update.tar.xz" ] || [ -f "$KO_HOME/ota/update.tar.xz" ]; then
    exit 1
fi
exec "$KOREADER_DIR/koreader.sh" --kual --asap
''')
(program / 'launch.sh').chmod(0o755)
(program / 'README-KOReaderCus.txt').write_text('''Leaf — powered by KOReader (separate custom installation)
Official Kindle hard-float build v2026.07.2-280-g400ba0e (2026-10-24), with local customizations.
Open KOReaderCus from the Kindle library script or KUAL. Run one reader at a time.
Your original /mnt/us/koreader remains installed.
All custom settings, caches, dictionaries, vocabulary and book progress live in:
/mnt/us/koreadercus/profile
Existing reader progress is not imported or shared. Books stay in /mnt/us/documents.
Automatic KOReader updates are disabled to protect the original installation.

Offline: tap a word for a compact dictionary; More opens the complete entry.
Hold and drag across multiple words; release to translate the exact selection automatically.
Single-word taps open the dictionary. Sentence help still offers explicit translation and analysis.
Translation always uses Google Translate first and requires Wi-Fi.
Use AI in the translation popup opens explicit AI translation, analysis and phrase help.
No AI request is sent automatically, including when Google fails.
If an AI request fails, Google translates the same text automatically.
Failed explanations return a clearly labelled Translation, not an AI analysis.
Fallback translations are saved under Google, and cancellation never starts fallback.
AI: edit profile/settings/english-ai.lua with base_url (HTTPS API prefix) and model.
Create profile/settings/english-ai.key containing only your provider API key.
Never send the key to anyone. Kindle USB storage is FAT32: keys are plaintext and
readable over USB; Unix file permissions do not protect them on this filesystem.
No personal API key is included. Live AI on this Kindle has not yet been tested.
Key saving supports user-approved plaintext storage on Kindle USB/FAT32; private permissions remain required elsewhere.

Rollback: exit KOReaderCus and launch your original reader.
To uninstall, remove only koreadercus/, documents/KOReaderCus.sh and extensions/koreadercus/.
Keep profile/ first if you want to retain new progress or vocabulary.

Learning vocabulary:
Tap Save word in the compact dictionary to keep its meaning, book and available
original sentence offline. Saved status survives reopening the reader.
Open the reader menu > Review 5 words. Reveal meaning, then choose Again or
Remembered. Earlier review dates come first; practice can include words not yet
due. Closing a card does not grade it. Reviews use KOReader's existing scheduler.
Native vocabulary and review progress remain in settings/vocabulary_builder.sqlite3;
English reading snapshots use an additional english_word_details table in that file.

English tools update:
- Word popup > Explain here: explicit AI explanation of the word in its sentence.
- Translation > Phrase help: explicit AI help with idioms and phrasal verbs.
- English tools > Translation history: open successful results offline.
  Cache identities include the passage, action, focused word, provider and model.
  The last 100 results are kept locally; up to 16 KB input and 64 KB output each.
  API keys and failed requests are never stored in this history.
  Clear saved translations in the history menu to delete the local cache.
- Review 5 words hides the saved word in its sentence before revealing it.
- English tools > Performance checks: run dictionary/popup timing, then measure
  the next page turn. Measurements run only when requested and are saved in
  profile/settings/english-performance.lua. They include software paint and
  refresh submission, not the physical E Ink settling time.
- A USB storage connection cannot execute these checks. Eject, open a book and
  run them on the Kindle. No Kindle timing is claimed until it has been run.

AI setup in the UI:
Settings > AI settings > Choose OpenRouter free model. Available from Home, Library and while reading.
Choose Gemma 4 26B A4B (default), Gemma 4 31B, or Automatic free model.
Enter your OpenRouter API key and Save. A blank key keeps the existing key for the same URL. The base URL and model remain editable
for other OpenAI-compatible providers. Choosing a preset does not save settings
or make a request. On the same base URL, a blank key keeps the existing key.
Changing provider with a blank key clears the previous provider's saved key.
Kindle USB storage cannot enforce Unix permissions. With your approval, the UI
can save a plaintext key under /mnt/us; it remains readable over USB. The UI
discloses this before saving. Private permissions are required elsewhere.
No key is bundled or copied by this update.

English speech - native Kindle compatibility test:
Word popup and sentence/translation popups offer Listen / Stop for the original
English text. Closing the popup, closing the book, or suspending stops speech.
English tools > Test English speech plays a fixed sample only when you tap Listen.
Pair Bluetooth headphones/speaker through Kindle Settings before testing.
This version uses the existing Kindle voice and current rate through KOReader's
bundled LIPC binding. It makes no network requests and needs no speech API key.
It does not install a voice pack, change pairing, or add the full audiobook plugin.
Native speech availability depends on Kindle firmware and installed voice support;
actual playback on this Kindle is not yet verified. Failure reports an error.
Speech is limited to 2 KB per passage and stops after at most 3 minutes.
Adjustable speech rate is not implemented in this initial native-service test.
''')
# Preserve launcher behavior and internal paths while applying Leaf branding.
branding = root.parent / 'branding'
for suffix in ('svg', 'png'):
    shutil.copyfile(branding / ('leaf.' + suffix), program / ('resources/koreader.' + suffix))
launcher = Path('/Volumes/Kindle/documents/koreader.sh').read_bytes()
assert launcher.count(b'# Name: KOReader ASAP') == 1
assert launcher.count(b'/mnt/us/koreader/koreader.sh --kual --asap') == 1
launcher = launcher.replace(b'# Name: KOReader ASAP', b'# Name: Leaf')
launcher = launcher.replace(b'/mnt/us/koreader/koreader.sh --kual --asap', b'/mnt/us/koreadercus/launch.sh')
launcher = re.sub(rb'^# Icon:.*$', b'# Icon: data:image/png;base64,' + base64.b64encode((branding / 'leaf-cover.png').read_bytes()), launcher, flags=re.M)
(root / 'staging/KOReaderCus.sh').write_bytes(launcher)
(root / 'staging/KOReaderCus.sh').chmod(0o755)
extension = root / 'staging/kual-koreadercus'
extension.mkdir(exist_ok=True)
(extension / 'config.xml').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<extension><information><name>Leaf</name><version>1.0</version><author>Local</author><id>koreadercus</id></information><menus><menu type="json" dynamic="true">menu.json</menu></menus></extension>
''')
(extension / 'menu.json').write_text(json.dumps({'items':[{'name':'Start Leaf', 'action':'/mnt/us/koreadercus/launch.sh'}]}, indent=2)+'\n')
print('Custom profile and launchers staged; no credentials copied.')
