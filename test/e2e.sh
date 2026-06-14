#!/usr/bin/env bash
# parcels E2E — real pop-os over Tailscale. GUARANTEED cleanup at exit.
# Uses a real local project; the parcel name is marked as a test.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PARCELS_BIN="$HERE/../parcels"
TEST_NAME="parcels-e2e-test"
REAL_PROJECT="/Users/sero/ai/inference/vllm-studio"

PASS=0; FAIL=0; FAILED_TESTS=()
ok()   { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); FAILED_TESTS+=("$1"); printf '  \033[31m✗\033[0m %s\n' "$1"; }
assert_contains() {
  local label="$1" needle="$2" hay="$3"
  if printf '%s' "$hay" | grep -qF -- "$needle"; then ok "$label"; else
    fail "$label (missing [$needle])
      hay: $hay"; fi
}

# GUARANTEED cleanup — no matter how we exit, leave pop-os clean
cleanup() {
  echo
  echo "## cleanup"
  $PARCELS_BIN rm "$TEST_NAME" >/dev/null 2>&1 && echo "  removed $TEST_NAME" || true
  # belt-and-suspenders: verify nothing leaked
  if ssh pop-os "tmux has-session -t '$TEST_NAME' 2>/dev/null"; then
    ssh pop-os "tmux kill-session -t '$TEST_NAME'" && echo "  force-killed leftover tmux session"
  fi
  ssh pop-os "command rm -rf ~/.parcels/$TEST_NAME" 2>/dev/null || true
  echo "  done"
}
trap cleanup EXIT

echo "## E — End-to-end against real pop-os"
echo "  (baseline: pre-existing tmux sessions left untouched)"

# Idempotent setup: clear any stale local + remote state from prior runs.
# This makes the test re-runnable regardless of how the last run ended.
rm -rf "$HOME/.parcels/$TEST_NAME" 2>/dev/null || true
ssh pop-os "tmux kill-session -t '$TEST_NAME' 2>/dev/null; command rm -rf ~/.parcels/$TEST_NAME" 2>/dev/null || true

# Pre-flight: name must not already exist (after cleanup above it shouldn't)
if ssh pop-os "tmux has-session -t '$TEST_NAME' 2>/dev/null"; then
  echo "ABORT: $TEST_NAME still exists on pop-os after cleanup" >&2
  exit 99
fi

# E1: push from the real project
push_out="$( ( cd "$REAL_PROJECT" && "$PARCELS_BIN" push "$TEST_NAME" ) 2>&1 )"
rc=$?
if [ "$rc" = "0" ]; then ok "E1 push exits 0"; else fail "E1 push exits 0 (got $rc)
$push_out"; fi
assert_contains "E1 prints attach hint" "parcels attach $TEST_NAME" "$push_out"
assert_contains "E1 names the host"     "pop-os"                    "$push_out"

# E2: tmux session actually exists on pop-os
if ssh pop-os "tmux has-session -t '$TEST_NAME' 2>/dev/null"; then ok "E2 tmux session exists on pop-os"; else fail "E2 tmux session exists"; fi

# E3: parcels list shows it as live
list_out="$("$PARCELS_BIN" list 2>&1)"
assert_contains "E3 list shows parcel" "$TEST_NAME" "$list_out"
assert_contains "E3 list shows live"   "● live"     "$list_out"

# E4: pull brings session.jsonl back (exit 0)
if "$PARCELS_BIN" pull "$TEST_NAME" >/dev/null 2>&1; then ok "E4 pull exits 0"; else fail "E4 pull exits 0"; fi

# E5: rm exits 0
if "$PARCELS_BIN" rm "$TEST_NAME" >/dev/null 2>&1; then ok "E5 rm exits 0"; else fail "E5 rm exits 0"; fi

# E6: cleanup verified — session gone AND dir gone (BEFORE the trap re-runs rm)
if ssh pop-os "tmux has-session -t '$TEST_NAME' 2>/dev/null"; then fail "E6 tmux session still present"; else ok "E6 tmux session gone"; fi
if ssh pop-os "test -d ~/.parcels/$TEST_NAME"; then fail "E6 parcel dir still present"; else ok "E6 parcel dir gone"; fi

echo
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then printf '  FAILED:\n'; printf '    - %s\n' "${FAILED_TESTS[@]}"; exit 1; fi
echo "E2E ALL GREEN — pop-os left clean"
