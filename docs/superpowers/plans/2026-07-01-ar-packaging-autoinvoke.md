# AR Packaging & Auto-Invocation — Implementation Plan (Plan 2 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `agent-resources` repo installable as the single bundled `ar` plugin and reliably auto-invoking across harnesses — via a `SessionStart` hook that injects an `ar:using-ar` routing index — with committed best-effort manifests for Codex/Gemini/OpenCode, `doctor` staleness reporting, and install docs.

**Architecture:** One marketplace (`agent-resources`) ships one plugin (`ar`); skills surface as `ar:<skill>`. A `SessionStart` hook cats `skills/using-ar/SKILL.md`, prefixes the absolute install root (`$CLAUDE_PLUGIN_ROOT`), and emits it as `additionalContext` so the routing index is present every session and bundled-file references resolve. Codex/Gemini route the same file through their own always-on channels; OpenCode/standalone-Codex discover skills via a `.agents/skills` symlink. One version string is mirrored across all manifests and guarded by a test.

**Tech Stack:** Bash, JSON manifests, `jq`, `git`. Hook wiring modeled verbatim on the verified superpowers plugin (`~/.claude/plugins/cache/claude-plugins-official/superpowers/6.0.3/hooks/`).

**Prerequisite:** Plan 1 (`2026-07-01-ar-path-portability.md`) must be complete — this plan relies on `scripts/lib/workspace.sh`, `dependencies.json`, and the rewritten `doctor`.

## Global Constraints

- All shell scripts start with `#!/usr/bin/env bash` and `set -euo pipefail` (the hook scripts; `doctor` keeps `set -uo pipefail`).
- One source-of-truth version string, value `1.0.0`, mirrored verbatim into `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (`.plugins[0].version`), `.codex-plugin/plugin.json`, and `gemini-extension.json`. A version-sync test fails on drift.
- The plugin `name` is `ar` in every harness manifest (it is the skill namespace). The marketplace `name` is `agent-resources`.
- `${CLAUDE_PLUGIN_ROOT}` / `${PLUGIN_ROOT}` appear only in hook manifests/scripts, never in skill bodies.
- Skill bodies reference bundled files by extension-relative paths; the hook supplies the absolute root at injection time.
- Commit after every task. Branch is `ar-plugin-packaging`.
- Owner identity in manifests: name `whacked`, email `directedglaph@gmail.com`, repo `https://github.com/whacked/agent-resources`.

---

### Task 1: Claude Code packaging manifest

**Files:**
- Create: `.claude-plugin/marketplace.json`
- Create: `.claude-plugin/plugin.json`

**Interfaces:**
- Produces: marketplace `agent-resources` → plugin `ar` at `source: "./"`, version `1.0.0`. Consumed by Task 4's `test-manifests.sh`.

- [ ] **Step 1: Create `.claude-plugin/marketplace.json`**

```json
{
  "name": "agent-resources",
  "owner": { "name": "whacked", "email": "directedglaph@gmail.com" },
  "plugins": [
    {
      "name": "ar",
      "source": "./",
      "description": "Notes, tasks, synthesis, reports, and search skills for AI agents (namespaced ar:*).",
      "version": "1.0.0"
    }
  ]
}
```

- [ ] **Step 2: Create `.claude-plugin/plugin.json`**

```json
{
  "name": "ar",
  "description": "Notes, tasks, synthesis, reports, and search skills for AI agents (namespaced ar:*).",
  "version": "1.0.0",
  "author": { "name": "whacked", "email": "directedglaph@gmail.com" },
  "homepage": "https://github.com/whacked/agent-resources",
  "repository": "https://github.com/whacked/agent-resources",
  "license": "MIT",
  "keywords": ["skills", "notes", "synthesis", "reports", "search"]
}
```

- [ ] **Step 3: Verify both are valid JSON and name is `ar`**

