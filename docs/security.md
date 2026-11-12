# Why each setting

An assistant that reads job postings is reading text written by strangers, and some of that text will try to give it instructions. So signalclaw assumes the agent can be talked into anything, and makes sure there is very little it could do even then.

Every setting below is in `config/hardening.batch.json`. Preview with `--dry-run` before applying.

## The sandbox: where the agent's commands run

| Setting | Value | Why |
|---|---|---|
| `agents.defaults.sandbox.mode` | `all` | Every agent session runs its tools in a container, not on your Mac. |
| `agents.defaults.sandbox.backend` | `docker` | The container is Docker. Docker Desktop must be running. |
| `agents.defaults.sandbox.docker.network` | `none` | The container has no network. A command the agent runs cannot reach the internet or your home network. (OpenClaw's own model calls happen outside the container, in the gateway.) |
| `agents.defaults.sandbox.workspaceAccess` | `rw` | The only folder from your Mac inside the container is the agent's workspace (`~/.openclaw/workspace`, seen as `/workspace`). Your home folder, keychain and other files are not there. |
| `agents.defaults.sandbox.scope` | `agent` | One container per agent. |
| `tools.exec.host` | `sandbox` | Commands run in the sandbox, never on the Mac. With `sandbox.mode: all`, if Docker is not running the agent refuses to run commands instead of falling back to the host. |
| `tools.fs.workspaceOnly` | `true` | File tools (read, write, edit) are limited to the workspace too. |
| `tools.elevated.enabled` | `false` | No "run this one outside the sandbox" escape hatch. |

**Check it fails closed.** Quit Docker Desktop and send the agent a message that needs a command. It should refuse with a sandbox error before any model call. Start Docker again and it recovers on its own. If the error suggests turning sandboxing off, don't.

## Tools the agent doesn't get

| Setting | Value | Why |
|---|---|---|
| `tools.profile` | `coding` | A small tool set: files and shell (inside the sandbox) plus a few session tools. |
| `tools.deny` | `github_publish`, `sessions_send`, `message` | No publishing to GitHub, no messaging other agent sessions, and no sending messages to anyone. The agent can still reply in the conversation it was messaged from: OpenClaw delivers the reply itself. The iMessage plugin adds the general `message` tool, which is why it is denied here. |
| `agents.defaults.heartbeat.every` | `0m` | No unprompted agent turns. The agent speaks only when spoken to. Status texts come from scripts, not the agent. |

**Use `tools.deny`, not `tools.sandbox.tools.deny`.** Setting the sandbox-level list replaces OpenClaw's default sandbox deny list (browser, gateway, every messaging channel) instead of adding to it. `deny` at the top level always wins and leaves the defaults in place.

**Check what the agent really has.** `openclaw sandbox explain --agent <id>` shows the sandbox layer and mounts, but not the final effect of `tools.deny`. To see that, ask the agent to list its tools.

## Who can reach the agent

| Setting | Value | Why |
|---|---|---|
| `channels.imessage.dmPolicy` | `allowlist` | Only numbers or addresses in `allowFrom` reach the agent. Everyone else is dropped before the agent sees the message. |
| `channels.imessage.allowFrom` | your number | Set by you during setup. Not in the batch file, so it never ends up in a repo. `notify.sh` reads it at send time for the same reason. |
| `channels.imessage.groupPolicy` | `disabled` | Group chats are ignored. |
| `channels.imessage.configWrites` | `false` | Nothing said in a chat can change OpenClaw's config. |
| `channels.imessage.includeAttachments` | `false` | Images and files sent over iMessage don't reach the agent. |

## What the gateway exposes

| Setting | Value | Why |
|---|---|---|
| `gateway.mode` / `gateway.bind` | `local` / `loopback` | The gateway listens only on this Mac, not on your network. |
| `gateway.tailscale.mode` | `off` | No remote access route. |
| `discovery.mdns.mode`, `plugins.entries.bonjour.enabled` | `off`, `false` | The gateway is not advertised on the local network. |
| `telemetry.enabled` | `false` | No usage data leaves the Mac. |
| `plugins.entries.{browser, cua-computer, file-transfer, canvas, linux-node, geolocation}.enabled` | `false` | Capabilities this setup doesn't need: driving a browser or the desktop, moving files, location. Off means not loaded. |

## Outside OpenClaw

- **A dedicated macOS user.** Run OpenClaw in its own Standard (non-admin) account. The agent's account can't install system software, read your main account's files, or change security settings.
- **An API key with a spend limit.** Use an Anthropic API key made just for this, with a monthly limit set in the Anthropic Console.
- **A separate Apple ID** for the assistant's Messages account, so it isn't signed in as you.
- **No GitHub (or other) credentials in the agent's account** unless you have a specific need. The sandbox can't reach them, but there is no reason to have them there.
- **Status texts without the agent.** `notify.sh` uses `openclaw message send`, an ordinary command with no model call. Alerts still work if the agent is confused, and cost nothing. (OpenClaw shows these sends in the agent's chat history, which is why the agent's instructions say the texts come from a script.)
