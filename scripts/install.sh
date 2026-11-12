#!/bin/sh
# Install signalclaw's LaunchAgents for the current macOS user. No admin needed.
#
#   install.sh --check "COMMAND" [--at HH:MM] [--results PATH] [--workdir DIR]
#              [--name TEXT] [--restart-alert] [--lock-at-login] [--print]
#
#   --check "COMMAND"  the job to run daily, e.g. signalcheck's run command
#   --at HH:MM         daily start time, local (default 05:30)
#   --results PATH     a signalcheck results file to summarize in the status file
#   --workdir DIR      folder the job starts in (default: your home folder)
#   --name TEXT        name for the status file and alerts (default "job checker")
#   --restart-alert    also install the after-restart text
#   --lock-at-login    also install the lock-after-automatic-login safeguard
#   --print            print the plists instead of installing them
#
# Labels: com.signalclaw.check, com.signalclaw.restart-alert,
# com.signalclaw.lock-at-login. Logs: ~/Library/Logs/signalclaw/.
# Remove with uninstall.sh.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
AGENTS="$HOME/Library/LaunchAgents"
LOGS="$HOME/Library/Logs/signalclaw"
check="" at="05:30" results="" workdir="$HOME" name="job checker" restart=0 lock=0 print=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) check="$2"; shift 2 ;;
    --at) at="$2"; shift 2 ;;
    --results) results="$2"; shift 2 ;;
    --workdir) workdir="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --restart-alert) restart=1; shift ;;
    --lock-at-login) lock=1; shift ;;
    --print) print=1; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done
[ -n "$check" ] || { echo "--check \"COMMAND\" is required (try --help)" >&2; exit 2; }
case "$at" in [0-2][0-9]:[0-5][0-9]) ;; *) echo "--at must be HH:MM" >&2; exit 2 ;; esac
hour=$(( 1${at%:*} - 100 )); minute=$(( 1${at#*:} - 100 ))
[ "$hour" -le 23 ] || { echo "--at hour must be 00-23" >&2; exit 2; }

xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

head_plist() {   # head_plist LABEL COMMENT
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$1</string>
	<key>Comment</key>
	<string>$(xml "$2")</string>
	<key>ProcessType</key>
	<string>Background</string>
	<key>StandardInPath</key>
	<string>/dev/null</string>
EOF
}

check_plist() {
  head_plist com.signalclaw.check "signalclaw: run the $name daily at $at, then write the agent's status file."
  cat <<EOF
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>$(xml "$HERE/run-with-status.sh")</string>
		<string>/bin/sh</string>
		<string>-c</string>
		<string>$(xml "$check")</string>
	</array>
	<key>EnvironmentVariables</key>
	<dict>
		<key>SIGNALCLAW_JOB_NAME</key>
		<string>$(xml "$name")</string>
		<key>SIGNALCLAW_LOG</key>
		<string>$(xml "$LOGS/check.log")</string>
EOF
  if [ -n "$results" ]; then
    printf '\t\t<key>SIGNALCLAW_RESULTS</key>\n\t\t<string>%s</string>\n' "$(xml "$results")"
  fi
  cat <<EOF
	</dict>
	<key>WorkingDirectory</key>
	<string>$(xml "$workdir")</string>
	<key>StartCalendarInterval</key>
	<dict>
		<key>Hour</key>
		<integer>$hour</integer>
		<key>Minute</key>
		<integer>$minute</integer>
	</dict>
	<key>RunAtLoad</key>
	<false/>
	<key>StandardOutPath</key>
	<string>$(xml "$LOGS/check.log")</string>
	<key>StandardErrorPath</key>
	<string>$(xml "$LOGS/check.log")</string>
</dict>
</plist>
EOF
}

login_plist() {   # login_plist LABEL SCRIPT COMMENT LOGNAME
  head_plist "$1" "$3"
  cat <<EOF
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>$(xml "$HERE/$2")</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>StandardOutPath</key>
	<string>$(xml "$LOGS/$4")</string>
	<key>StandardErrorPath</key>
	<string>$(xml "$LOGS/$4")</string>
</dict>
</plist>
EOF
}

render() {   # render LABEL
  case "$1" in
    com.signalclaw.check) check_plist ;;
    com.signalclaw.restart-alert) login_plist "$1" restart-alert.sh "signalclaw: after a restart, wait for the OpenClaw gateway, then text a status line (no model call)." restart-alert.log ;;
    com.signalclaw.lock-at-login) login_plist "$1" lock-at-login.sh "signalclaw: about 60 s after automatic login, sleep the display so the session locks." lock-at-login.log ;;
  esac
}

labels="com.signalclaw.check"
[ "$restart" = 1 ] && labels="$labels com.signalclaw.restart-alert"
[ "$lock" = 1 ] && labels="$labels com.signalclaw.lock-at-login"

if [ "$print" = 1 ]; then
  for l in $labels; do echo "----- $AGENTS/$l.plist"; render "$l"; done
  exit 0
fi

mkdir -p "$AGENTS" "$LOGS"
U="$(id -u)"
for l in $labels; do
  f="$AGENTS/$l.plist"
  render "$l" >"$f.tmp"
  plutil -lint -s "$f.tmp"
  mv -f "$f.tmp" "$f"
  launchctl bootout "gui/$U/$l" 2>/dev/null || true
  # Login jobs (RunAtLoad) start once now; the check job only at its time.
  launchctl bootstrap "gui/$U" "$f"
  echo "installed and loaded $l"
done
echo "Run the check once now with: launchctl kickstart gui/$U/com.signalclaw.check"
