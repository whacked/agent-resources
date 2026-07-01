#!/usr/bin/env bash
# Self-contained unit tests for scripts/lib/workspace.sh. Exit 0 = all pass.
set -uo pipefail

LIB="$(cd "$(dirname "$0")/../lib" && pwd)/workspace.sh"
# shellcheck source=/dev/null
source "$LIB"

fail=0
assert_eq() { # desc expected actual
  if [[ "$2" == "$3" ]]; then echo "PASS: $1"; else echo "FAIL: $1 (expected '$2', got '$3')"; fail=1; fi
}

# 1. Explicit NOTES_WORKSPACE wins over everything.
assert_eq "env var wins" "/tmp/ws-explicit" "$(NOTES_WORKSPACE=/tmp/ws-explicit resolve_workspace)"

# 2. AGENTS_SUBDIR override is honored by agents_dir.
assert_eq "agents_dir uses subdir override" "/tmp/ws/out" \
  "$(NOTES_WORKSPACE=/tmp/ws AGENTS_SUBDIR=out agents_dir)"

# 3. agents_dir default subdir is 'agents'.
assert_eq "agents_dir default subdir" "/tmp/ws/agents" \
  "$(NOTES_WORKSPACE=/tmp/ws agents_dir)"

# 4. With no env var, inside a git repo → git toplevel.
gitdir="$(mktemp -d)"; ( cd "$gitdir" && git init -q )
assert_eq "git toplevel when no env var" "$gitdir" \
  "$(cd "$gitdir" && unset NOTES_WORKSPACE; resolve_workspace)"
rm -rf "$gitdir"

# 5. With no env var and not a git repo → $PWD.
nogit="$(mktemp -d)"
assert_eq "pwd fallback outside git" "$nogit" \
  "$(cd "$nogit" && unset NOTES_WORKSPACE; resolve_workspace)"
rm -rf "$nogit"

[[ $fail -eq 0 ]]
