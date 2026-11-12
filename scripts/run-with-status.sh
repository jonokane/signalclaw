#!/bin/sh
# Run a scheduled job, then tell a sandboxed OpenClaw agent how it went.
#
#   run-with-status.sh [command args...]
#
# Meant to be started by launchd (see install.sh), but works by hand too.
#
# Every run, success or failure, ends by overwriting a status file in the
# agent's workspace (write_status.py), the one folder the OpenClaw sandbox
# can see. If this script is killed or stops early, the EXIT trap still writes
# a "failed" status. A missed run (Mac off) writes nothing, so a stale date in
# the file is the signal.
#
# On failure or timeout it also sends one text through notify.sh. Nothing on
# success.
#
# Settings (environment variables, all optional):
#   SIGNALCLAW_JOB_NAME     name used in the status file and alerts ("job checker")
#   SIGNALCLAW_STATUS_FILE  default ~/.openclaw/workspace/checker-status.json
#   SIGNALCLAW_RESULTS      a signalcheck results file to summarize (counts, GONE rows)
#   SIGNALCLAW_TIMEOUT      seconds before the job is stopped (default 1800)
#   SIGNALCLAW_LOG          log path quoted in alerts (default ~/Library/Logs/signalclaw/check.log)
#   SIGNALCLAW_NO_ALERTS=1  never send a text
#   NOTIFY_DRY_RUN=1        passed to notify.sh: preview the text, don't send
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export LANG="${LANG:-en_US.UTF-8}"
export PYTHONUNBUFFERED=1

HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="${SIGNALCLAW_JOB_NAME:-job checker}"
LIMIT="${SIGNALCLAW_TIMEOUT:-1800}"
LOG_HINT="${SIGNALCLAW_LOG:-~/Library/Logs/signalclaw/check.log}"
export SIGNALCLAW_JOB_NAME="$NAME"
export SIGNALCLAW_STATUS_FILE="${SIGNALCLAW_STATUS_FILE:-$HOME/.openclaw/workspace/checker-status.json}"
iso_now() { date '+%Y-%m-%dT%H:%M:%S%z' | sed 's/\(..\)$/:\1/'; }   # ISO-8601, offset with colon
when() { date '+%l:%M %p %a %b %e' | tr -s ' ' | sed 's/^ //'; }
START="$(iso_now)"

status_done=0
pid=""
write_status() {   # write_status RC "error text"
  status_done=1
  /usr/bin/python3 "$HERE/write_status.py" --start "$START" --rc "$1" --error "$2" && return 0
  # Last resort if Python itself is broken: a fixed-text failed status.
  printf '{\n  "startedAt": "%s",\n  "finishedAt": "%s",\n  "status": "failed",\n  "exitCode": %s,\n  "error": "the status writer failed; see the log"\n}\n' \
      "$START" "$(iso_now)" "$1" >"$SIGNALCLAW_STATUS_FILE.tmp" &&
    mv -f "$SIGNALCLAW_STATUS_FILE.tmp" "$SIGNALCLAW_STATUS_FILE"
}
on_exit() {
  rc=$1
  [ -n "$pid" ] && kill -TERM -- "-$pid" 2>/dev/null
  [ "$status_done" = 1 ] && return
  [ "$rc" = 0 ] && rc=1
  write_status "$rc" "the run script stopped before finishing (exit $rc)"
}
trap 'on_exit $?' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

[ $# -gt 0 ] || { echo "usage: run-with-status.sh command [args...]" >&2; exit 2; }
OUT="$(mktemp -t signalclaw-run)" || exit 1

echo "=== $(date '+%Y-%m-%d %H:%M:%S %Z') start: $NAME: $* (limit ${LIMIT}s)"
set -m   # own process group, so a timeout also stops any browser the job started
"$@" >"$OUT" 2>&1 &
pid=$!
started=$(date +%s)
timed_out=0
while kill -0 "$pid" 2>/dev/null; do
  if [ $(( $(date +%s) - started )) -ge "$LIMIT" ]; then
    timed_out=1
    kill -TERM -- "-$pid" 2>/dev/null
    sleep 10
    kill -KILL -- "-$pid" 2>/dev/null
    break
  fi
  sleep 2
done
wait "$pid"
rc=$?
pid=""   # finished; nothing left for the EXIT trap to stop
cat "$OUT"
last_line="$(grep -v '^[[:space:]]*$' "$OUT" | tail -1)"

reason=""
if [ "$timed_out" = 1 ]; then
  rc=124
  reason="ran longer than $(( LIMIT / 60 )) minutes and was stopped"
  [ "$LIMIT" -lt 60 ] && reason="ran longer than ${LIMIT} seconds and was stopped"
elif [ "$rc" -ne 0 ]; then
  reason="$(grep '^FAILED: ' "$OUT" | tail -1 | sed 's/^FAILED: //')"
  [ -n "$reason" ] || reason="$last_line"
  [ -n "$reason" ] || reason="exited with code $rc and no output"
fi
rm -f "$OUT"

if [ -n "$reason" ]; then
  reason="$(printf '%s' "$reason" | tr -d '\r' | cut -c1-200)"
  write_status "$rc" "$reason"
  echo "=== alert: $reason"
  [ -n "${SIGNALCLAW_NO_ALERTS:-}" ] || "$HERE/notify.sh" "The $NAME failed at $(when): ${reason}. Log: $LOG_HINT"
else
  # Exit 0. write_status.py still marks it failed if SIGNALCLAW_RESULTS is set
  # and no fresh results exist, quoting the last line of output.
  write_status 0 "$last_line"
fi
echo "=== $(date '+%Y-%m-%d %H:%M:%S %Z') end: exit $rc"
exit $rc