Run:
```bash
jq -e '.plugins[0].name == "ar" and .name == "agent-resources"' .claude-plugin/marketplace.json
jq -e '.name == "ar" and .version == "1.0.0"' .claude-plugin/plugin.json
```
Expected: both print `true`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/
git commit -m "[ai] add Claude Code packaging: marketplace agent-resources -> plugin ar"
```

---

### Task 2: `ar:using-ar` routing index skill

**Files:**
- Create: `skills/using-ar/SKILL.md`

**Interfaces:**
- Produces: the routing index injected by the hook (Task 3) and `@`-included by Gemini (Task 4). Must have YAML frontmatter `name: using-ar` + `description:`, and the intent→target table.

- [ ] **Step 1: Create `skills/using-ar/SKILL.md`**

```markdown
---
name: using-ar
description: Routing index for the ar skills bundle — read this to send a request to the right ar skill or guide (notes/tasks, synthesis, reports, CPD data, search, setup checks).
---

# using-ar — routing index for the ar bundle

The `ar` bundle installs as one extension. Its skills surface as `ar:notes`, `ar:synthesize`, `ar:doctor`, `ar:tfq`, `ar:ck`, `ar:audit-skills`. Bundled files named below (guides, schemas, scripts) are **relative to this extension's root** — the SessionStart hook prints that absolute root above this text. All agent **writes** go under `$NOTES_WORKSPACE` (resolved env → git toplevel → CWD by `scripts/lib/workspace.sh`).

## Route by intent

| If the user wants to… | Do this |
|---|---|
| create / find / validate a note or task | invoke `ar:notes` |
| synthesize journals, meetings, or fragments into something coherent | invoke `ar:synthesize` |
| record a decision, architectural/schema change, or write a formal report or ADR | read `docs/agent-guides/reports.md`; write to `$NOTES_WORKSPACE/artifacts/reports/YYYY/MM/`; validate with `scripts/validate-frontmatter.sh schemas/reports.cue.template.md <file>` |
| accumulate append-only structured records (API JSONL ingestion, ETL, data generation) | read `docs/agent-guides/cpd-data.md`; write to `$NOTES_WORKSPACE/artifacts/data/<scope>/<dataset>.cpd.yaml` |
| keyword / structured / task-graph search over markdown | invoke `ar:tfq` |
| semantic / concept / hybrid search | invoke `ar:ck` |
| check / verify / repair the setup, or preflight dependencies | invoke `ar:doctor` |
| audit or review skills | invoke `ar:audit-skills` |

Reports are prose markdown — not a skill, never CPD-formatted. CPD is for append-only data, never the path for writing reports.
```

- [ ] **Step 2: Verify frontmatter + routing rows present**

Run:
```bash
grep -q '^name: using-ar' skills/using-ar/SKILL.md && \
grep -q 'ar:notes' skills/using-ar/SKILL.md && \
grep -q 'artifacts/reports/YYYY/MM/' skills/using-ar/SKILL.md && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add skills/using-ar/
git commit -m "[ai] add ar:using-ar routing index skill"
```

---

### Task 3: SessionStart hooks (Claude Code + Codex)

**Files:**
- Create: `hooks/hooks.json`, `hooks/hooks-codex.json`, `hooks/run-hook.cmd`, `hooks/session-start`, `hooks/session-start-codex`
- Test: `scripts/tests/test-hooks.sh`

**Interfaces:**
- Consumes: `skills/using-ar/SKILL.md` (Task 2).
- Produces: a `SessionStart` `additionalContext` JSON payload carrying the absolute install root + the routing index. Claude auto-discovers `hooks/hooks.json` at the plugin root (verified: superpowers ships exactly this, with no `hooks` key in `plugin.json`).

- [ ] **Step 1: Write the failing test** — `scripts/tests/test-hooks.sh`

```bash
#!/usr/bin/env bash
# Verify the SessionStart hook emits valid JSON additionalContext carrying the
# absolute install root and the routing table. Exit 0 = pass.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0; ok(){ echo "PASS: $1"; }; bad(){ echo "FAIL: $1"; fail=1; }
command -v jq >/dev/null || { echo "SKIP: jq not on PATH"; exit 0; }

out="$(CLAUDE_PLUGIN_ROOT="$ROOT" bash "$ROOT/hooks/session-start" 2>&1)"
if echo "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ok "session-start emits valid JSON additionalContext"
  ctx="$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext')"
  echo "$ctx" | grep -q "installed at: $ROOT" && ok "context carries absolute install root" || bad "no install root"
  echo "$ctx" | grep -q "ar:notes" && ok "context carries routing table" || bad "routing table missing"
