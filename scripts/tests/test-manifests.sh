#!/usr/bin/env bash
# Manifest structure + version-sync across all four harness manifests.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0; ok(){ echo "PASS: $1"; }; bad(){ echo "FAIL: $1"; fail=1; }
command -v jq >/dev/null || { echo "SKIP: jq not on PATH"; exit 0; }

ref="$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)"
[[ -n "$ref" && "$ref" != "null" ]] && ok "claude plugin.json version present ($ref)" || bad "claude plugin.json version missing"

declare -A GET=(
  [marketplace]='.plugins[0].version|.claude-plugin/marketplace.json'
  [codex]='.version|.codex-plugin/plugin.json'
  [gemini]='.version|gemini-extension.json'
)
for k in marketplace codex gemini; do
  q="${GET[$k]%%|*}"; f="${GET[$k]##*|}"
  v="$(jq -r "$q" "$ROOT/$f" 2>/dev/null)"
  [[ "$v" == "$ref" ]] && ok "$k version matches ($ref)" || bad "$k version '$v' != '$ref' ($f)"
done

[[ "$(jq -r '.plugins[0].name' "$ROOT/.claude-plugin/marketplace.json")" == "ar" ]] \
  && ok "marketplace plugin name is 'ar'" || bad "marketplace plugin name != ar"
[[ "$(jq -r '.name' "$ROOT/.codex-plugin/plugin.json")" == "ar" ]] \
  && ok "codex plugin name is 'ar'" || bad "codex plugin name != ar"
[[ "$(jq -r '.skills' "$ROOT/.codex-plugin/plugin.json")" == "./skills/" ]] \
  && ok "codex skills -> ./skills/" || bad "codex skills field wrong"
[[ "$(jq -r '.contextFileName' "$ROOT/gemini-extension.json")" == "GEMINI.md" ]] \
  && ok "gemini contextFileName is GEMINI.md" || bad "gemini contextFileName wrong"
grep -q 'using-ar' "$ROOT/GEMINI.md" && ok "GEMINI.md includes using-ar" || bad "GEMINI.md missing using-ar include"

[[ $fail -eq 0 ]]
