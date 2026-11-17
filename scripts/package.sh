#!/bin/bash
# Builds the app and zips it to build/Start-Menu.zip for a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh
rm -f build/Start-Menu.zip
ditto -c -k --keepParent "build/Start Menu.app" build/Start-Menu.zip
echo "Packaged build/Start-Menu.zip"
