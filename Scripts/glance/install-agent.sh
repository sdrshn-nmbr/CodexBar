#!/usr/bin/env bash
# Installs the glance sync LaunchAgent and runs the first sync. Re-run to update the agent definition.
set -euo pipefail

GLANCE_HOME="$HOME/Library/Application Support/CodexBarGlance"
LABEL="com.sdrshn.codexbar-glance-sync"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$GLANCE_HOME/bin" "$HOME/Library/LaunchAgents"
cp "$HERE/sync.sh" "$GLANCE_HOME/bin/sync.sh"
chmod +x "$GLANCE_HOME/bin/sync.sh"

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$GLANCE_HOME/bin/sync.sh</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>GLANCE_LAUNCH</key><string>0</string>
    </dict>
    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>15</integer><key>Minute</key><integer>30</integer></dict>
        <dict><key>Hour</key><integer>21</integer><key>Minute</key><integer>30</integer></dict>
    </array>
    <key>Nice</key><integer>5</integer>
    <key>ProcessType</key><string>Adaptive</string>
    <key>StandardOutPath</key><string>$GLANCE_HOME/sync.log</string>
    <key>StandardErrorPath</key><string>$GLANCE_HOME/sync.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed $LABEL. Run now with: launchctl kickstart gui/$(id -u)/$LABEL"