else
  bad "invalid hook JSON: $out"
fi
[[ $fail -eq 0 ]]
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash scripts/tests/test-hooks.sh`
Expected: FAIL — `hooks/session-start` does not exist yet.

- [ ] **Step 3: Create `hooks/run-hook.cmd`** (cross-platform polyglot wrapper, verbatim pattern from superpowers)

```bash
: << 'CMDBLOCK'
@echo off
REM Cross-platform polyglot wrapper for hook scripts.
REM On Windows: cmd.exe runs the batch portion, which finds and calls bash.
REM On Unix: the shell interprets this as a script (: is a no-op in bash).
REM Usage: run-hook.cmd <script-name> [args...]

if "%~1"=="" (
    echo run-hook.cmd: missing script name >&2
    exit /b 1
)
set "HOOK_DIR=%~dp0"
if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
where bash >nul 2>nul
if %ERRORLEVEL% equ 0 (
    bash "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
exit /b 0
CMDBLOCK

# Unix: run the named script directly
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$1"
shift
exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
```

- [ ] **Step 4: Create `hooks/session-start`**

```bash
#!/usr/bin/env bash
# SessionStart hook for the ar plugin — injects the using-ar routing index,
# prefixed with the absolute extension root so bundled-file references resolve.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

routing="$(cat "$PLUGIN_ROOT/skills/using-ar/SKILL.md" 2>&1 || echo "Error reading using-ar SKILL.md")"

escape_for_json() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

full="<ar-routing>
The ar skills bundle is installed at: ${PLUGIN_ROOT}
Bundled files referenced below are relative to that path. Agent writes go under \$NOTES_WORKSPACE (env -> git toplevel -> CWD).

${routing}
</ar-routing>"

escaped="$(escape_for_json "$full")"
printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$escaped"
exit 0
```

- [ ] **Step 5: Create `hooks/session-start-codex`** (reuses `session-start`, mapping Codex's `PLUGIN_ROOT`)

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
exec bash "$SCRIPT_DIR/session-start"
```

- [ ] **Step 6: Create `hooks/hooks.json`**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start", "async": false }
        ]
      }
    ]
  }
}
```

- [ ] **Step 7: Create `hooks/hooks-codex.json`**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear",
        "hooks": [
          { "type": "command", "command": "\"${PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start-codex", "async": false }
        ]
      }
    ]
  }
}
```

- [ ] **Step 8: Make hook scripts executable, run the test**

```bash
chmod +x hooks/run-hook.cmd hooks/session-start hooks/session-start-codex
bash scripts/tests/test-hooks.sh
```
Expected: 3 `PASS:` lines (or `SKIP` if jq absent), exit 0.

- [ ] **Step 9: Commit**

```bash
git add hooks/ scripts/tests/test-hooks.sh
git commit -m "[ai] add SessionStart hooks injecting the ar routing index (Claude + Codex)"
```

---

### Task 4: Cross-harness thin manifests + version-sync test

**Files:**
- Create: `.codex-plugin/plugin.json`, `gemini-extension.json`, `GEMINI.md`, `.agents/skills` (symlink → `../skills`)
- Modify: `AGENTS.md` (add a consumer-routing pointer)
- Test: `scripts/tests/test-manifests.sh`

**Interfaces:**
- Consumes: `.claude-plugin/*` (Task 1). Produces: all four manifests sharing version `1.0.0`, plugin name `ar`.

- [ ] **Step 1: Create `.codex-plugin/plugin.json`**

```json
{
  "name": "ar",
  "version": "1.0.0",
  "description": "Notes, tasks, synthesis, reports, and search skills for AI agents.",
  "author": { "name": "whacked", "email": "directedglaph@gmail.com" },
  "homepage": "https://github.com/whacked/agent-resources",
  "repository": "https://github.com/whacked/agent-resources",
  "license": "MIT",
  "skills": "./skills/",
  "hooks": "./hooks/hooks-codex.json"
}
```

- [ ] **Step 2: Create `gemini-extension.json`**

