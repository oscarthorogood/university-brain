#!/bin/sh
# Wraps the SwiftPM build in a minimal .app so macOS treats it as a real app.
set -e
cd "$(dirname "$0")"
# The version the updater compares: $VERSION (the release workflow passes the tag), else the latest git tag, else 0.0.0.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
swift build -c release
APP=build/SecondBrain.app
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SecondBrain "$APP/Contents/MacOS/SecondBrain"
mkdir -p "$APP/Contents/Resources"
# Templates and Agents: the app copies them into the vault the first time each new version runs (AppFiles.swift)
rm -rf "$APP/Contents/Resources/University Brain App"
if [ -d "University Brain App" ]; then
  ditto "University Brain App" "$APP/Contents/Resources/University Brain App"
else
  echo "warning: no 'University Brain App' folder here, so this build installs no Templates or Agents" >&2
fi
# Liquid Glass icon: Icon/SecondBrain.icon (layers drawn by Icon/icon.swift) compiled by Xcode's actool
rm -rf build/icon && mkdir -p build/icon
xcrun actool Icon/SecondBrain.icon --compile build/icon --platform macosx --minimum-deployment-target 26.0 --app-icon SecondBrain --output-partial-info-plist build/icon/partial.plist >/dev/null
cp build/icon/Assets.car build/icon/SecondBrain.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.oscarthorogood.secondbrain</string>
<key>CFBundleIconFile</key><string>SecondBrain</string>
<key>CFBundleIconName</key><string>SecondBrain</string>
<key>CFBundleName</key><string>University Brain</string>
<key>CFBundleDisplayName</key><string>University Brain</string>
<key>CFBundleExecutable</key><string>SecondBrain</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSRemindersFullAccessUsageDescription</key><string>University Brain keeps your tasks and a Reminders list in step, both ways, and adds reminders you create to Unsorted.</string>
<key>NSRemindersUsageDescription</key><string>University Brain keeps your tasks and a Reminders list in step, both ways, and adds reminders you create to Unsorted.</string>
<key>NSMicrophoneUsageDescription</key><string>University Brain records voice memos into your Unsorted folder.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>University Brain turns your voice memos into text on this Mac.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
