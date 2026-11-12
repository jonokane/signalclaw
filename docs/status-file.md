# The status file

`run-with-status.sh` ends every scheduled run by overwriting one JSON file in the agent's workspace:

```
~/.openclaw/workspace/checker-status.json     (on the Mac)
/workspace/checker-status.json                 (inside the agent's sandbox)
```

This is the whole interface between the scheduled job and the agent. The agent never runs the job, never sees its logs and needs no extra permissions. It reads one file in the one folder it can already see.

## When it is written

| What happened | File |
|---|---|
| The job finished and exited 0 | `"status": "ok"` |
| The job exited non-zero | `"status": "failed"`, with the job's last `FAILED: ...` line (or last line) as `error` |
| The job ran past the time limit | `"status": "failed"`, `"exitCode": 124` |
| The wrapper itself was killed or stopped early | `"status": "failed"`, written by an EXIT trap |
| `SIGNALCLAW_RESULTS` is set but no results were written this run | `"status": "failed"`, even if the job exited 0 |
| The Mac was off at the scheduled time | Nothing. The old file stays, so `finishedAt` is not today. |

The file is written to a temporary name and renamed into place, so the agent never reads half a file.

## Fields

```json
{
  "about": "Status of the job checker, a macOS LaunchAgent (not an OpenClaw automation). ...",
  "startedAt": "2026-11-12T05:30:00-08:00",
  "finishedAt": "2026-11-12T05:38:12-08:00",
  "status": "ok",
  "exitCode": 0,
  "error": "",
  "counts": { "LIVE": 42, "GONE": 8, "CHANGED": 2, "CANT_TELL": 26 },
  "checked": 78,
  "gone": [
    { "company": "Acme", "title": "Staff Product Designer", "url": "https://..." }
  ],
  "resultsRunAt": "2026-11-12T05:30:01-08:00"
}
```

`counts`, `checked`, `gone` and `resultsRunAt` appear only when `SIGNALCLAW_RESULTS` points at a signalcheck results file. `note` appears when the check finished but a later step failed (for example a git push), so the counts are real even though the status is `failed`.

## What never goes in

Only the fields above are copied from the results. No reasons, row ids or other columns. The error text is cut to 500 characters, and anything that looks like an email address or a phone number is replaced, because the agent may quote it back over chat.

## Using it with a different job

Nothing here is specific to job listings. Any command works:

```sh
SIGNALCLAW_JOB_NAME="backup" SIGNALCLAW_STATUS_FILE=~/.openclaw/workspace/backup-status.json \
  scripts/run-with-status.sh rsync -a ~/Documents /Volumes/Backup/
```

Then give the agent a short instructions section like `agent/AGENTS-checker-section.md`, pointing at that file.
