#!/bin/sh
# Builds build/LeafSend.app (release) with Command Line Tools only. Open it with: open build/LeafSend.app
set -eu
cd "$(dirname "$0")"
swift build -c release --product LeafSend
APP=build/LeafSend.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/LeafSend" "$APP/Contents/MacOS/LeafSend"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Leaf Send</string>
<key>CFBundleIdentifier</key><string>local.leaf.send</string>
<key>CFBundleExecutable</key><string>LeafSend</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Leaf Send looks for your Kindle on the local network.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" 2>/dev/null || true
echo "$APP"