```json
{
  "name": "ar",
  "version": "1.0.0",
  "description": "Notes, tasks, synthesis, reports, and search skills for AI agents.",
  "contextFileName": "GEMINI.md"
}
```

- [ ] **Step 3: Create `GEMINI.md`**

```markdown
@./skills/using-ar/SKILL.md
```

- [ ] **Step 4: Create the `.agents/skills` symlink** (OpenCode + standalone Codex discovery)

```bash
mkdir -p .agents
ln -s ../skills .agents/skills
test -d .agents/skills && ls .agents/skills | grep -q using-ar && echo "symlink OK"
```
Expected: `symlink OK` (the symlink resolves to the real `skills/` dir).

- [ ] **Step 5: Add a consumer-routing pointer to `AGENTS.md`** — append at the end of the file:

```markdown

## Consumer routing (when this repo is installed as the `ar` extension)

When a workspace has this extension installed, route requests using `skills/using-ar/SKILL.md` — it maps intents (notes, synthesis, reports, CPD, search, doctor) to the right `ar:` skill or bundled guide. Agent writes resolve under `$NOTES_WORKSPACE` (env → git toplevel → CWD).
```

- [ ] **Step 6: Write `scripts/tests/test-manifests.sh`**

```bash
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
```

- [ ] **Step 7: Run it**

Run: `bash scripts/tests/test-manifests.sh`
Expected: all `PASS:` (or `SKIP` if jq absent), exit 0.

- [ ] **Step 8: Commit**

```bash
git add .codex-plugin/ gemini-extension.json GEMINI.md .agents/skills AGENTS.md scripts/tests/test-manifests.sh
git commit -m "[ai] add Codex/Gemini/OpenCode thin manifests + version-sync test"
```

---

### Task 5: `doctor` staleness check

**Files:**
- Modify: `skills/doctor/scripts/check.sh` (append a staleness section before `exit $status`)

**Interfaces:**
- Consumes: `.claude-plugin/plugin.json` `.version` (Task 1); `git` if the install dir is a checkout.

- [ ] **Step 1: Add the staleness block** — in `skills/doctor/scripts/check.sh`, immediately before the final `exit $status`, insert:

```bash
# --- version + upstream staleness ---
PLUGIN_JSON="$INSTALL_ROOT/.claude-plugin/plugin.json"
if command -v jq &>/dev/null && [ -f "$PLUGIN_JSON" ]; then
  installed_ver="$(jq -r '.version // "unknown"' "$PLUGIN_JSON")"
  info "installed ar version: $installed_ver"
fi
if git -C "$INSTALL_ROOT" rev-parse --git-dir &>/dev/null; then
  local_head="$(git -C "$INSTALL_ROOT" rev-parse HEAD 2>/dev/null)"
  remote_head="$(git -C "$INSTALL_ROOT" ls-remote origin HEAD 2>/dev/null | awk '{print $1}')"
  if [ -n "$remote_head" ] && [ "$local_head" != "$remote_head" ]; then
    warn "ar may be behind upstream" "local ${local_head:0:8} != origin ${remote_head:0:8} — update: /plugin marketplace update agent-resources (Claude), codex plugin marketplace upgrade, or gemini extensions update ar"
  elif [ -n "$remote_head" ]; then
    info "ar is up to date with origin (${local_head:0:8})"
  else
    info "upstream HEAD unknown (no reachable 'origin' remote) — update via your harness's plugin-update command"
  fi
else
  info "install dir is not a git checkout — update via your harness's plugin-update command (/plugin marketplace update agent-resources, etc.)"
fi
```

- [ ] **Step 2: Smoke-test that doctor still exits cleanly**

Run:
```bash
ws="$(mktemp -d)"; mkdir -p "$ws/agents/notes" "$ws/agents/tasks"
NOTES_WORKSPACE="$ws" bash skills/doctor/scripts/check.sh | grep -E 'installed ar version|up to date|behind upstream|not a git checkout'
rm -rf "$ws"
```
Expected: at least one of the version/staleness `INFO`/`WARN` lines prints; command exits 0 (when required bins present).

- [ ] **Step 3: Commit**

