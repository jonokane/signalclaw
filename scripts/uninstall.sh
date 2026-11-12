#!/bin/sh
# Remove signalclaw's LaunchAgents for the current user. Leaves logs, the
# status file and OpenClaw itself alone.
U="$(id -u)"
for l in com.signalclaw.check com.signalclaw.restart-alert com.signalclaw.lock-at-login; do
  f="$HOME/Library/LaunchAgents/$l.plist"
  [ -f "$f" ] || continue
  launchctl bootout "gui/$U/$l" 2>/dev/null || true
  rm -f "$f"
  echo "removed $l"
done
