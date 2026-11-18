#!/bin/bash
# Builds the app and packages it for a GitHub release: build/Start-Menu.dmg
# (drag to Applications) and build/Start-Menu.zip (Homebrew cask).
# With a Developer ID signature, the app and the DMG are notarized and stapled
# (credentials: xcrun notarytool store-credentials "$NOTARY_PROFILE").
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/Start Menu.app"
ZIP=build/Start-Menu.zip
DMG=build/Start-Menu.dmg
NOTARY_PROFILE="${NOTARY_PROFILE:-notary}"

scripts/build.sh
rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

SIGNATURE=$(codesign -dvv "$APP" 2>&1)
NOTARIZE=false
[[ "$SIGNATURE" == *"Authority=Developer ID Application"* ]] && NOTARIZE=true

if $NOTARIZE; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    spctl -a -vv "$APP"
else
    echo "warning: not signed with a Developer ID, nothing is notarized." >&2
fi

scripts/dmg/make-dmg.sh "$APP" "$DMG"

if $NOTARIZE; then
    codesign --sign "$(sed -nE 's/^Authority=(Developer ID Application: .*)$/\1/p' <<<"$SIGNATURE")" --timestamp "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl -a -vv -t open --context context:primary-signature "$DMG"
fi
echo "Packaged $DMG and $ZIP"
