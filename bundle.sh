#!/bin/sh
# Wraps the SwiftPM build in a minimal .app so macOS treats it as a real app.
set -e
swift build -c release
APP=build/SecondBrain.app
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SecondBrain "$APP/Contents/MacOS/SecondBrain"
mkdir -p "$APP/Contents/Resources"
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
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>University Brain records voice memos into your Unsorted folder.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>University Brain turns your voice memos into text on this Mac.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