```bash
git add skills/doctor/scripts/check.sh
git commit -m "[ai] doctor: report installed version + upstream staleness with update commands"
```

---

### Task 6: Install docs + README install table

**Files:**
- Create: `docs/INSTALL.md`
- Modify: `README.md` (install table → plugin id `ar`; point to `docs/INSTALL.md`)

**Interfaces:** none.

- [ ] **Step 1: Create `docs/INSTALL.md`**

```markdown
# Installing `ar`

This repo ships as one bundled plugin named `ar` (skills surface as `ar:notes`, `ar:synthesize`, …) inside a marketplace named `agent-resources`. Skills are inert until triggered; the `ar:using-ar` routing index is injected at session start so requests route automatically.

After install, point writes at a workspace (only needed if you are not already inside the git repo you want to write into):

    export NOTES_WORKSPACE=/path/to/your/notes-repo

Then verify: `bash skills/doctor/scripts/check.sh`.

## Claude Code

    /plugin marketplace add whacked/agent-resources
    /plugin install ar@agent-resources

Local clone instead of GitHub:

    /plugin marketplace add /path/to/agent-resources
    /plugin install ar@agent-resources

Update: `/plugin marketplace update agent-resources`. (Auto-update is off by default for third-party marketplaces; enable per the Claude Code `/plugin` Marketplaces tab.)

## Codex

    codex plugin marketplace add github:whacked/agent-resources
    codex plugin add ar

Update: `codex plugin marketplace upgrade`. *(Best-effort — verify against current Codex docs.)*

## Gemini CLI

    gemini extensions install https://github.com/whacked/agent-resources

Update: `gemini extensions update ar`. *(Best-effort — verify against current Gemini docs.)*

## OpenCode

OpenCode has no GitHub-install for skills. Clone the repo and symlink its `skills/` into a scanned path:

    git clone https://github.com/whacked/agent-resources
    ln -s "$PWD/agent-resources/skills" ~/.config/opencode/skills

(The repo also ships `.agents/skills` → `skills`, which OpenCode and standalone Codex scan if the repo itself sits in your project.) *(Best-effort — verify against current OpenCode docs.)*
```

- [ ] **Step 2: Fix the README install table** — in `README.md`, the Claude Code row currently says `/plugin install agent-resources@agent-resources`. Change the plugin id to `ar`:

Replace:
```
| **Claude Code** | `.claude-plugin/{plugin.json, marketplace.json}` | `/plugin marketplace add whacked/agent-resources`<br>then `/plugin install agent-resources@agent-resources` |
```
with:
```
| **Claude Code** | `.claude-plugin/{plugin.json, marketplace.json}` | `/plugin marketplace add whacked/agent-resources`<br>then `/plugin install ar@agent-resources` |
```

- [ ] **Step 3: Point the README at `docs/INSTALL.md`** — immediately under the `## Install` heading, add:

```markdown
> Full per-harness install + update steps: [`docs/INSTALL.md`](docs/INSTALL.md).
```

- [ ] **Step 4: Verify the README no longer claims the wrong plugin id**

Run: `grep -n 'agent-resources@agent-resources' README.md || echo "clean"`
Expected: `clean`.

- [ ] **Step 5: Commit**

```bash
git add docs/INSTALL.md README.md
git commit -m "[ai] add docs/INSTALL.md; fix README plugin id to ar"
```

---

### Task 7: Normative report + final aggregation

**Files:**
- Create: `artifacts/reports/2026/07/2026-07-01.001-ar-plugin-packaging.md`
- Modify: `scripts/tests/run-tests.sh` (aggregate `test-manifests.sh`, `test-hooks.sh`)

**Interfaces:** none.

- [ ] **Step 1: Aggregate the Plan 2 suites in `run-tests.sh`** — alongside the Plan 1 sub-suite lines, add:

```bash
check "manifest version-sync suite" pass bash "$TESTS_DIR/test-manifests.sh"
check "session-start hook suite"    pass bash "$TESTS_DIR/test-hooks.sh"
```

- [ ] **Step 2: Run the full suite**

Run: `bash scripts/tests/run-tests.sh`
Expected: all `PASS`, `Results: N passed, 0 failed`, exit 0.

