#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEMA="$(cd "$SCRIPTS_DIR/.." && pwd)/schemas/reports.cue.template.md"
VALIDATOR="$SCRIPTS_DIR/validate-frontmatter.sh"

pass=0; fail=0

check() {
    local desc="$1" expect="$2"; shift 2
    if [[ "$expect" == "pass" ]]; then
        if "$@" > /dev/null 2>&1; then
            echo "PASS: $desc"; (( pass++ )) || true
        else
            echo "FAIL: $desc (expected success, got failure)"; (( fail++ )) || true
        fi
    else
        if ! "$@" > /dev/null 2>&1; then
            echo "PASS: $desc"; (( pass++ )) || true
        else
            echo "FAIL: $desc (expected failure, got success)"; (( fail++ )) || true
        fi
    fi
}

# validate-frontmatter.sh
_tmpdir="$(mktemp -d)"
VALID_REPORT="$_tmpdir/2026-04-22.001-valid-report.md"
cp "$TESTS_DIR/validate-sample.md" "$VALID_REPORT"
trap 'rm -rf "$_tmpdir"' EXIT

check "valid document passes"        pass "$VALIDATOR" "$SCHEMA" "$VALID_REPORT"
check "invalid content fails"        fail "$VALIDATOR" "$SCHEMA" "$TESTS_DIR/validate-sample-invalid.md"
check "bad filename fails"           fail "$VALIDATOR" "$SCHEMA" "$TESTS_DIR/validate-sample.md"

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
