#!/usr/bin/env bash
# new-note.sh — create a date-sharded note with required frontmatter
#
# Usage:
#   new-note.sh <slug>                   # auto-detects agent vs human context
#   new-note.sh <slug> --dest-dir DIR    # explicit destination override
#   new-note.sh <slug> --author NAME     # explicit author override
#   new-note.sh <slug> --edit            # open in $EDITOR after creation
#
# Auto-detection (no flags needed in normal use):
#   CLAUDECODE=1 in env → author=agent, dest=agents/notes/
#   Otherwise           → author=git user.name (or $USER), dest=$PWD
#
# Filename: YYYY-MM-DD.NNN-slug.md  (NNN resets to 001 each day, per dest dir)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

usage() {
  echo "Usage: $0 <slug> [--dest-dir DIR] [--author NAME] [--edit]" >&2
  echo "  slug       lowercase, hyphens only: [a-z0-9-]+" >&2
  echo "  --dest-dir default: agent/notes (agent use) or set to any dir (human use)" >&2
  echo "  --author   default: agent" >&2
  echo "  --edit     open file in \$EDITOR after creation" >&2
  exit 1
}

[[ $# -ge 1 ]] || usage

SLUG="$1"; shift

# Detect agent vs human: CLAUDECODE=1 is set by Claude Code in agent shells
if [[ -n "${CLAUDECODE:-}" ]]; then
  DEFAULT_AUTHOR="agent"
  DEFAULT_DEST="$REPO_ROOT/orgzly/agents/notes"
else
  DEFAULT_AUTHOR=$(git config user.name 2>/dev/null || echo "${USER:-human}")
  DEFAULT_DEST="$PWD"
fi

DEST_DIR="$DEFAULT_DEST"
AUTHOR="$DEFAULT_AUTHOR"
DO_EDIT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest-dir) DEST_DIR="$2"; shift 2 ;;
    --author)   AUTHOR="$2";   shift 2 ;;
    --edit)     DO_EDIT=1;     shift   ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

if ! echo "$SLUG" | grep -qE '^[a-z0-9-]+$'; then
  echo "error: slug must match [a-z0-9-]+ (lowercase, hyphens only)" >&2
  exit 1
fi

TODAY=$(date +%Y-%m-%d)
YYYY=$(date +%Y)
MM=$(date +%m)
DD=$(date +%d)

DAY_DIR="$DEST_DIR/$YYYY/$MM/$DD"
mkdir -p "$DAY_DIR"

# Compute next NNN for today in this dest dir
EXISTING=$(find "$DAY_DIR" -maxdepth 1 -name "*.md" 2>/dev/null | grep -cE "/[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]{3}-" || true)
NNN=$(printf "%03d" $((EXISTING + 1)))

OUTFILE="$DAY_DIR/$TODAY.$NNN-$SLUG.md"

if [[ -f "$OUTFILE" ]]; then
  echo "error: file already exists: $OUTFILE" >&2
  exit 1
fi

cat > "$OUTFILE" << FRONTMATTER
---
date: $TODAY
author: $AUTHOR
slug: $SLUG
source_notes: []
tags: []
---

# ${SLUG//-/ }

<summary>

# Background

<context>

# Findings

<notes>

# Next steps

<open questions>
FRONTMATTER

echo "$OUTFILE"

if [[ $DO_EDIT -eq 1 ]]; then
  exec "${EDITOR:-vim}" "$OUTFILE"
fi
