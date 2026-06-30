#!/usr/bin/env bash
# validate-note.sh — validate a note file against the notes schema
#
# Usage:
#   validate-note.sh <file.md>           # validate one file
#   validate-note.sh agent/notes/        # validate all .md files under a dir
#
# Checks:
#   1. Filename matches YYYY-MM-DD.NNN-slug.md
#   2. Path is under YYYY/MM/DD/ sharding
#   3. YAML frontmatter validates against skills/notes/schemas/notes.cue.template.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SCHEMA="$SKILL_DIR/schemas/notes.cue.template.md"
VALIDATOR="$(cd "$SCRIPT_DIR/../../.." && pwd)/scripts/validate-frontmatter.sh"

[[ $# -ge 1 ]] || { echo "Usage: $0 <file.md|dir>" >&2; exit 1; }

TARGET="$1"
FAIL=0

validate_one() {
  local file="$1"
  local base dir ok=0

  base=$(basename "$file")
  dir=$(dirname "$file")

  # 1. Filename convention
  if ! echo "$base" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]{3}-[a-z0-9-]+\.md$'; then
    echo "FAIL  filename: $file"
    echo "      expected: YYYY-MM-DD.NNN-slug.md"
    ok=1
  fi

  # 2. Path sharding: must end in YYYY/MM/DD
  if ! echo "$dir" | grep -qE '/[0-9]{4}/[0-9]{2}$'; then
    echo "FAIL  path: $file"
    echo "      expected path ending: YYYY/MM/"
    ok=1
  fi

  # 3. Frontmatter — requires tfq (bundles cuelang); degrades to required-field check if absent
  if command -v tfq &>/dev/null && [[ -x "$VALIDATOR" ]]; then
    fm_out=$(bash "$VALIDATOR" "$SCHEMA" "$file" 2>&1) || {
      echo "FAIL  frontmatter: $file"
      echo "$fm_out" | sed 's/^/      /'
      ok=1
    }
  else
    # Manual check: required fields
    for field in date author slug; do
      if ! grep -q "^${field}:" "$file" 2>/dev/null; then
        echo "FAIL  frontmatter missing '$field': $file"
        ok=1
      fi
    done
  fi

  [[ $ok -eq 0 ]] && echo "PASS  $file"
  return $ok
}

if [[ -f "$TARGET" ]]; then
  validate_one "$TARGET" || FAIL=1
elif [[ -d "$TARGET" ]]; then
  while IFS= read -r f; do
    validate_one "$f" || FAIL=1
  done < <(find "$TARGET" -name "*.md" | sort)
else
  echo "error: not a file or directory: $TARGET" >&2
  exit 1
fi

exit $FAIL
