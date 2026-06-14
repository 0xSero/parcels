# Parcels — Design

> Ship the current agent session to a remote box (Pop OS) over Tailscale,
> run it inside a persistent tmux session, and reattach from the MacBook
> whenever you reopen the lid.

---

## 1. The problem, restated

You're working in pi (or Claude Code / Codex / OpenCode) on the MacBook.
You need to close the lid. You want:

1. The agent's **session/context** to survive.
2. The **working tree** to be available on the other machine.
3. The **relevant keys** to be present.
4. The agent to **keep running** on Pop OS inside tmux.
5. On reopening the MacBook, to **snap back** to the live session.

## 2. The key realization: almost nothing needs building

Everything the workflow needs already exists and is verified working:

| Need | Already-solved by | Verified |
|------|-------------------|----------|
| Flat network between MacBook and Pop OS | **Tailscale** | `pop-os` online at `100.90.62.80` |
| Authenticated transport + remote exec | **SSH** (key `~/.ssh/linux-ai`) | `ssh pop-os ...` works |
| Fast file sync of the working tree | **rsync** | present on both ends |
| Session that survives the laptop sleeping | **tmux** on Pop OS | `/usr/bin/tmux` present |
| Portable agent session | **pi JSONL** + `pi --session <path>` | `pi --help` confirms |
| Credentials on the remote | **`~/.pi/agent/auth.json`** | identical top-level keys on both machines |

So "parcels" is **orchestration glue**, not infrastructure. The thinner the glue,
the better.

## 3. Architecture (minimal)

Two pieces, both tiny:

```
                  MacBook (client)                      Pop OS (server)
                  ────────────────                      ───────────────
   pi ──┐                                            ┌── tmux: parcels/<name>
        ├──> parcels (shell CLI) ──ssh/rsync────────>│     └─ pi --session ...
   /parcels (pi extension)                           │     └─ project/ (rsync mirror)
        │                                            └── ~/.parcels/<name>/
   claude/codex/opencode ──> parcels (same CLI)           ├── manifest.json
                                                          ├── session.jsonl
   ~/.parcels/<name>/  (local registry)                   ├── run.sh   (self-launcher)
                                                          └── project/
```

### Piece A — `parcels` CLI

A single dependency-free shell script, installed once on the MacBook. It owns
all the logic; everything else calls it. Subcommands:

| Command | What it does |
|---------|--------------|
| `parcels push [name]` | Snapshot session + cwd, rsync to Pop OS, launch in tmux |
| `parcels attach <name>` | `ssh pop-os -t tmux attach -t <name>` |
| `parcels list` | Show local registry + live tmux sessions on Pop OS |
| `parcels pull <name>` | rsync working tree (and updated session.jsonl) back to MacBook |
| `parcels rm <name>` | Kill tmux session + delete parcel dir on Pop OS + local entry |

### Piece B — thin agent wrappers

The CLI is agent-agnostic. Each agent gets a ~10-line wrapper so you can type
a slash command inside it:

- **pi**: an extension at `~/.pi/agent/extensions/parcels.ts` that registers
  `/parcels` and shells out to the CLI. Reads the live session file via
  `ctx.sessionManager.getSessionFile()`.
- **Claude Code**: a markdown command at `~/.claude/commands/parcels.md` that
  runs `!parcels push`.
- **Codex / OpenCode**: their own command files pointing at the same CLI.

The wrappers do no real work. The CLI does.

## 4. What a "parcel" actually is

A directory, mirrored on both machines:

```
~/.parcels/<name>/
├── manifest.json     # agent, model, source cwd, created, host, excludes
├── session.jsonl     # pi session snapshot (copied from ~/.pi/agent/sessions/...)
├── run.sh            # self-contained launcher (generated on push)
└── project/          # rsync mirror of the working tree
```

### Naming (one string, three uses)

The parcel directory name, the tmux session name, and what you type into
`parcels attach` are **all the same identifier**. No registry file — the
filesystem is the registry (`ls ~/.parcels`).

- **Default**: sanitized basename of the project dir.
  `~/ai/inference/vllm-studio` → `vllm-studio`.
- **Sanitization**: lowercase; `.` `:` `/` space → `-`; strip anything
  outside `[a-z0-9_-]`; collapse runs of `-`.
  `My.App:v2` → `my-app-v2`. (We sanitize ourselves because tmux 3.2a silently
  rewrites `.`/`:` → `_`, and we want predictable `-`-joined names.)
- **Explicit**: `parcels push debug-auth` overrides the default.
- **Collision**: if `<name>` exists, push refuses and prints the three options:
  `attach` the live one, `push <name>-2` for a parallel session, or
  `push --replace` to kill+reship (loses remote state, so it must be asked for).

The `.parcels` config reserves a `name=` field for per-project overrides if
basename collisions become routine later.

### Optional per-project config: `.parcels` (in the project root)

```ini
agent=pi                       # pi | claude | codex | opencode
model=anthropic/claude-...     # optional override
env=.env secrets.local.env     # files to ship verbatim
exclude=node_modules .venv dist build *.log
remote=pop-os                  # default target (Tailscale host)
```

Absent any config, sane defaults apply (pi agent, pop-os target, standard
excludes). Zero config = it just works.

## 5. The push flow (the moment that matters)

You're in pi on `~/ai/inference/vllm-studio`. You type `/parcels push`.

