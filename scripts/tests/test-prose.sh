#!/usr/bin/env bash
# Prose linter: forbid stale path/binary references in skill bodies + guides.
# Exit 0 = clean.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FILES=(
  "$ROOT/skills/notes/SKILL.md"
  "$ROOT/skills/synthesize/SKILL.md"
  "$ROOT/docs/agent-guides/reports.md"
  "$ROOT/docs/agent-guides/cpd-data.md"
)
# Each entry: <regex>\t<human reason>
PATTERNS=(
  'agent-resources/(skills|artifacts|docs|scripts|schemas|CLAUDE|AGENTS)	hardcoded agent-resources/ path — use skill-relative reads or $NOTES_WORKSPACE'
  '\btaskmd\b	retired binary taskmd — superseded by tfq'
  '(^|[^[:alnum:]])ov [a-z]	retired binary ov — superseded by tfq'
  'reports/YYYY/MM/DD	day-sharded report path — reports are YYYY/MM now'
)

fail=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "FAIL: missing $f"; fail=1; continue; }
  for entry in "${PATTERNS[@]}"; do
    rx="${entry%%$'\t'*}"; why="${entry##*$'\t'}"
    if grep -nEq "$rx" "$f"; then
      echo "FAIL: ${f#"$ROOT"/} matches /$rx/ — $why"
      grep -nE "$rx" "$f" | sed 's/^/      /'
      fail=1
    fi
  done
done
[[ $fail -eq 0 ]] && echo "PASS: prose clean"
[[ $fail -eq 0 ]]
