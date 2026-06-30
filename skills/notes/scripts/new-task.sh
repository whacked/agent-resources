#!/usr/bin/env bash
# new-task.sh — create a tfq task record in the sharded tasks/ hierarchy
#
# Usage:
#   new-task.sh "Task title" [--priority P] [--effort E] [--parent REF] \
#               [--depends-on REF[,REF]] [--tags a,b,c] [--context FILE]
#
# Creates agents/tasks/YYYY/MM/NNN-slug.md. tfq handles the YYYY/MM sharding
# and the padded sequential id, so there is no add|mv dance and no per-CWD
# config to walk up to — the tasks collection is named explicitly via --root.
# Requires: tfq on PATH. Run from anywhere in the repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TASKS_DIR="$REPO_ROOT/agents/tasks"

usage() {
  echo "Usage: $0 \"Task title\" [--priority P] [--effort E] [--parent REF] [--depends-on REF[,REF]] [--tags a,b,c] [--context FILE]" >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
command -v tfq &>/dev/null || { echo "error: tfq not found on PATH — required for task creation" >&2; exit 1; }
command -v jq  &>/dev/null || { echo "error: jq not found on PATH" >&2; exit 1; }

TITLE="$1"; shift

# Translate the skill's friendly flags into tfq --task flags.
#   --tags a,b   → repeated --tag a --tag b
#   --context F  → --field context=F   (provenance link to the source note)
#   --template   → ignored: tfq records have no body-section templates
TFQ_ARGS=(--root "$TASKS_DIR" --json --task --title "$TITLE")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --priority)   TFQ_ARGS+=(--priority "$2");      shift 2 ;;
    --effort)     TFQ_ARGS+=(--effort "$2");        shift 2 ;;
    --parent)     TFQ_ARGS+=(--parent "$2");        shift 2 ;;
    --depends-on) TFQ_ARGS+=(--depends-on "$2");    shift 2 ;;
    --context)    TFQ_ARGS+=(--field "context=$2"); shift 2 ;;
    --tags)       IFS=',' read -ra _tags <<< "$2"
                  for t in "${_tags[@]}"; do TFQ_ARGS+=(--tag "$t"); done
                  shift 2 ;;
    --template)   shift 2 ;;
    *) echo "error: unknown option: $1" >&2; usage ;;
  esac
done

mkdir -p "$TASKS_DIR"
CREATED=$(tfq "${TFQ_ARGS[@]}" | jq -r '.path // empty')

if [[ -z "$CREATED" ]]; then
  echo "error: tfq --task did not return a path" >&2
  exit 1
fi

echo "$TASKS_DIR/$CREATED"
