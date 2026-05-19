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
TASKS_DIR="$REPO_ROOT/agents/tasks"

[[ $# -ge 1 ]] || { echo "Usage: $0 \"Task title\" [taskmd-add-options...]" >&2; exit 1; }

YYYY=$(date +%Y)
MM=$(date +%m)
SHARD="$TASKS_DIR/$YYYY/$MM"
mkdir -p "$SHARD"

# taskmd add creates file in TASKS_DIR root; capture created filename.
# Field is file_path (not file) in taskmd JSON output.
CREATED=$(cd "$TASKS_DIR" && taskmd add "$@" --format json 2>/dev/null | jq -r '.file_path // empty')

if [[ -z "$CREATED" ]]; then
  echo "error: taskmd add --format json did not return file_path — is jq installed?" >&2
  exit 1
fi

# file_path may be absolute or relative; normalize to just filename
BASENAME=$(basename "$CREATED")
FULLPATH="$TASKS_DIR/$BASENAME"
if [[ ! -f "$FULLPATH" ]]; then
  echo "error: created task file not found at $FULLPATH" >&2
  exit 1
fi

DEST="$SHARD/$BASENAME"
mv "$FULLPATH" "$DEST"
echo "$DEST"
