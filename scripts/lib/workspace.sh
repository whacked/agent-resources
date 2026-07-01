#!/usr/bin/env bash
# workspace.sh — single source of truth for resolving where agent WRITES go.
#
# SOURCE this file; do not execute it. It defines two functions:
#
#   resolve_workspace  prints the workspace root, resolved in this order:
#                        1. $NOTES_WORKSPACE (if non-empty)
#                        2. git rev-parse --show-toplevel (if inside a repo)
#                        3. $PWD
#
#   agents_dir         prints <workspace>/<AGENTS_SUBDIR:-agents>
#
# Reads of bundled resources (schemas, validators, guides) must NOT use these —
# those resolve relative to the reading script. These are for WRITE anchoring only.

resolve_workspace() {
  if [[ -n "${NOTES_WORKSPACE:-}" ]]; then
    printf '%s\n' "${NOTES_WORKSPACE%/}"
    return 0
  fi
  local top
  if top="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$top" ]]; then
    printf '%s\n' "$top"
    return 0
  fi
  printf '%s\n' "$PWD"
}

agents_dir() {
  printf '%s/%s\n' "$(resolve_workspace)" "${AGENTS_SUBDIR:-agents}"
}
