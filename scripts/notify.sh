#!/bin/sh
# Send one status text to the agent's owner through OpenClaw's own send command.
# Not an agent turn: no model call, no tokens.
#
#   notify.sh "message text"
#
# The recipient is read at send time from OpenClaw's config
# (channels.imessage.allowFrom[0], the one sender the agent accepts). It is
# never stored in a file or written to a log.
#
# NOTIFY_DRY_RUN=1 runs OpenClaw's --dry-run instead of sending.
# Log: ~/Library/Logs/signalclaw/alerts.log
export PATH="$HOME/.openclaw/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export NODE_OPTIONS=--no-deprecation
LOG="$HOME/Library/Logs/signalclaw/alerts.log"
mkdir -p "$(dirname "$LOG")"
stamp() { date '+%Y-%m-%d %H:%M:%S %Z'; }

msg="$1"
[ -n "$msg" ] || { echo "$(stamp) notify: empty message" >>"$LOG"; exit 2; }

to="$(openclaw config get channels.imessage.allowFrom 2>/dev/null |
      /usr/bin/python3 -c 'import json,sys
try: v = json.load(sys.stdin)
except ValueError: v = []
print(v[0] if isinstance(v, list) and v else "")')"
if [ -z "$to" ]; then
  echo "$(stamp) notify: no recipient in channels.imessage.allowFrom; not sent: $msg" >>"$LOG"
  exit 3
fi

dry=""
[ -n "${NOTIFY_DRY_RUN:-}" ] && dry="--dry-run"
for attempt in 1 2; do
  if out="$(openclaw message send --channel imessage --target "$to" --message "$msg" $dry 2>&1)"; then
    echo "$(stamp) sent${dry:+ (dry run)}: $msg" >>"$LOG"
    exit 0
  fi
  echo "$(stamp) send attempt $attempt failed: $(printf '%s' "$out" | tail -1 | cut -c1-200)" >>"$LOG"
  [ "$attempt" = 1 ] && sleep 30
done
echo "$(stamp) NOT SENT: $msg" >>"$LOG"
exit 1
