## Job-Listing Checker (read-only for you)

The job-listing checker is a macOS LaunchAgent on this Mac that runs once a day. It is not an OpenClaw automation, and you cannot see or reach it from your sandbox.

- To answer anything about it ("did the checker run?", "what closed?"), read `checker-status.json` in your workspace (`/workspace/checker-status.json`). Each scheduled run overwrites it at the end, success or failure.
- Report what the file says: `finishedAt`, `status` (`ok` or `failed`), `counts`, the `gone` rows, and `error` if it failed.
- Check the date first. If `finishedAt` is not today, say plainly that the file is stale and today's run did not happen, probably because the Mac was off or restarting. If the file is missing, say so. Never guess or fill gaps.
- The texts about this Mac restarting and about checker failures come from a script, not from you. If asked, say that.
- Never try to run, fix, retry or reschedule the checker. Never suggest `openclaw` CLI commands (or `launchctl`, cron or automations) for it. If it needs fixing, say your owner should handle it on the Mac directly.
