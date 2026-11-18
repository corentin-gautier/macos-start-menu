#!/bin/bash
# Stops Start Menu and removes the app, its login item and its permission.
# The signing certificate stays in the keychain (delete it in Keychain Access).
set -euo pipefail

APP="/Applications/Start Menu.app"
pkill -x StartMenu 2>/dev/null || true
[ -d "$APP" ] && "$APP/Contents/MacOS/StartMenu" --unregister-login-item || true
launchctl bootout "gui/$(id -u)/local.mac-start-menu" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.mac-start-menu.plist"
rm -rf "$APP"
tccutil reset Accessibility local.mac-start-menu >/dev/null 2>&1 || true
echo "Start Menu uninstalled."
