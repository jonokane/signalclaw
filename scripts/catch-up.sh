#!/bin/sh
# Runs at login (LaunchAgent com.signalclaw.catch-up, see install.sh).
#
# launchd skips a daily run that comes due while your macOS user is logged
# out or the Mac is off; it does not run it late. This script fills that gap:
# if today's scheduled time has passed and the status file shows no run that
# started today, it starts the check job now and texts you once.
#
# A run that happened today and failed is not re-run (it already texted you).
# The run is the normal check job (launchctl kickstart), so its time limit,
# status file and failure text all apply unchanged. No model call; nothing on
# success.
#
# Settings (environment variables; install.sh sets the first two):
#   SIGNALCLAW_AT           the check's daily time, HH:MM (default 05:30)
#   SIGNALCLAW_JOB_NAME     name used in the text ("job checker")
#   SIGNALCLAW_STATUS_FILE  default ~/.openclaw/workspace/checker-status.json
#   SIGNALCLAW_CHECK_LABEL  default com.signalclaw.check
#   CATCHUP_NOW="YYYY-MM-DD HH:MM"  pretend it is this time (testing)
#   CATCHUP_DRY_RUN=1       say what it would do; don't start the job or text
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
HERE="$(cd "$(dirname "$0")" && pwd)"
AT="${SIGNALCLAW_AT:-05:30}"
NAME="${SIGNALCLAW_JOB_NAME:-job checker}"
STATUS_FILE="${SIGNALCLAW_STATUS_FILE:-$HOME/.openclaw/workspace/checker-status.json}"
JOB="gui/$(id -u)/${SIGNALCLAW_CHECK_LABEL:-com.signalclaw.check}"
stamp() { date '+%Y-%m-%d %H:%M:%S %Z'; }
say() { echo "$(stamp) catch-up: $*"; }

now="${CATCHUP_NOW:-$(date '+%Y-%m-%d %H:%M')}"
today="${now% *}"
hhmm="${now#* }"
# "06:05" -> 605, with no octal surprises from leading zeros.
mins() { echo $(( (1${1%:*} - 100) * 60 + 1${1#*:} - 100 )); }
if [ "$(mins "$hhmm")" -lt "$(mins "$AT")" ]; then
  say "before today's $AT run; the schedule will handle it"
  exit 0
fi

# The date part of startedAt, e.g. "2026-11-14" from "2026-11-14T05:30:05-08:00".
last="$(/usr/bin/python3 -c 'import json,sys
try: print(str(json.load(open(sys.argv[1])).get("startedAt") or "")[:10])
except Exception: print("")' "$STATUS_FILE")"
if [ "$last" = "$today" ]; then
  say "today's run already happened (started $last); nothing to do"
  exit 0
fi
if launchctl print "$JOB" 2>/dev/null | grep -q 'state = running'; then
  say "the check is running right now; nothing to do"
  exit 0
fi
say "missed today's $AT run (last run started ${last:-never}); starting it now"

if [ -n "${CATCHUP_DRY_RUN:-}" ]; then
  say "dry run: would kickstart $JOB and send a text"
  exit 0
fi

# At login this job and the check job load at about the same time; give the
# check job up to 2 minutes to appear.
started=0
i=0
while [ $i -lt 24 ]; do
  if launchctl kickstart "$JOB" 2>/dev/null; then started=1; break; fi
  sleep 5; i=$((i + 1))
done

when="$(date '+%l:%M %p %a %b %e' | tr -s ' ' | sed 's/^ //')"
if [ "$started" = 1 ]; then
  msg="Missed the $AT $NAME run (this Mac user wasn't logged in, or the Mac was off). Started it at ${when}. You'll get a text only if it fails."
else
  msg="Missed the $AT $NAME run, and couldn't start it at ${when}: the check job isn't loaded."
fi
say "$msg"

# The text goes through the OpenClaw gateway, which also starts at login.
# Wait up to 3 minutes for its iMessage channel (notify.sh retries once too).
export PATH="$HOME/.openclaw/bin:$PATH" NODE_OPTIONS=--no-deprecation
i=0
while [ $i -lt 12 ]; do
  openclaw channels status 2>/dev/null | grep -i imessage | grep -qi connected && break
  sleep 15; i=$((i + 1))
done
"$HERE/notify.sh" "$msg" || say "text not sent (see the alerts log)"
