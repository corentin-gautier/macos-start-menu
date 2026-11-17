#!/bin/bash
# Builds, installs to ~/Applications, starts at login (LaunchAgent) and launches.
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL="local.mac-start-menu"
DEST="$HOME/Applications/Start Menu.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

scripts/build.sh

pkill -x StartMenu 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$DEST"
cp -R "build/Start Menu.app" "$DEST"

cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-g</string>
        <string>$DEST</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT"

echo "Installed $DEST (starts at login)."
