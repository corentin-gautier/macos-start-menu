#!/bin/bash
# Builds the app and zips it to build/Start-Menu.zip for a GitHub release.
# With a Developer ID signature, the app is notarized and stapled first
# (credentials: xcrun notarytool store-credentials "$NOTARY_PROFILE").
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/Start Menu.app"
ZIP=build/Start-Menu.zip
NOTARY_PROFILE="${NOTARY_PROFILE:-notary}"

scripts/build.sh
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

SIGNATURE=$(codesign -dvv "$APP" 2>&1)
if [[ "$SIGNATURE" == *"Authority=Developer ID Application"* ]]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    spctl -a -vv "$APP"
else
    echo "warning: not signed with a Developer ID, the zip is not notarized." >&2
fi
echo "Packaged $ZIP"