- [ ] **Step 3: Write the normative report** — `artifacts/reports/2026/07/2026-07-01.001-ar-plugin-packaging.md`

```markdown
---
status: accepted
date: 2026-07-01
intent: normative
author: agent
tags:
  - packaging
  - skills
  - portability
  - cross-harness
references:
  - docs/superpowers/specs/2026-07-01-portable-ar-skills-distribution-design.md
supersedes: 2026-06-30.002-supersede-ov-taskmd-cue-with-tfq
---

# Package agent-resources as the portable, auto-invoking `ar` plugin

This repo is now distributed as a single bundled plugin `ar` (marketplace `agent-resources`), installable from GitHub or a local clone, and auto-invoking via a SessionStart-injected routing index.

# Motivation

Three defects (PROBLEM.md) plus a gap: agent writes climbed to the read-only install dir; the documented `.claude-plugin` manifests did not exist; there was no upstream-update story; and skills only fired on description match, with no portable routing.

# Reasoning

Reads of bundled resources are install-relative (the whole tree ships together); writes resolve under `$NOTES_WORKSPACE` (env → git toplevel → CWD) so they survive version bumps. Cohesive interdependent skills ship as one namespaced plugin (`ar:*`). A SessionStart hook injects `ar:using-ar`, the same file Gemini `@`-includes and Codex/OpenCode reach via `.agents/skills`/`AGENTS.md`. Reports are aligned to the `YYYY/MM` shard used by notes/tasks and kept decoupled from CPD.

# Decision

Adopt the design in the referenced spec: workspace resolver, manifest-driven layout-aware doctor with staleness, `.claude-plugin` + best-effort Codex/Gemini/OpenCode manifests, the `ar:using-ar` routing skill + hooks, one mirrored version string, and report-shard migration to `YYYY/MM`.

# Consequences

- Skills write correctly whether installed as a plugin or vendored as a submodule.
- `/plugin marketplace add whacked/agent-resources` → `/plugin install ar@agent-resources` works; `doctor` reports staleness.
- Non-Claude install commands are committed best-effort and must be verified against each harness's live docs.
```

- [ ] **Step 4: Validate the report against the schema**

Run:
```bash
scripts/validate-frontmatter.sh schemas/reports.cue.template.md \
  artifacts/reports/2026/07/2026-07-01.001-ar-plugin-packaging.md
```
Expected: exit 0 (valid). If it fails, correct the frontmatter/headings per the error.

- [ ] **Step 5: Commit**

```bash
git add artifacts/reports/2026/07/ scripts/tests/run-tests.sh
git commit -m "[ai] normative report: ar plugin packaging; aggregate manifest+hook test suites"
```

---

## Self-Review

**Spec coverage (Plan 2 portion):**
- Single bundled `ar` plugin + namespace → Tasks 1, 2. ✓
- `ar:using-ar` routing skill + SessionStart hook injecting it with resolved install root → Tasks 2, 3. ✓
- Cross-harness thin manifests (Codex/Gemini/OpenCode) + `.agents/skills` symlink + `AGENTS.md` routing → Task 4. ✓
- One mirrored version string + version-sync test → Tasks 1, 4. ✓
- Native-update + `doctor` staleness → Task 5. ✓
- `docs/INSTALL.md` + README install-table fix → Task 6. ✓
- Normative report (post-implementation invariant) → Task 7. ✓
- Test aggregation → Task 7. ✓

**Placeholder scan:** No TBD/TODO. Hook scripts, manifests, routing skill, and report are shown in full. "Best-effort — verify against current docs" notes are deliberate honesty flags per the spec's harness-scope decision, not deferred work.

**Type/name consistency:** plugin `name` is `ar` in marketplace.json, plugin.json, codex plugin.json (Tasks 1, 4); version `1.0.0` is identical across all four manifests and asserted by `test-manifests.sh`. `hooks/session-start` is referenced by `hooks.json` (Task 3) and reused by `session-start-codex`. `INSTALL_ROOT` (defined in the Plan 1 doctor rewrite) is reused by the Task 5 staleness block. The report path matches the migrated `YYYY/MM` shard from Plan 1.
```
