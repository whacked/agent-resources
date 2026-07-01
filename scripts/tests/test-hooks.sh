#!/usr/bin/env bash
# Verify the SessionStart hook emits valid JSON additionalContext carrying the
# absolute install root and the routing table. Exit 0 = pass.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0; ok(){ echo "PASS: $1"; }; bad(){ echo "FAIL: $1"; fail=1; }
command -v jq >/dev/null || { echo "SKIP: jq not on PATH"; exit 0; }

out="$(CLAUDE_PLUGIN_ROOT="$ROOT" bash "$ROOT/hooks/session-start" 2>&1)"
if echo "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ok "session-start emits valid JSON additionalContext"
  ctx="$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext')"
  echo "$ctx" | grep -q "installed at: $ROOT" && ok "context carries absolute install root" || bad "no install root"
  echo "$ctx" | grep -q "ar:notes" && ok "context carries routing table" || bad "routing table missing"
else
  bad "invalid hook JSON: $out"
fi
[[ $fail -eq 0 ]]
