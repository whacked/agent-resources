#!/usr/bin/env bash
# Integration test: agent writes land under the resolved workspace, NOT the
# install dir. Exit 0 = all pass.
set -uo pipefail

NOTES_SCRIPTS="$(cd "$(dirname "$0")/../../skills/notes/scripts" && pwd)"
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

# new-note.sh: with NOTES_WORKSPACE set, the note must appear under
# $NOTES_WORKSPACE/agents/notes/YYYY/MM/ and nowhere near the install dir.
ws="$(mktemp -d)"
out="$(CLAUDECODE=1 NOTES_WORKSPACE="$ws" bash "$NOTES_SCRIPTS/new-note.sh" portability-probe)"
if [[ "$out" == "$ws/agents/notes/"*"-portability-probe.md" && -f "$out" ]]; then
  ok "new-note.sh writes under \$NOTES_WORKSPACE"
else
  bad "new-note.sh wrote to '$out' (expected under $ws/agents/notes/)"
fi
# It must NOT have written inside the install tree.
if find "$NOTES_SCRIPTS/../../.." -path '*/agents/notes/*portability-probe.md' 2>/dev/null | grep -q .; then
  bad "new-note.sh leaked a write into the install dir"
else
  ok "new-note.sh did not write into the install dir"
fi
rm -rf "$ws"

# new-task.sh requires tfq; skip cleanly if absent.
if command -v tfq &>/dev/null; then
  ws="$(mktemp -d)"
  out="$(NOTES_WORKSPACE="$ws" bash "$NOTES_SCRIPTS/new-task.sh" "probe task" --tags probe 2>/dev/null)"
  if [[ "$out" == "$ws/agents/tasks/"* && -f "$out" ]]; then
    ok "new-task.sh writes under \$NOTES_WORKSPACE"
  else
    bad "new-task.sh wrote to '$out' (expected under $ws/agents/tasks/)"
  fi
  rm -rf "$ws"
else
  echo "SKIP: new-task.sh (tfq not on PATH)"
fi

[[ $fail -eq 0 ]]