1. pi extension calls `parcels push` with the live session path.
2. CLI copies `~/.pi/agent/sessions/.../<current>.jsonl` →
   `~/.parcels/vllm-studio/session.jsonl`.
3. CLI writes `manifest.json` (agent, model, source cwd, timestamp).
4. CLI **generates `run.sh` locally** (so there is zero nested-shell escaping):
   ```bash
   #!/usr/bin/env bash
   cd ~/.parcels/vllm-studio/project
   exec pi --session ~/.parcels/vllm-studio/session.jsonl \
           --session-dir ~/.parcels/vllm-studio/
   ```
5. `rsync` the parcel dir → `pop-os:~/.parcels/vllm-studio/`
   (working tree uses `--exclude` from config / defaults).
6. `ssh pop-os "tmux new-session -d -s vllm-studio 'bash ~/.parcels/vllm-studio/run.sh'"`
7. Notify: `Parcel 'vllm-studio' shipped. Attach: parcels attach vllm-studio`

The remote command stays a clean one-liner because the launcher lives inside
the parcel.

## 6. The "link back"

There is no link in the networking sense — there doesn't need to be. The tmux
session **is** the source of truth and lives on Pop OS:

- MacBook sleeps → tmux session keeps running on Pop OS. The agent is either
  still working or waiting at a prompt.
- MacBook reopens → `/parcels attach` (or `parcels attach vllm-studio`) →
  `ssh pop-os -t tmux attach -t vllm-studio`. You are instantly back in the
  live session. Same cells, same scrollback, same agent state.

This is the classic "always-on tmux on a server" pattern, deliberately. It is
the simplest possible thing that satisfies "reopen the laptop, get everything
back."

### Optional: syncing work *back* to the MacBook disk

If you also want the files the agent produced to land on the MacBook
(not just to view them live), `parcels pull <name>` rsyncs the working tree
in reverse and copies the updated `session.jsonl` back, so a local
`pi --session ...` can resume from where the remote got to. Explicit, opt-in,
not automatic.

## 7. Cross-agent behavior

| Agent | Session portability | Parcel behavior |
|-------|---------------------|-----------------|
| **pi** | Native (JSONL, `--session <path>`) | Full fidelity resume. Best case. |
| **claude / codex / opencode** | Sessions live in their own stores | Ship cwd + env + an auto-generated `HANDOFF.md` (what we were doing, open tasks, last command). They start a fresh session that reads it. Graceful degradation. |

The manifest records `agent`, and `run.sh` is generated accordingly.

## 8. Credentials

Verified: `~/.pi/agent/auth.json` already has the same providers configured on
both machines (`anthropic`, `openai-codex`, `kimi-coding`, `google-antigravity`).
So **no key transport is needed for pi**. For project-local secrets (a `.env`),
the `.parcels` config lists which files to ship, and they travel inside the
parcel over the already-encrypted SSH/Tailscale link. Nothing is logged.

## 9. tmux is the runtime, not a feature

The whole "reopen the laptop, get everything back" property comes from tmux
being a persistent server on Pop OS. It is load-bearing, not optional:

- MacBook sleeps → the tmux server on Pop OS keeps the agent running.
- MacBook reopens → `parcels attach <name>` runs
  `ssh pop-os -t tmux attach -t <name>`, landing you back in the live session
  with identical scrollback and agent state.
- Multiple parcels coexist as multiple tmux sessions on one server.

Verified on Pop OS: `tmux 3.2a`, `new-session -d -s <name>` works, names must
avoid `.`/`:` (we sanitize to `-` ourselves). No mosh, no daemon, no extra
service — SSH + the tmux server is the entire runtime.

## 10. What is deliberately NOT in the minimal version

To keep it minimal, these are deferred until the core proves out:

- **No daemon / server / database on either machine.** SSH + tmux is the runtime.
- **No auto-pull on MacBook wake** (launchd agent). Run `parcels pull` by hand.
- **No WoL / wake-on-lan** if Pop OS is asleep. Tailscale supports it; add later.
- **No multi-host fleet.** `pop-os` is the only target for now; the config
  already has a `remote=` field for later expansion.
- **No mosh.** Plain SSH is fine over Tailscale; revisit if links get flaky.
- **No GUI / dashboard.** `parcels list` is enough.

## 11. Open questions to confirm before building

1. **Target host**: lock to `pop-os`, or wire up the `.parcels remote=` selector
   now (so `macmini` / `spark-2822` are one flag away)?
2. **pi version drift**: MacBook is `0.79.3`, Pop OS is `0.73.0`. OK to
   `pi update --self` on Pop OS as part of the install step? (Not blocking —
   JSONL auto-migrates — but keeps feature parity.)
3. **Default agent**: pi first (richest), with claude/codex wrappers following?
4. **Project transport**: default to full `rsync --exclude` (simple, works for
   106 MB repos like vllm-studio in seconds), with a git-transport mode
   (`remote+branch+patch`) as an opt-in for huge trees?

## 12. MVP build plan (once approved)

1. `parcels` shell script: `push`, `attach`, `list`, `pull`, `rm`. (~250 lines)
2. `~/.pi/agent/extensions/parcels.ts`: `/parcels` command wrapping the CLI. (~60 lines)
3. End-to-end test on `vllm-studio`: push from MacBook, attach, type, detach,
   close lid, reopen, reattach, pull.
4. (Follow-up) claude / codex command wrappers + `HANDOFF.md` generator.

Total surface: **one script + one extension**. No new protocols, no services,
no persistence layer beyond tmux itself.
