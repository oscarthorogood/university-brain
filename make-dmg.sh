#!/bin/sh
# Packs build/SecondBrain.app into a drag-to-Applications disk image, build/UniversityBrain-<version>.dmg,
# and writes its SHA-256 beside it (the in-app updater checks the download against it).
set -e
cd "$(dirname "$0")"
APP=build/SecondBrain.app
[ -d "$APP" ] || ./bundle.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGE=build/dmg
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "$APP" "$STAGE/University Brain.app"
ln -s /Applications "$STAGE/Applications"
DMG="build/UniversityBrain-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "University Brain" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
shasum -a 256 "$DMG" | awk '{print $1}' > "$DMG.sha256"
echo "$DMG"
