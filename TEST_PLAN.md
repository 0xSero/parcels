# Parcels — Test Plan (the contract)

`done` is defined here. Nothing ships until every line below is green.

## Tiers

| Tier | What | Network | Count |
|------|------|---------|-------|
| U | Unit / pure functions | none | 9 |
| C | Command construction (dry-run) | none (prints, doesn't exec) | 5 |
| I | Integration (local fake remote + local tmux) | localhost only | 6 |
| E | End-to-end against real `pop-os` over Tailscale | real SSH | 6 |

## U — Unit (pure)

- U1 `sanitize_name("vllm-studio")` → `vllm-studio`
- U2 `sanitize_name("My.App:v2")` → `my-app-v2`
- U3 `sanitize_name("a   b/c.d")` → `a-b-c-d`
- U4 `sanitize_name("__x__")` → `x` (leading/trailing `-`/`_` stripped, runs collapsed)
- U5 `default_name("/Users/sero/ai/inference/vllm-studio")` → `vllm-studio`
- U6 manifest JSON parses and has required keys (`name`, `agent`, `source_cwd`, `remote`, `created`, `parcels_version`)
- U7 `run.sh` for pi contains `exec pi --session <path> --session-dir <dir>` and `cd <project>`
- U8 `run.sh` is executable bit set after gen
- U9 `.parcels` parser reads `agent`, `exclude`, `env`, `remote`, `model`, `name` correctly; ignores comments/blank lines

## C — Command construction (PARCELS_DRY_RUN=1)

- C1 `push` emits an `rsync` line targeting `pop-os:~/.parcels/<name>/`
- C2 `push` emits a `tmux new-session -d -s <name>` line running `run.sh`
- C3 `attach` emits `ssh pop-os -t tmux attach -t <name>`
- C4 `rm` emits `tmux kill-session -t <name>` and `rm -rf ~/.parcels/<name>`
- C5 `pull` emits an `rsync` from remote project back to local

## I — Integration (PARCELS_LOCAL=1, real local tmux, fake remote dir)

- I1 `push` from a temp project creates `~/.parcels/<name>/{manifest.json,run.sh,project/,session.jsonl}`
- I2 the parcel appears in `list` output with `live` status
- I3 the local tmux session `<name>` actually exists (`tmux has-session`)
- I4 second `push` of same name **exits non-zero** and prints all three options (attach / `-2` / `--replace`)
- I5 `push <name>-2` succeeds alongside the first
- I6 `rm <name>` removes local dir AND kills the tmux session

## E — End-to-end (real pop-os)

- E1 `push` from a real project exits 0 and prints the attach hint
- E2 `ssh pop-os tmux has-session -t <name>` → exists
- E3 `parcels list` shows the parcel as `live` with `remote=pop-os`
- E4 `parcels pull <name>` exits 0 and brings session.jsonl back
- E5 `parcels rm <name>` exits 0
- E6 **cleanup verified**: `ssh pop-os 'tmux ls'` shows no `<name>` session AND `ssh pop-os 'ls ~/.parcels/<name>'` is gone

## End condition

All U + C + I green in the local runner, **and** E1–E6 all pass with pop-os left
in its original state (no orphan tmux sessions, no leftover parcel dirs).
