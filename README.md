# parcels

Package your work — repo, uncommitted changes, `.env` files, and the live agent
session — and ship it over Tailscale to another machine, where the agent resumes
in tmux and keeps working.

Supports **Claude Code**, **Codex**, **pi**, **Droid**, and **Grok Build** sessions.

## Install

```sh
git clone https://github.com/0xSero/parcels && cd parcels && ./install.sh
```

This symlinks `parcel` into `~/.local/bin`, installs the `/parcel` skill for
Claude Code (`~/.claude/skills/parcel`) and Grok Build (`~/.grok/skills/parcel`)
when those homes exist, and seeds `~/.parcels/targets/` with an example target
config. Requirements: `ssh` access to your targets (Tailscale MagicDNS names
work great), `rsync`, `tmux` + the agent CLIs on the targets.

```
parcel send pop-os                      # ship cwd repo + newest claude session, resume there
parcel send pop-os --agent droid        # same but for a droid session
parcel send pop-os --agent grok         # Grok Build (xAI) session
parcel send spark --idle                # ship but don't launch
parcel send pop-os --session <id>       # pick an exact session
parcel send pop-os --prompt "focus on the failing tests first"
parcel status                           # what's running where (tails tmux panes)
parcel doctor pop-os                    # preflight: binaries + auth on the target
parcel auth spark                       # copy portable creds (codex/pi/grok) to target
parcel targets                          # list configured targets
```

## How it works

1. **HANDOFF.md** — the sending agent writes its intent (what it was doing, next
   steps, gotchas) at the repo root; `parcel` appends a mechanical state snapshot
   (branch, last commit, `git status`). This is the universal fallback: any agent
   on any machine can pick up from it.
2. **Working tree** — rsync of the whole repo including `.git`, untracked files,
   and `.env`s (excludes `node_modules`, `.venv`, `__pycache__`, build dirs).
3. **Session transplant** — the session transcript is copied into the remote
   agent's expected per-project location (each agent sanitizes the cwd path
   differently; `parcel` knows all five layouts) so native resume works:
   - claude: `~/.claude/projects/<sanitized-cwd>/<uuid>.jsonl` → `claude --resume <uuid>`
   - codex: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` → `codex exec resume <uuid>`
   - pi: `~/.pi/agent/sessions/<sanitized-cwd>/*.jsonl` → `pi -c`
   - droid: `~/.factory/sessions/<sanitized-cwd>/<uuid>.jsonl` (+ index entry) → `droid exec -s <uuid>`
   - grok: `~/.grok/sessions/<url-encoded-cwd>/<uuid>/` → `grok --resume <uuid>`
4. **Launch** — a tmux session `parcel-<repo>` starts on the target and the agent
   resumes with your prompt (default: "read HANDOFF.md and continue"). Attach any
   time: `ssh -t <host> tmux attach -t parcel-<repo>`.

## Targets

One file per machine in `~/.parcels/targets/<name>.conf`:

```sh
HOST=pop-os      # ssh host (Tailscale MagicDNS name works)
DEST_BASE=ai     # repos land in ~/<DEST_BASE>/<repo-name> on the target
AGENT=claude     # default agent for this target
```

## Auth (one-time per machine, not per handoff)

- **claude** — run `claude login` on the target once, or mint a long-lived token
  on an authed machine with `claude setup-token` and set `CLAUDE_CODE_OAUTH_TOKEN`
  in the target's shell profile.
- **codex / pi / grok** — plain-file creds; `parcel auth <target>` copies them.
  Grok also accepts `XAI_API_KEY` or `grok login` on the target.
- **droid** — encrypted per-machine; run `droid` once on the target to log in.

`parcel doctor <target>` tells you exactly what's missing.
