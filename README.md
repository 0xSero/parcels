# parcels

Ship the current agent session to a remote box (Pop OS) over Tailscale,
run it inside a persistent tmux session, and reattach from anywhere.

> One string, three uses: **parcel dir name == tmux session name == attach target.**
> The filesystem is the registry (`ls ~/.parcels`).

## Why

You're working in pi on the MacBook. You need to close the lid. You want the
session to survive, the files available, the agent still running — and to snap
back to the live session when you reopen the laptop. tmux on a always-on box
over Tailscale is the spine; this is the glue.

## Install

```bash
ln -sf "$PWD/parcels" ~/.local/bin/parcels   # or anywhere on $PATH
parcels help
```

Requires: `bash`, `ssh`, `rsync`, `tmux` (on the remote). A Tailscale-routed
host (default: `pop-os`) with passwordless SSH.

## Use

```bash
# from inside a project (optionally inside a pi session)
parcels push                    # ships current dir + session, launches tmux on pop-os
parcels attach vllm-studio      # reattach to the live session
parcels list                    # show all parcels + live status
parcels pull vllm-studio        # rsync working tree + session back to MacBook
parcels rm vllm-studio          # kill tmux + delete parcel (both ends)
```

### Naming

- Default = sanitized project basename (`~/ai/inference/vllm-studio` → `vllm-studio`).
- `.` `:` `/` space → `-`; lowercase; `[a-z0-9_-]` only.
- `parcels push debug-auth` overrides.
- Collision → push refuses and offers: `attach`, `push <name>-2`, or `--replace`.

### Per-project config (`.parcels`, optional)

```ini
agent=pi                # pi (default) | claude | codex | opencode
model=anthropic/...     # optional override
remote=pop-os           # Tailscale host (default pop-os)
name=...                # override default name
exclude=node_modules dist build
```

## The "link back"

There is no link to maintain. The tmux session on Pop OS **is** the source of
truth. MacBook sleeps → it keeps running. MacBook reopens → `parcels attach`
→ you're back in the live session, same scrollback, same agent state.

## Credentials

Verified: `~/.pi/agent/auth.json` is already identical on both machines
(same providers), so pi needs no key transport. Project-local secrets travel
inside the parcel over the encrypted SSH/Tailscale link; nothing is logged.

## Design & test plan

- [DESIGN.md](DESIGN.md) — full architecture.
- [TEST_PLAN.md](TEST_PLAN.md) — acceptance criteria (the contract).

## Test

```bash
./test/run_tests.sh   # 43 unit + construction + integration tests (local)
./test/e2e.sh         # 10 end-to-end tests against real pop-os (auto-cleanup)
```

E2E is **idempotent** and leaves pop-os clean via a guaranteed cleanup trap.
