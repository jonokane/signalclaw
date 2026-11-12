#!/bin/sh
# Optional, for headless Macs with automatic login (LaunchAgent
# com.signalclaw.lock-at-login). Automatic login keeps the gateway and the
# check job running after a power cut, but leaves an unlocked session. This
# waits for both to load, then sleeps the display. With "Require password
# immediately" set in Lock Screen settings, that locks the session while every
# agent keeps running.
#
# Settings: SIGNALCLAW_CHECK_LABEL (default com.signalclaw.check)
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
CHECK_LABEL="${SIGNALCLAW_CHECK_LABEL:-com.signalclaw.check}"
U="$(id -u)"
stamp() { date '+%Y-%m-%d %H:%M:%S %Z'; }
echo "$(stamp) login; waiting 60 s before locking"
sleep 60
i=0
while [ $i -lt 24 ]; do   # up to 4 more minutes if either job is not loaded yet
  launchctl print "gui/$U/ai.openclaw.gateway" >/dev/null 2>&1 &&
    launchctl print "gui/$U/$CHECK_LABEL" >/dev/null 2>&1 && break
  sleep 10; i=$((i + 1))
done
pmset displaysleepnow && echo "$(stamp) display asleep; session locked" || echo "$(stamp) pmset displaysleepnow failed"
