#!/usr/bin/env bash
# new-task.sh — create a taskmd task in the sharded tasks/ hierarchy
#
# Usage:
#   new-task.sh "Task title" [taskmd-add-options...]
#
# Creates task in agents/tasks/YYYY/MM/NNN-slug.md
# All extra args are passed through to `taskmd add`.
# Requires: taskmd in PATH, run from anywhere in the repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TASKS_DIR="$REPO_ROOT/orgzly/agents/tasks"

[[ $# -ge 1 ]] || { echo "Usage: $0 \"Task title\" [taskmd-add-options...]" >&2; exit 1; }

YYYY=$(date +%Y)
MM=$(date +%m)
SHARD="$TASKS_DIR/$YYYY/$MM"
mkdir -p "$SHARD"

# taskmd add creates file in TASKS_DIR root; capture created filename
CREATED=$(cd "$TASKS_DIR" && taskmd add "$@" --format json 2>/dev/null | jq -r '.file // empty')

if [[ -z "$CREATED" ]]; then
  # Fallback: taskmd add without --format json, find newest file
  BEFORE=$(ls "$TASKS_DIR"/*.md 2>/dev/null | sort)
  cd "$TASKS_DIR" && taskmd add "$@"
  AFTER=$(ls "$TASKS_DIR"/*.md 2>/dev/null | sort)
  CREATED=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | head -1)
fi

if [[ -z "$CREATED" || ! -f "$TASKS_DIR/$CREATED" ]]; then
  echo "error: could not identify created task file" >&2
  exit 1
fi

BASENAME=$(basename "$CREATED")
DEST="$SHARD/$BASENAME"
mv "$TASKS_DIR/$BASENAME" "$DEST"
echo "$DEST"
