#!/usr/bin/env bash
set -euo pipefail

# Usage: validate-frontmatter.sh <template.md> <document.md>
#
# Validates <document.md> against <template.md>:
#   1. YAML frontmatter is validated against the CUE schema in the template's
#      first ```cue block.
#   2. H1 headings must appear in the order defined by the template; sections
#      with alternatives (# <A | B | C>) accept any one match, case-insensitive.

usage() {
    echo "Usage: $0 <template.md> <document.md>" >&2
    exit 1
}

# Extract H1 lines from a file's body (skipping any leading ```cue block and frontmatter).
extract_h1_lines() {
    local file="$1"
    awk '
        /^```cue$/ { skip=1; next }
        skip && /^```$/ { skip=0; next }
        skip { next }
        NR==1 && /^---$/ { fm=1; next }
        fm && /^---$/ { fm=0; next }
        fm { next }
        /^# / { print }
    ' "$file"
}

validate_frontmatter() {
    local template="$1" document="$2"

    # tfq bundles the cuelang library: it reads the ```cue block from the
    # template itself and validates the document's frontmatter against it with
    # `cue vet` semantics. No `cue` binary, no manual schema/yaml extraction.
    if ! command -v tfq &>/dev/null; then
        echo "error: tfq not found on PATH — required for frontmatter validation" >&2
        return 1
    fi

    local out rc
    out=$(tfq --validate "$document" --schema "$template" 2>&1); rc=$?
    [[ $rc -eq 0 ]] || echo "$out" >&2
    return $rc
}

validate_titles() {
    local template="$1" document="$2"
    local ok=0

    local patterns=() headings=()
    while IFS= read -r line; do patterns+=("$line"); done < <(extract_h1_lines "$template")
    while IFS= read -r line; do headings+=("$line"); done < <(extract_h1_lines "$document")

    local n="${#patterns[@]}" m="${#headings[@]}"

    if [[ "$m" -ne "$n" ]]; then
        echo "error: expected $n H1 headings, found $m" >&2
        ok=1
    fi

    local i
    for (( i=0; i < n && i < m; i++ )); do
        # Template pattern looks like: "# <A | B | C>" or "# <title>"
        local inner actual
        inner=$(echo "${patterns[$i]}" | sed 's/^# <//; s/>$//')
        actual="${headings[$i]#\# }"

        if [[ "$inner" == *"|"* ]]; then
            # Build alternation pattern: "A | B | C" → "A|B|C"
            local grep_pat="${inner// | /|}"
            if ! echo "$actual" | grep -qiE "^(${grep_pat})$"; then
                echo "error: heading $((i+1)): expected one of [${inner}], got '${actual}'" >&2
                ok=1
            fi
        else
            # Free-form slot (e.g. <title>) — just require non-empty
            if [[ -z "$actual" ]]; then
                echo "error: heading $((i+1)): title must not be empty" >&2
                ok=1
            fi
        fi
    done

    return $ok
}

[[ $# -eq 2 ]] || usage

TEMPLATE="$1"
DOCUMENT="$2"

[[ -f "$TEMPLATE" ]] || { echo "error: template not found: '$TEMPLATE'" >&2; exit 1; }
[[ -f "$DOCUMENT" ]] || { echo "error: document not found: '$DOCUMENT'" >&2; exit 1; }

validate_filename() {
    local document="$1"
    local base; base=$(basename "$document")
    if ! echo "$base" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]{3}-[a-z0-9-]+\.md$'; then
        echo "error: filename '$base' must match YYYY-MM-DD.NNN-slug.md" >&2
        return 1
    fi
}

fm_ok=0; title_ok=0; fn_ok=0
validate_frontmatter "$TEMPLATE" "$DOCUMENT" || fm_ok=1
validate_titles       "$TEMPLATE" "$DOCUMENT" || title_ok=1
validate_filename              "$DOCUMENT" || fn_ok=1

if [[ $((fm_ok + title_ok + fn_ok)) -eq 0 ]]; then
    echo "ok: '$DOCUMENT' is valid"
else
    exit 1
fi
