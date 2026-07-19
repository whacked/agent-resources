#!/usr/bin/env bash
# supersession-repair.sh — reconcile superseded_by (reverse) from supersedes (forward).
#
# The forward `supersedes` edge lives on the immutable successor file and is the
# SOURCE OF TRUTH. Each predecessor's `superseded_by` list is a DERIVED CACHE of
# "who supersedes me", materialized so a human browsing raw files / Obsidian can
# see obsolescence without running a tool. tfq writes each direction independently
# and does NOT infer the inverse — this script is where that inference lives.
#
# It recomputes every predecessor's superseded_by set from `tfq --graph` and, in
# --fix mode, writes it back (plus status: superseded). On any forward/reverse
# disagreement the FORWARD edge wins; the reverse is replaced, never appended.
#
# Usage:
#   supersession-repair.sh --root DIR [--fix] [--no-status]
#     default        check-only; prints DRIFT lines and exits 1 if any found
#     --fix          apply the reconciliation (tfq --set)
#     --no-status    reconcile superseded_by only; do not touch status
#
# Refs are basename-without-.md (how supersedes values are written); tfq resolves
# them by path/basename/seq-stripped basename/id/slug/title.
set -uo pipefail

ROOT=""; FIX=0; SET_STATUS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --fix)  FIX=1; shift ;;
    --no-status) SET_STATUS=0; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "usage: $0 --root DIR [--fix] [--no-status]" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT" ]  || { echo "error: --root DIR required" >&2; exit 2; }
[ -d "$ROOT" ]  || { echo "error: not a directory: $ROOT" >&2; exit 2; }
command -v tfq >/dev/null || { echo "error: tfq not on PATH" >&2; exit 2; }
command -v jq  >/dev/null || { echo "error: jq not on PATH"  >&2; exit 2; }

# Two upfront snapshots (coerce to arrays: tfq emits `null`, not `[]`, when empty).
# `--graph` carries both supersedes and superseded_by edges since tfq 20260719.6865b49.
graph="$(tfq --root "$ROOT" --graph --json 2>/dev/null | jq -c 'if type=="array" then . else [] end' 2>/dev/null)"
[ -n "$graph" ] || graph="[]"
records="$(tfq --root "$ROOT" --list --json 2>/dev/null | jq -c 'if type=="array" then . else [] end' 2>/dev/null)"
[ -n "$records" ] || records="[]"

ref() { local b; b="$(basename "$1")"; printf '%s' "${b%.md}"; }

# predecessors = distinct targets of a forward supersedes edge
mapfile -t preds < <(printf '%s' "$graph" | jq -r '.[] | select(.kind=="fm:supersedes") | .to' | sort -u)

rc=0
for pred in "${preds[@]}"; do
  [ -n "$pred" ] || continue
  predref="$(ref "$pred")"

  # want = successor refs (basename of every file whose supersedes points at pred)
  want="$(printf '%s' "$graph" \
    | jq -r --arg p "$pred" '.[] | select(.kind=="fm:supersedes" and .to==$p) | .from' \
    | while read -r f; do [ -n "$f" ] && ref "$f" && echo; done | sort -u | paste -sd, -)"

  # have = current superseded_by refs, from the same graph snapshot. `.raw` is the
  # literal stored ref, so a dangling entry (which resolves to an empty `.to`) is
  # still surfaced by name and flagged.
  have="$(printf '%s' "$graph" \
    | jq -r --arg p "$pred" '.[] | select(.kind=="fm:superseded_by" and .from==$p) | .raw' \
    | while read -r t; do [ -n "$t" ] && ref "$t" && echo; done | sort -u | paste -sd, -)"

  status="$(printf '%s' "$records" | jq -r --arg p "$pred" '.[] | select(.path==$p) | .status' | head -1)"

  link_bad=0; status_bad=0
  [ "$want" != "$have" ] && link_bad=1
  [ "$SET_STATUS" -eq 1 ] && [ "$status" != "superseded" ] && status_bad=1
  [ "$link_bad" -eq 0 ] && [ "$status_bad" -eq 0 ] && continue

  if [ "$FIX" -eq 1 ]; then
    [ "$link_bad" -eq 1 ] && tfq --root "$ROOT" --set "$pred" --field-list "superseded_by=$want" >/dev/null 2>&1
    [ "$status_bad" -eq 1 ] && tfq --root "$ROOT" --set "$pred" --field "status=superseded" >/dev/null 2>&1
    echo "FIXED $predref  superseded_by=[$want]$([ "$status_bad" -eq 1 ] && echo ' status=superseded')"
  else
    msg="DRIFT $predref"
    [ "$link_bad" -eq 1 ]   && msg="$msg  superseded_by: have=[$have] want=[$want]"
    [ "$status_bad" -eq 1 ] && msg="$msg  status=[$status] want=[superseded]"
    echo "$msg"
    rc=1
  fi
done

exit $rc
