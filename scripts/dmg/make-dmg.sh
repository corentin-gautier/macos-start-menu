#!/bin/bash
# Makes a drag-to-Applications disk image: make-dmg.sh <app> <output.dmg>
# The Finder lays the window out (needs Automation access to the Finder).
set -euo pipefail
APP="$1"
DMG="$2"
VOLUME="Start Menu"
BACKGROUND="$(dirname "$0")/background.tiff"
WORK=$(mktemp -d)
trap 'hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true
hdiutil create -quiet -size 200m -fs HFS+ -volname "$VOLUME" -ov "$WORK/rw.dmg"
hdiutil attach -quiet -nobrowse -noautoopen "$WORK/rw.dmg"
MOUNT="/Volumes/$VOLUME"
cp -R "$APP" "$MOUNT/"
ln -s /Applications "$MOUNT/Applications"
mkdir "$MOUNT/.background"
cp "$BACKGROUND" "$MOUNT/.background/background.tiff"
APP_NAME=$(basename "$APP")

# Window 540×360 (the background's size), icons centered on the arrow's ends.
osascript <<OSA
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 740, 480}
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        set label position of opts to bottom
        set background picture of opts to file ".background:background.tiff"
        set extension hidden of item "$APP_NAME" to true
        set position of item "$APP_NAME" to {140, 170}
        set position of item "Applications" to {400, 170}
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA

chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync
hdiutil detach -quiet "$MOUNT"
rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format ULFO -o "$DMG"
