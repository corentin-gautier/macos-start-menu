#!/bin/bash
# Builds "build/Start Menu.app".
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Start Menu.app"
IDENTITY="Mac Start Menu Local Signing"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/StartMenu"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/StartMenu"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "warning: no \"$IDENTITY\" certificate (run scripts/setup-signing.sh)," \
         "signing ad hoc: the Accessibility permission will be asked again after each build." >&2
    codesign --force --sign - "$APP"
fi

echo "Built $APP"
