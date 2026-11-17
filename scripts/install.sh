#!/bin/bash
# Builds, installs to ~/Applications and launches. The app adds itself to the
# Login Items on its first launch (System Settings › General › Login Items).
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="$HOME/Applications/Start Menu.app"
OLD_AGENT="$HOME/Library/LaunchAgents/local.mac-start-menu.plist"

scripts/build.sh

pkill -x StartMenu 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "build/Start Menu.app" "$DEST"

# Earlier versions started at login through a LaunchAgent.
if [ -f "$OLD_AGENT" ]; then
    launchctl bootout "gui/$(id -u)/local.mac-start-menu" 2>/dev/null || true
    rm -f "$OLD_AGENT"
fi

open "$DEST"
echo "Installed $DEST"
