#!/bin/sh
# Runs at login (LaunchAgent com.signalclaw.restart-alert). After a restart,
# waits for the OpenClaw gateway's iMessage channel, then texts the owner once:
# when the Mac came back, the kernel's shutdown codes, whether the gateway is
# up and whether the check job is loaded. A login without a restart sends
# nothing.
#
# Settings: SIGNALCLAW_CHECK_LABEL (default com.signalclaw.check)
export PATH="$HOME/.openclaw/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export NODE_OPTIONS=--no-deprecation
STATE_DIR="$HOME/Library/Application Support/signalclaw"
STATE="$STATE_DIR/last-boot-alerted"
NOTIFY="$(cd "$(dirname "$0")" && pwd)/notify.sh"
CHECK_LABEL="${SIGNALCLAW_CHECK_LABEL:-com.signalclaw.check}"
U="$(id -u)"
stamp() { date '+%Y-%m-%d %H:%M:%S %Z'; }
mkdir -p "$STATE_DIR"

boot="$(sysctl -n kern.boottime | sed -E 's/^\{ sec = ([0-9]+),.*/\1/')"
if [ "$(cat "$STATE" 2>/dev/null)" = "$boot" ]; then
  echo "$(stamp) login without a restart (boot $boot already reported); nothing sent"
  exit 0
fi
echo "$(stamp) restart detected (boot $boot); waiting for the gateway"

# Wait up to 10 minutes for iMessage to show connected.
up=0
i=0
while [ $i -lt 40 ]; do
  if openclaw channels status 2>/dev/null | grep -i "imessage" | grep -qi "connected"; then up=1; break; fi
  sleep 15; i=$((i + 1))
done

host="$(scutil --get ComputerName 2>/dev/null || hostname -s)"
boot_at="$(date -r "$boot" '+%l:%M %p %a %b %e' | tr -s ' ' | sed 's/^ //')"
# macOS's shutdown-cause log needs admin to read; the kernel's raw reset codes don't.
cause="$(sysctl -n kern.shutdownreason 2>/dev/null | tr -s ' ' | sed 's/^ //;s/ $//')"
[ -n "$cause" ] && cause="kernel reset codes: $cause" || cause="not recorded"
if launchctl print "gui/$U/$CHECK_LABEL" >/dev/null 2>&1; then
  check="Check job loaded."
else
  check="WARNING: check job ($CHECK_LABEL) is not loaded."
fi
if [ "$up" = 1 ]; then gw="Gateway up."; else gw="Gateway iMessage not connected after 10 min."; fi

msg="${host} restarted at ${boot_at}. Last shutdown: ${cause}. ${gw} ${check}"
echo "$(stamp) $msg"
if "$NOTIFY" "$msg"; then
  echo "$boot" >"$STATE"
else
  echo "$(stamp) alert not sent (see alerts.log); will try again at next login"
fi
