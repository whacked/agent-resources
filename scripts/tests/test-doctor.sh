#!/usr/bin/env bash
# Smoke test for doctor in plugin layout: against a fresh workspace it should
# (a) run without crashing, (b) report the workspace it resolved, (c) PASS the
# required-binary checks when tfq/rg/jq are present. Exit 0 = pass.
set -uo pipefail

CHECK="$(cd "$(dirname "$0")/../../skills/doctor/scripts" && pwd)/check.sh"
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

ws="$(mktemp -d)"
mkdir -p "$ws/agents/notes" "$ws/agents/tasks"
out="$(NOTES_WORKSPACE="$ws" bash "$CHECK" 2>&1)"; rc=$?

echo "$out" | grep -q "Workspace: $ws" && ok "doctor reports resolved workspace" || bad "no workspace line"
echo "$out" | grep -q "plugin" && ok "doctor detects plugin layout (install dir outside workspace)" \
  || bad "layout not reported as plugin (got: $(echo "$out" | grep -i layout))"
if command -v tfq &>/dev/null && command -v rg &>/dev/null && command -v jq &>/dev/null; then
  [[ $rc -eq 0 ]] && ok "doctor exits 0 when required bins present + dirs exist" \
    || bad "doctor exited $rc despite required bins + dirs (out below)"
  [[ $rc -eq 0 ]] || echo "$out"
else
  echo "SKIP: exit-code assertion (a required binary is missing)"
fi
rm -rf "$ws"
[[ $fail -eq 0 ]]
