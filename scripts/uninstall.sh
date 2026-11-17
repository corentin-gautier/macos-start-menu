#!/bin/bash
# Stops Start Menu and removes the app and its login agent.
# The signing certificate stays in the keychain (delete it in Keychain Access).
set -euo pipefail

LABEL="local.mac-start-menu"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x StartMenu 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/Start Menu.app"
tccutil reset Accessibility "$LABEL" >/dev/null 2>&1 || true
echo "Start Menu uninstalled."
