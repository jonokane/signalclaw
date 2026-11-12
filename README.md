# SignalClaw

A locked-down [OpenClaw](https://docs.openclaw.ai) assistant for your job search, that you can text.

SignalClaw sets up OpenClaw on a Mac so you can reach your assistant over iMessage, while it runs in a sandbox with no network, no access to your files and no way to message anyone but you. A daily job check runs beside it, and the assistant can tell you how that went without being given any extra access.


```
You (iMessage)  <--->  OpenClaw gateway  <--->  Assistant (Docker sandbox, no network)
                              ^                         |
                              | status texts            | reads
                              |                         v
                     launchd scripts  ---writes--->  checker-status.json
                              |                     (in the assistant's workspace)
                              v
                     daily job check (e.g. signalcheck)
```

## What it does

- **Sandboxed, and fails closed.** The assistant runs in a Docker container with no network. The only folder it can see is its own workspace. If Docker isn't running, it refuses rather than running anything on your Mac.
- **Just you.** Only your number gets through; group chats and attachments are ignored. It can't message anyone else, publish anything or change its own settings.
- **Knows about your daily job.** A scheduled job, such as a check that saved job postings are still open, writes a small status file the assistant can read. Text "did the checker run today?" and get a straight answer: when it ran, how many jobs are still open, which ones closed, or that it didn't run at all. The assistant gets no extra access.
- **Texts you when something breaks.** If the daily job fails, or the Mac restarts (with the shutdown cause), a plain script sends the text, with no AI involved.
- **Every setting explained.** See [docs/security.md](docs/security.md).

## How to use it

1. Install OpenClaw and Docker in a dedicated, non-admin macOS user, and set up iMessage.
2. Apply the hardening settings (`config/hardening.batch.json`) and add your own number to the allowlist.
3. Paste the checker section into the assistant's `AGENTS.md`.
4. Schedule your daily check with `scripts/install.sh`.
5. Text the assistant.

Step-by-step commands are in [Setup](#setup) below.

SignalClaw pairs with **SignalCheck** (coming soon), a separate tool that checks whether saved job postings are really still open. You can use either one without the other: SignalClaw's scheduler runs any command.

## Requirements

- A Mac that stays on. Tested on an M4 Mac mini running macOS 15 (Sequoia), headless over Screen Sharing.
- A dedicated Standard (non-admin) macOS user for the assistant.
- [OpenClaw](https://docs.openclaw.ai) 2026.11 or later, and [Docker Desktop](https://www.docker.com/products/docker-desktop/).
- An Anthropic API key made for this, with a monthly spend limit.
- A separate Apple ID signed into Messages in the assistant's macOS user.

## Setup

Do all of this signed in as the assistant's macOS user.

**1. Install OpenClaw** and run its setup, following the [OpenClaw docs](https://docs.openclaw.ai). Use an API key, stored the way the setup suggests, not a file in this folder. Set up the iMessage channel the same way. On a headless Mac, be on Screen Sharing for the first reply: macOS asks once for permission to control Messages, and if nobody clicks Allow, replies fail silently.

**2. Apply the hardening settings.** Preview, then apply:

```sh
openclaw config set --batch-file config/hardening.batch.json --dry-run
openclaw config set --batch-file config/hardening.batch.json
```

**3. Allow your own number** (and nobody else's):

```sh
openclaw config set channels.imessage.allowFrom '["+15555550123"]'
```

Restart the gateway after changing config (see the OpenClaw docs for your install).

**4. Check it.** `openclaw sandbox explain --agent <id>` shows the sandbox and its one mounted folder. Then text the assistant "list your tools": `message`, `sessions_send` and `github_publish` should not be among them. Finally, quit Docker Desktop and ask it to run a command. It should refuse. Start Docker again.

**5. Teach the assistant about the check.** Paste [agent/AGENTS-checker-section.md](agent/AGENTS-checker-section.md) into `~/.openclaw/workspace/AGENTS.md`, the instructions file OpenClaw loads for the assistant.

**6. Schedule the daily check.** Preview the LaunchAgents, then install them:

```sh
scripts/install.sh --print --check "YOUR CHECK COMMAND" --at 05:30 --restart-alert
scripts/install.sh         --check "YOUR CHECK COMMAND" --at 05:30 --restart-alert
```

With SignalCheck, add `--results /path/to/results/latest.json` so the status file includes the counts and closed jobs. If the Mac uses automatic login so everything comes back after a power cut, add `--lock-at-login` to lock the screen again a minute later.

**7. Try it.** Run the check once now with `launchctl kickstart gui/$(id -u)/com.signalclaw.check`. When it finishes, text the assistant "did the checker run today?"

## What's in here

| Path | What it is |
|---|---|
| `config/hardening.batch.json` | Every OpenClaw setting SignalClaw changes, as one `openclaw config set` batch |
| `agent/AGENTS-checker-section.md` | The instructions section that tells the assistant how to answer about the check |
| `scripts/run-with-status.sh` | Runs the check with a time limit, writes the status file, texts you on failure |
| `scripts/write_status.py` | Writes the status file (Python standard library only) |
| `scripts/notify.sh` | Sends one text through `openclaw message send`. Reads your number from OpenClaw's config at send time. |
| `scripts/restart-alert.sh` | After a restart, waits for the gateway and texts you a status line |
| `scripts/lock-at-login.sh` | Optional: locks the screen after automatic login |
| `scripts/install.sh`, `scripts/uninstall.sh` | Add or remove the LaunchAgents. No admin needed. |
| `docs/security.md` | Why each setting exists |
| `docs/status-file.md` | The status file format, and how to use it for other jobs |

## Tests

```sh
python3 -m unittest discover -s tests
```

No network and no OpenClaw needed. The tests run the real wrapper around small fake jobs (success, failure, timeout, killed) and check the installer's plists with `plutil`.

## License

MIT. See [LICENSE](LICENSE).
