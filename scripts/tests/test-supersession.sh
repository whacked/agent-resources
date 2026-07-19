#!/usr/bin/env bash
# Supersession feature suite:
#   - both schemas accept superseded_by as a list and reject a scalar
#   - the doctor supersession janitor detects missing reverse links, --fix
#     materializes the full (fork-aware) set + status, is idempotent, and
#     exits 0 on a collection with no supersession.
# Exit 0 = all pass.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPORTS_SCHEMA="$ROOT/schemas/reports.cue.template.md"
NOTES_SCHEMA="$ROOT/skills/notes/schemas/notes.cue.template.md"
REPAIR="$ROOT/skills/doctor/scripts/supersession-repair.sh"
fail=0
ok()  { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

if ! command -v tfq &>/dev/null || ! command -v jq &>/dev/null; then
  echo "SKIP: supersession suite (tfq/jq not on PATH)"; exit 0
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mk() { printf '%s\n' "$@"; }

# --- schema: superseded_by list validates; scalar is rejected ---
mk '---' 'id: r' 'status: superseded' 'date: 2026-07-19' 'intent: normative' 'author: agent' \
   'superseded_by: [2026-07-19.001-x]' '---' '# R' 'b' > "$tmp/rep-ok.md"
tfq --validate "$tmp/rep-ok.md" --schema "$REPORTS_SCHEMA" >/dev/null 2>&1 \
  && ok "reports schema: superseded_by list validates" || bad "reports schema rejected a valid superseded_by list"

mk '---' 'id: r' 'status: accepted' 'date: 2026-07-19' 'author: agent' \
   'superseded_by: not-a-list' '---' '# R' 'b' > "$tmp/rep-bad.md"
tfq --validate "$tmp/rep-bad.md" --schema "$REPORTS_SCHEMA" >/dev/null 2>&1 \
  && bad "reports schema: scalar superseded_by should FAIL" || ok "reports schema: scalar superseded_by rejected"

mk '---' 'date: 2026-07-19' 'author: agent' 'slug: n' \
   'superseded_by: [2026-07-19.002-y]' 'status: superseded' '---' '# N' 'b' > "$tmp/note-ok.md"
tfq --validate "$tmp/note-ok.md" --schema "$NOTES_SCHEMA" >/dev/null 2>&1 \
  && ok "notes schema: superseded_by list + status validates" || bad "notes schema rejected valid superseded_by/status"

# --- janitor: drift -> fix -> clean, idempotent, fork-aware ---
col="$tmp/col"; mkdir -p "$col"
mk '---' 'id: old' 'status: accepted' 'date: 2026-05-01' 'author: agent' '---' '# old' > "$col/2026-05-01.001-old.md"
mk '---' 'id: a' 'status: accepted' 'date: 2026-07-19' 'author: agent' 'supersedes: 2026-05-01.001-old' '---' '# a' > "$col/2026-07-19.001-a.md"
mk '---' 'id: b' 'status: accepted' 'date: 2026-07-19' 'author: agent' 'supersedes: 2026-05-01.001-old' '---' '# b' > "$col/2026-07-19.002-b.md"

bash "$REPAIR" --root "$col" >/dev/null 2>&1 && bad "janitor should report drift (exit 1)" || ok "janitor detects missing reverse links"
bash "$REPAIR" --root "$col" --fix >/dev/null 2>&1 && ok "janitor --fix applies" || bad "janitor --fix errored"
bash "$REPAIR" --root "$col" >/dev/null 2>&1 && ok "janitor clean after fix (exit 0)" || bad "janitor still drifting after fix"

got="$(tfq --root "$col" --show 2026-05-01.001-old --frontmatter --json 2>/dev/null | jq -c '[(.superseded_by|sort), .status]')"
[ "$got" = '[["2026-07-19.001-a","2026-07-19.002-b"],"superseded"]' ] \
  && ok "janitor materialized fork set + status" || bad "unexpected reverse state: $got"

bash "$REPAIR" --root "$col" --fix >/dev/null 2>&1
bash "$REPAIR" --root "$col" >/dev/null 2>&1 && ok "janitor idempotent" || bad "janitor not idempotent"

# --- a dangling reverse ref (points nowhere) is detected and cleaned ---
tfq --root "$col" --set 2026-05-01.001-old --field-list superseded_by=2026-07-19.001-a,2026-07-19.002-b,ghost-ref-nowhere >/dev/null 2>&1
bash "$REPAIR" --root "$col" >/dev/null 2>&1 && bad "janitor should flag a dangling reverse ref" || ok "janitor detects dangling reverse ref"
bash "$REPAIR" --root "$col" --fix >/dev/null 2>&1
got2="$(tfq --root "$col" --show 2026-05-01.001-old --frontmatter --json 2>/dev/null | jq -c '(.superseded_by|sort)')"
[ "$got2" = '["2026-07-19.001-a","2026-07-19.002-b"]' ] && ok "janitor cleaned dangling ref" || bad "dangling ref not cleaned: $got2"

# --- empty / no-supersession collection exits 0 ---
empty="$tmp/empty"; mkdir -p "$empty"
mk '---' 'id: z' 'date: 2026-07-19' 'author: agent' '---' '# z' 'body' > "$empty/z.md"
bash "$REPAIR" --root "$empty" >/dev/null 2>&1 && ok "janitor exit 0 on no-supersession collection" || bad "janitor nonzero on empty collection"

[[ $fail -eq 0 ]]
