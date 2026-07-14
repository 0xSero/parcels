#!/usr/bin/env bash
# Install parcel: symlink the CLI onto PATH and the skill into Claude Code / Grok.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bindir="${1:-$HOME/.local/bin}"
mkdir -p "$bindir"
ln -sf "$here/bin/parcel" "$bindir/parcel"
echo "✓ CLI: $bindir/parcel"
case ":$PATH:" in *":$bindir:"*) ;; *) echo "  NOTE: add $bindir to your PATH" ;; esac

if [[ -d "$HOME/.claude" ]]; then
  mkdir -p "$HOME/.claude/skills"
  ln -sfn "$here/skills/parcel" "$HOME/.claude/skills/parcel"
  echo "✓ Claude Code skill: ~/.claude/skills/parcel (/parcel)"
fi

if [[ -d "$HOME/.grok" ]]; then
  mkdir -p "$HOME/.grok/skills"
  ln -sfn "$here/skills/parcel" "$HOME/.grok/skills/parcel"
  echo "✓ Grok Build skill: ~/.grok/skills/parcel (/parcel)"
fi

mkdir -p "$HOME/.parcels/targets"
if ! ls "$HOME/.parcels/targets"/*.conf >/dev/null 2>&1; then
  cat > "$HOME/.parcels/targets/example.conf" <<'EOF'
# Copy to <name>.conf — `parcel send <name>` will use it.
HOST=my-machine      # ssh host (Tailscale MagicDNS name works)
DEST_BASE=ai         # repos land in ~/<DEST_BASE>/<repo-name> on the target
AGENT=claude         # default agent: claude | codex | pi | droid | grok
EOF
  echo "✓ example target: ~/.parcels/targets/example.conf"
fi
echo "Next: create a target conf, then run: parcel doctor <target>"
