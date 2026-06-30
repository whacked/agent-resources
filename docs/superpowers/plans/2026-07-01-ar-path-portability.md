# AR Path Portability & Correctness — Implementation Plan (Plan 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every agent *write* resolve under a portable `$NOTES_WORKSPACE` anchor instead of climbing to the (read-only, versioned) install dir, align report sharding to notes, and make `doctor` manifest-driven and layout-aware — so the skills behave correctly whether installed as a plugin or vendored as a submodule.

**Architecture:** A single sourced helper `scripts/lib/workspace.sh` is the one place that resolves the write anchor (`$NOTES_WORKSPACE` → `git rev-parse --show-toplevel` → `$PWD`). The notes scripts and `doctor` source it. Bundled *reads* (validators, schemas, guides) stay install-relative. Reports drop the `DD/` shard to match notes/tasks. `dependencies.json` declares external CLIs; `doctor` reads it and degrades submodule-only checks to INFO when running from a plugin cache.

**Tech Stack:** Bash, `tfq` (frontmatter validation, bundles cuelang), `jq`, `git`, `rg`.

**Companion plan:** Plan 2 (`2026-07-01-ar-packaging-autoinvoke.md`) adds the `.claude-plugin` manifest, the `using-ar` routing skill + `SessionStart` hooks, the cross-harness thin manifests, `doctor` staleness, and `docs/INSTALL.md`. Do Plan 1 first.

## Global Constraints

- All shell scripts start with `#!/usr/bin/env bash`. New executable scripts use `set -euo pipefail`; the existing `doctor` check pattern (`cmd && check ok || check fail`) uses `set -uo pipefail` (no `-e`) because it intentionally continues past individual failures and accumulates a `status` variable.
- Every `${VAR}` used as a path is double-quoted.
- Write-anchor resolution order is exactly: explicit `NOTES_WORKSPACE` env var → `git rev-parse --show-toplevel 2>/dev/null` → `$PWD`. The agent-output subdir defaults to `agents`, overridable via `AGENTS_SUBDIR`.
- Bundled-resource *reads* (schemas, validators, guides, the lib) use paths relative to the reading script's own location. Never climb to a `REPO_ROOT` to find a *write* destination.
- New shell tests follow the existing `scripts/tests/run-tests.sh` `check "<desc>" pass|fail <cmd...>` pattern, aggregating self-contained sub-suite scripts.
- Commit after every task. Branch is `ar-plugin-packaging` (already created, off `main` + the `tfq` skills commit).
- Preserve submodule-layout behavior: scripts and `doctor` must still work when `agent-resources/` is a subdirectory of the consuming repo, and also when installed standalone in a harness cache.

---

### Task 1: Workspace resolver helper

**Files:**
- Create: `scripts/lib/workspace.sh`
- Test: `scripts/tests/test-workspace.sh`

**Interfaces:**
- Produces: `resolve_workspace()` → prints the workspace root (one line); `agents_dir()` → prints `<workspace>/${AGENTS_SUBDIR:-agents}` (one line). Both are meant to be sourced, not executed. Consumed by Tasks 2 and 4.

- [ ] **Step 1: Write the failing test** — `scripts/tests/test-workspace.sh`

```bash
#!/usr/bin/env bash
# Self-contained unit tests for scripts/lib/workspace.sh. Exit 0 = all pass.
set -uo pipefail

LIB="$(cd "$(dirname "$0")/../lib" && pwd)/workspace.sh"
# shellcheck source=/dev/null
source "$LIB"

fail=0
assert_eq() { # desc expected actual
  if [[ "$2" == "$3" ]]; then echo "PASS: $1"; else echo "FAIL: $1 (expected '$2', got '$3')"; fail=1; fi
}

# 1. Explicit NOTES_WORKSPACE wins over everything.
assert_eq "env var wins" "/tmp/ws-explicit" "$(NOTES_WORKSPACE=/tmp/ws-explicit resolve_workspace)"

# 2. AGENTS_SUBDIR override is honored by agents_dir.
assert_eq "agents_dir uses subdir override" "/tmp/ws/out" \
  "$(NOTES_WORKSPACE=/tmp/ws AGENTS_SUBDIR=out agents_dir)"

# 3. agents_dir default subdir is 'agents'.
assert_eq "agents_dir default subdir" "/tmp/ws/agents" \
  "$(NOTES_WORKSPACE=/tmp/ws agents_dir)"

# 4. With no env var, inside a git repo → git toplevel.
gitdir="$(mktemp -d)"; ( cd "$gitdir" && git init -q )
assert_eq "git toplevel when no env var" "$gitdir" \
  "$(cd "$gitdir" && unset NOTES_WORKSPACE; resolve_workspace)"
rm -rf "$gitdir"

# 5. With no env var and not a git repo → $PWD.
nogit="$(mktemp -d)"
assert_eq "pwd fallback outside git" "$nogit" \
  "$(cd "$nogit" && unset NOTES_WORKSPACE; resolve_workspace)"
rm -rf "$nogit"

[[ $fail -eq 0 ]]
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash scripts/tests/test-workspace.sh`
Expected: fails — `workspace.sh` does not exist yet (`source` errors / functions undefined).

- [ ] **Step 3: Create the helper** — `scripts/lib/workspace.sh`

```bash
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
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `bash scripts/tests/test-workspace.sh`
Expected: 5 `PASS:` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/workspace.sh scripts/tests/test-workspace.sh
git commit -m "[ai] add workspace.sh resolver (env -> git toplevel -> pwd)"
```

---

### Task 2: Repoint notes scripts at the resolver

**Files:**
- Modify: `skills/notes/scripts/new-note.sh:20` and `:38` (the `REPO_ROOT` climb and the agent dest)
- Modify: `skills/notes/scripts/new-task.sh:16-17` (the `REPO_ROOT` climb and `TASKS_DIR`)
- Modify: `skills/notes/scripts/validate-note.sh:11` (stale `YYYY/MM/DD` comment)
- Test: `scripts/tests/test-portability.sh`

**Interfaces:**
- Consumes: `resolve_workspace`, `agents_dir` from Task 1, sourced via `"$SCRIPT_DIR/../../../scripts/lib/workspace.sh"` (from `skills/notes/scripts/` that path climbs to the install root, then into `scripts/lib/`).

- [ ] **Step 1: Write the failing test** — `scripts/tests/test-portability.sh`

```bash
#!/usr/bin/env bash
# Integration test: agent writes land under the resolved workspace, NOT the
# install dir. Exit 0 = all pass.
set -uo pipefail

NOTES_SCRIPTS="$(cd "$(dirname "$0")/../../skills/notes/scripts" && pwd)"
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

# new-note.sh: with NOTES_WORKSPACE set, the note must appear under
# $NOTES_WORKSPACE/agents/notes/YYYY/MM/ and nowhere near the install dir.
ws="$(mktemp -d)"
out="$(CLAUDECODE=1 NOTES_WORKSPACE="$ws" bash "$NOTES_SCRIPTS/new-note.sh" portability-probe)"
if [[ "$out" == "$ws/agents/notes/"*"-portability-probe.md" && -f "$out" ]]; then
  ok "new-note.sh writes under \$NOTES_WORKSPACE"
else
  bad "new-note.sh wrote to '$out' (expected under $ws/agents/notes/)"
fi
# It must NOT have written inside the install tree.
if find "$NOTES_SCRIPTS/../../.." -path '*/agents/notes/*portability-probe.md' 2>/dev/null | grep -q .; then
  bad "new-note.sh leaked a write into the install dir"
else
  ok "new-note.sh did not write into the install dir"
fi
rm -rf "$ws"

# new-task.sh requires tfq; skip cleanly if absent.
if command -v tfq &>/dev/null; then
  ws="$(mktemp -d)"
  out="$(NOTES_WORKSPACE="$ws" bash "$NOTES_SCRIPTS/new-task.sh" "probe task" --tags probe 2>/dev/null)"
  if [[ "$out" == "$ws/agents/tasks/"* && -f "$out" ]]; then
    ok "new-task.sh writes under \$NOTES_WORKSPACE"
  else
    bad "new-task.sh wrote to '$out' (expected under $ws/agents/tasks/)"
  fi
  rm -rf "$ws"
else
  echo "SKIP: new-task.sh (tfq not on PATH)"
fi

[[ $fail -eq 0 ]]
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash scripts/tests/test-portability.sh`
Expected: FAIL — current `new-note.sh` resolves dest via `REPO_ROOT="$SCRIPT_DIR/../../../.."` so the probe lands under the install tree, not `$ws`.

- [ ] **Step 3: Edit `new-note.sh`** — replace the `REPO_ROOT` line (line 20) with sourcing the lib, and the agent dest (line 38).

Replace:
```bash
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
```
with:
```bash
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../../scripts/lib/workspace.sh"
```

Replace (in the `CLAUDECODE` branch):
```bash
  DEFAULT_DEST="$REPO_ROOT/agents/notes"
```
with:
```bash
  DEFAULT_DEST="$(agents_dir)/notes"
```

- [ ] **Step 4: Edit `new-task.sh`** — replace lines 16-17.

Replace:
```bash
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TASKS_DIR="$REPO_ROOT/agents/tasks"
```
with:
```bash
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../../scripts/lib/workspace.sh"
TASKS_DIR="$(agents_dir)/tasks"
```

- [ ] **Step 5: Fix the stale comment in `validate-note.sh`** — line 11.

Replace:
```bash
#   3. YAML frontmatter validates against skills/notes/schemas/notes.cue.template.md
```
(the block comment two lines above, line 11, currently reads `#   2. Path is under YYYY/MM/DD/ sharding`) — change `YYYY/MM/DD/` to `YYYY/MM/`:
```bash
#   2. Path is under YYYY/MM/ sharding
```

- [ ] **Step 6: Run the portability test and watch it pass**

Run: `bash scripts/tests/test-portability.sh`
Expected: `new-note.sh` probes pass; `new-task.sh` passes if `tfq` present, else `SKIP`. Exit 0.

- [ ] **Step 7: Commit**

```bash
git add skills/notes/scripts/new-note.sh skills/notes/scripts/new-task.sh \
        skills/notes/scripts/validate-note.sh scripts/tests/test-portability.sh
git commit -m "[ai] notes scripts: resolve writes via workspace.sh, not install-dir climb"
```

---

### Task 3: Align report sharding to notes (migrate + fix guide prose)

**Files:**
- Migrate: 3 files under `artifacts/reports/YYYY/MM/DD/` → `artifacts/reports/YYYY/MM/`
- Modify: `docs/agent-guides/reports.md` (drop `DD/`; read/write split)
- Modify: `docs/agent-guides/cpd-data.md` (read/write split for `artifacts/data/` paths)
- Modify: `skills/synthesize/SKILL.md:188` (report path `YYYY/MM/DD/` → `YYYY/MM/`)

**Interfaces:** none (content + filesystem only).

- [ ] **Step 1: Migrate the 3 existing reports up one level**

```bash
git mv artifacts/reports/2026/04/23/2026-04-23.001-manage-cumulative-data-with-cpd.md \
       artifacts/reports/2026/04/2026-04-23.001-manage-cumulative-data-with-cpd.md
git mv artifacts/reports/2026/04/24/2026-04-24.001-refactor-agent-directives.md \
       artifacts/reports/2026/04/2026-04-24.001-refactor-agent-directives.md
git mv artifacts/reports/2026/06/30/2026-06-30.002-supersede-ov-taskmd-cue-with-tfq.md \
       artifacts/reports/2026/06/2026-06-30.002-supersede-ov-taskmd-cue-with-tfq.md
rmdir artifacts/reports/2026/04/23 artifacts/reports/2026/04/24 artifacts/reports/2026/06/30
```

- [ ] **Step 2: Verify the new layout**

Run: `find artifacts/reports -name '*.md' | sort`
Expected (3 lines, all at `YYYY/MM/`):
```
artifacts/reports/2026/04/2026-04-23.001-manage-cumulative-data-with-cpd.md
artifacts/reports/2026/04/2026-04-24.001-refactor-agent-directives.md
artifacts/reports/2026/06/2026-06-30.002-supersede-ov-taskmd-cue-with-tfq.md
```

- [ ] **Step 3: Rewrite `docs/agent-guides/reports.md`** to the YYYY/MM shard and the read/write split. Replace the whole file with:

```markdown
# Agent Report Guide

Write every agent-generated report, analysis, implementation decision, architectural change, or significant design choice as a Markdown file conforming to the bundled `schemas/reports.cue.template.md`.

Use `intent: descriptive` when the report only describes what is true. Use `intent: normative` when the report establishes, justifies, or affects a change.

## Location and naming

- Location: `$NOTES_WORKSPACE/artifacts/reports/YYYY/MM/` (where `$NOTES_WORKSPACE` resolves env → git toplevel → CWD; see `scripts/lib/workspace.sh`).
- Filename: `YYYY-MM-DD.NNN-short-slug.md` (`NNN` resets per day).
- Example: `2026-04-22.001-replace-metrics-pipeline.md`

## Validation

Run this before committing a report (the schema and validator are bundled reads, install-relative; the report itself is the workspace write):

```sh
<install>/scripts/validate-frontmatter.sh \
  <install>/schemas/reports.cue.template.md \
  "$NOTES_WORKSPACE/artifacts/reports/YYYY/MM/<your-report.md>"
```

`<install>` is this extension's root (the directory holding `skills/`, `scripts/`, `schemas/`). A non-zero exit means the report is invalid and must be corrected before proceeding.
```

- [ ] **Step 4: Fix write paths in `docs/agent-guides/cpd-data.md`** — make the two `artifacts/data/...` references workspace-anchored.

Replace (line 27):
```markdown
Write records to `artifacts/data/<scope-or-dataset-slug>/<dataset-slug>.cpd.yaml`. Continue appending to the same CPD file while the accumulation scope and schema remain compatible; do not rotate files merely because the calendar date changes.
```
with:
```markdown
Write records to `$NOTES_WORKSPACE/artifacts/data/<scope-or-dataset-slug>/<dataset-slug>.cpd.yaml` (`$NOTES_WORKSPACE` resolves env → git toplevel → CWD; see `scripts/lib/workspace.sh`). Continue appending to the same CPD file while the accumulation scope and schema remain compatible; do not rotate files merely because the calendar date changes.
```

Replace (line 31):
```markdown
For long-lived datasets, add `artifacts/data/<scope-or-dataset-slug>/README.md` with the dataset purpose, active CPD file, schema lineage, append policy, and migration notes.
```
with:
```markdown
For long-lived datasets, add `$NOTES_WORKSPACE/artifacts/data/<scope-or-dataset-slug>/README.md` with the dataset purpose, active CPD file, schema lineage, append policy, and migration notes.
```

- [ ] **Step 5: Fix the report path in `skills/synthesize/SKILL.md`** — line 188.

Replace:
```
# File lands in agent-resources/artifacts/reports/YYYY/MM/DD/
```
with:
```
# File lands in $NOTES_WORKSPACE/artifacts/reports/YYYY/MM/
```

- [ ] **Step 6: Commit**

```bash
git add artifacts/reports docs/agent-guides/reports.md docs/agent-guides/cpd-data.md skills/synthesize/SKILL.md
git commit -m "[ai] align report sharding to YYYY/MM; workspace-anchor report/CPD write paths"
```

---

### Task 4: `dependencies.json` + manifest-driven, layout-aware `doctor`

**Files:**
- Create: `dependencies.json`
- Modify: `skills/doctor/scripts/check.sh` (full rewrite)
- Test: `scripts/tests/test-doctor.sh`

**Interfaces:**
- Consumes: `resolve_workspace`, `agents_dir` from Task 1.
- Produces: `dependencies.json` shape `{ cli: [{name, check, required, usedBy}], cohesion: {...} }`, consumed by `doctor` and by Plan 2's manifest tests.

- [ ] **Step 1: Create `dependencies.json`**

```json
{
  "cli": [
    { "name": "tfq", "check": "tfq --version", "required": true,  "usedBy": ["notes", "synthesize", "doctor"] },
    { "name": "rg",  "check": "rg --version",  "required": true,  "usedBy": ["notes", "tfq"] },
    { "name": "jq",  "check": "jq --version",  "required": true,  "usedBy": ["notes", "doctor"] },
    { "name": "ck",  "check": "ck --version",  "required": false, "usedBy": ["ck"] },
    { "name": "cpd", "check": "cpd --help",    "required": false, "usedBy": ["synthesize"] }
  ],
  "cohesion": {
    "knowledge-core": ["notes", "synthesize", "doctor"],
    "leaf": ["tfq", "ck", "audit-skills"]
  }
}
```

- [ ] **Step 2: Write the failing test** — `scripts/tests/test-doctor.sh`

```bash
#!/usr/bin/env bash
# Smoke test for doctor in plugin layout: against a fresh workspace it should
# (a) run without crashing, (b) report the workspace it resolved, (c) PASS the
# required-binary checks when tfq/rg/jq are present. Exit 0 = pass.
set -uo pipefail

CHECK="$(cd "$(dirname "$0")/../../skills/doctor/scripts" && pwd)/check.sh"
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

ws="$(mktemp -d)"
mkdir -p "$ws/agents/notes" "$ws/agents/tasks"
out="$(NOTES_WORKSPACE="$ws" bash "$CHECK" 2>&1)"; rc=$?

echo "$out" | grep -q "Workspace: $ws" && ok "doctor reports resolved workspace" || bad "no workspace line"
echo "$out" | grep -q "plugin" && ok "doctor detects plugin layout (install dir outside workspace)" \
  || bad "layout not reported as plugin (got: $(echo "$out" | grep -i layout))"
if command -v tfq &>/dev/null && command -v rg &>/dev/null && command -v jq &>/dev/null; then
  [[ $rc -eq 0 ]] && ok "doctor exits 0 when required bins present + dirs exist" \
    || bad "doctor exited $rc despite required bins + dirs (out below)"
  [[ $rc -eq 0 ]] || echo "$out"
else
  echo "SKIP: exit-code assertion (a required binary is missing)"
fi
rm -rf "$ws"
[[ $fail -eq 0 ]]
```

- [ ] **Step 3: Run it and watch it fail**

Run: `bash scripts/tests/test-doctor.sh`
Expected: FAIL — current `check.sh` has no `Workspace:`/`Layout:` output and resolves dirs against a `REPO` climb, not `$NOTES_WORKSPACE`.

- [ ] **Step 4: Replace `skills/doctor/scripts/check.sh`** with the layout-aware, manifest-driven version:

```bash
#!/usr/bin/env bash
# Doctor — exits 0 if all required checks pass, 1 if any fail.
# Two layouts:
#   plugin    : this tree is installed in a harness cache, OUTSIDE the workspace
#               it writes into. Submodule-only checks degrade to INFO.
#   submodule : this tree is a subdirectory of the consuming repo. The
#               .claude/skills symlink + extension-routing checks are real.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_ROOT="$(cd "$SKILLS_DIR/.." && pwd)"
NOTES_SCRIPTS="$SKILLS_DIR/notes/scripts"
DEPS_JSON="$INSTALL_ROOT/dependencies.json"
status=0

# shellcheck source=/dev/null
source "$INSTALL_ROOT/scripts/lib/workspace.sh"
WORKSPACE="$(resolve_workspace)"
AGENTS="$(agents_dir)"

case "$INSTALL_ROOT/" in
  "$WORKSPACE"/*) LAYOUT="submodule" ;;
  *)              LAYOUT="plugin" ;;
esac

check() { local label="$1" result="$2"
  if [ "$result" = "ok" ]; then echo "PASS  $label"
  else echo "FAIL  $label"; echo "      fix: $result"; status=1; fi; }
warn() { echo "WARN  $1"; echo "      note: $2"; }
info() { echo "INFO  $1"; }

echo "Layout: $LAYOUT"
echo "Workspace: $WORKSPACE"
echo "Agents: $AGENTS"
echo

# --- external CLI dependencies (manifest-driven) ---
if command -v jq &>/dev/null && [ -f "$DEPS_JSON" ]; then
  while IFS=$'\t' read -r name _check required; do
    if command -v "$name" &>/dev/null; then
      check "$name binary in PATH" "ok"
    elif [ "$required" = "true" ]; then
      check "$name binary in PATH" "install $name and put it on PATH (see dependencies.json .usedBy)"
    else
      warn "$name not found (optional)" "features that use $name degrade without it"
    fi
  done < <(jq -r '.cli[] | [.name, .check, (.required|tostring)] | @tsv' "$DEPS_JSON")
else
  for bin in tfq rg jq; do
    command -v "$bin" &>/dev/null \
      && check "$bin binary in PATH" "ok" \
      || check "$bin binary in PATH" "install $bin and put it on PATH"
  done
  [ -f "$DEPS_JSON" ] || warn "dependencies.json missing" "expected at $DEPS_JSON"
fi

# --- agent output directories ---
for dir in "$AGENTS/notes" "$AGENTS/tasks"; do
  [ -d "$dir" ] \
    && check "agent dir exists: ${dir#"$WORKSPACE"/}" "ok" \
    || check "agent dir exists: ${dir#"$WORKSPACE"/}" "run: mkdir -p $dir"
done

# --- notes skill scripts present ---
for script in new-note.sh new-task.sh validate-note.sh; do
  [ -x "$NOTES_SCRIPTS/$script" ] \
    && check "notes script executable: $script" "ok" \
    || check "notes script executable: $script" "missing or not executable: $NOTES_SCRIPTS/$script"
done

# --- notes schema present ---
NOTES_SCHEMA="$SKILLS_DIR/notes/schemas/notes.cue.template.md"
[ -f "$NOTES_SCHEMA" ] \
  && check "notes schema exists" "ok" \
  || check "notes schema exists" "missing: $NOTES_SCHEMA"

# --- required skills registered ---
for skill in tfq ck audit-skills doctor notes synthesize; do
  [ -f "$SKILLS_DIR/$skill/SKILL.md" ] \
    && check "skill registered: $skill" "ok" \
    || check "skill registered: $skill" "missing $SKILLS_DIR/$skill/SKILL.md"
done

# --- agents/notes sharding + frontmatter (only when notes exist) ---
if [ -d "$AGENTS/notes" ]; then
  flat_notes=$(find "$AGENTS/notes" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  [ "${flat_notes:-0}" -eq 0 ] \
    && check "agents/notes: all sharded (no flat .md)" "ok" \
    || check "agents/notes: all sharded (no flat .md)" "$flat_notes flat file(s) — move to YYYY/MM/ subdirs"

  note_count=$(find "$AGENTS/notes" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "${note_count:-0}" -gt 0 ]; then
    bad=$(bash "$NOTES_SCRIPTS/validate-note.sh" "$AGENTS/notes" 2>/dev/null | grep -c "^FAIL" || true)
    [ "${bad:-0}" -eq 0 ] \
      && check "agents/notes frontmatter valid ($note_count files)" "ok" \
      || check "agents/notes frontmatter valid" "$bad invalid — run: bash $NOTES_SCRIPTS/validate-note.sh $AGENTS/notes"
  else
    info "agents/notes is empty (no notes yet)"
  fi
fi

# --- submodule-only checks (INFO under plugin layout) ---
if [ "$LAYOUT" = "submodule" ]; then
  if [ -L "$WORKSPACE/.claude/skills" ] && [ "$(readlink "$WORKSPACE/.claude/skills")" = "$SKILLS_DIR" ]; then
    check ".claude/skills -> skills symlink" "ok"
  else
    check ".claude/skills -> skills symlink" "run: ln -sfn $SKILLS_DIR $WORKSPACE/.claude/skills"
  fi
else
  info "plugin/extension layout — .claude/skills symlink is managed by the harness (skipped)"
fi

# --- extension routing file present (both layouts) ---
{ [ -f "$INSTALL_ROOT/AGENTS.md" ] || [ -f "$INSTALL_ROOT/CLAUDE.md" ]; } \
  && check "extension routing file (AGENTS.md/CLAUDE.md) present" "ok" \
  || check "extension routing file (AGENTS.md/CLAUDE.md) present" "missing at $INSTALL_ROOT — checkout looks incomplete"

# --- ck index (optional) ---
if command -v ck &>/dev/null; then
  [ -d "$WORKSPACE/.ck" ] \
    && check "ck index exists at workspace root" "ok" \
    || warn "ck index not built" "run: cd $WORKSPACE && ck --index ."
fi

exit $status
```

- [ ] **Step 5: Run the doctor test and watch it pass**

Run: `bash scripts/tests/test-doctor.sh`
Expected: `Workspace:`/`plugin` lines present; exit-0 assertion passes when `tfq`/`rg`/`jq` are installed (else SKIP). Exit 0.

- [ ] **Step 6: Commit**

```bash
git add dependencies.json skills/doctor/scripts/check.sh scripts/tests/test-doctor.sh
git commit -m "[ai] doctor: manifest-driven deps + workspace resolver + layout-aware checks"
```

---

### Task 5: Prose scrub + linter

**Files:**
- Modify: `skills/notes/SKILL.md` (remove `agent-resources/...` hardcoded paths; retired binaries)
- Modify: `skills/synthesize/SKILL.md` (same)
- Test: `scripts/tests/test-prose.sh`

**Interfaces:** none.

- [ ] **Step 1: Write the failing linter** — `scripts/tests/test-prose.sh`

```bash
#!/usr/bin/env bash
# Prose linter: forbid stale path/binary references in skill bodies + guides.
# Exit 0 = clean.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FILES=(
  "$ROOT/skills/notes/SKILL.md"
  "$ROOT/skills/synthesize/SKILL.md"
  "$ROOT/docs/agent-guides/reports.md"
  "$ROOT/docs/agent-guides/cpd-data.md"
)
# Each entry: <regex>\t<human reason>
PATTERNS=(
  'agent-resources/(skills|artifacts|docs|scripts|schemas|CLAUDE|AGENTS)	hardcoded agent-resources/ path — use skill-relative reads or $NOTES_WORKSPACE'
  '\btaskmd\b	retired binary taskmd — superseded by tfq'
  '(^|[^[:alnum:]])ov [a-z]	retired binary ov — superseded by tfq'
  'reports/YYYY/MM/DD	day-sharded report path — reports are YYYY/MM now'
)

fail=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "FAIL: missing $f"; fail=1; continue; }
  for entry in "${PATTERNS[@]}"; do
    rx="${entry%%$'\t'*}"; why="${entry##*$'\t'}"
    if grep -nEq "$rx" "$f"; then
      echo "FAIL: ${f#"$ROOT"/} matches /$rx/ — $why"
      grep -nE "$rx" "$f" | sed 's/^/      /'
      fail=1
    fi
  done
done
[[ $fail -eq 0 ]] && echo "PASS: prose clean"
[[ $fail -eq 0 ]]
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash scripts/tests/test-prose.sh`
Expected: FAIL — `skills/notes/SKILL.md` and `skills/synthesize/SKILL.md` still contain `agent-resources/skills/...` paths (and possibly `ov`/`taskmd` mentions).

- [ ] **Step 3: Scrub `skills/notes/SKILL.md`** — replace every `agent-resources/skills/notes/scripts/...`, `agent-resources/artifacts/...`, `agent-resources/CLAUDE.md`, `agent-resources/docs/...` reference with a skill-relative or `$NOTES_WORKSPACE` form. Concretely, apply these substitutions throughout the file:

| Find | Replace with |
|---|---|
| `bash agent-resources/skills/notes/scripts/new-note.sh` | `bash "$(dirname "$0")/scripts/new-note.sh"` style → in prose write: `bash <notes-skill>/scripts/new-note.sh` |
| `bash agent-resources/skills/notes/scripts/new-task.sh` | `bash <notes-skill>/scripts/new-task.sh` |
| `bash agent-resources/skills/notes/scripts/validate-note.sh` | `bash <notes-skill>/scripts/validate-note.sh` |
| `agent-resources/artifacts/reports/` | `$NOTES_WORKSPACE/artifacts/reports/` |
| `agent-resources/CLAUDE.md` | `the extension's AGENTS.md` |
| `agent-resources/docs/agent-guides/reports.md` | `the bundled docs/agent-guides/reports.md` |

Add one orienting sentence near the top of the file: `` `<notes-skill>` is this skill's own directory (the folder holding this SKILL.md); its helper scripts live in `<notes-skill>/scripts/`. ``

- [ ] **Step 4: Scrub `skills/synthesize/SKILL.md`** — same treatment. Replace `agent-resources/skills/notes/scripts/<x>.sh` → `<notes-skill>/scripts/<x>.sh`; `agent-resources/artifacts/data/...` → `$NOTES_WORKSPACE/artifacts/data/...`; `agent-resources/artifacts/reports/...` → `$NOTES_WORKSPACE/artifacts/reports/...`; `agent-resources/AGENTS.md and agent-resources/docs/agent-guides/reports.md` → `the bundled AGENTS.md and docs/agent-guides/reports.md`. Leave references to the `cpd` binary as-is (it is a real optional dependency, not a retired one).

- [ ] **Step 5: Run the linter and watch it pass**

Run: `bash scripts/tests/test-prose.sh`
Expected: `PASS: prose clean`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add skills/notes/SKILL.md skills/synthesize/SKILL.md scripts/tests/test-prose.sh
git commit -m "[ai] scrub hardcoded agent-resources paths + retired binaries from skill prose"
```

---

### Task 6: Bootstrap workspace anchoring + test aggregation

**Files:**
- Modify: `scripts/bootstrap.sh` (create `artifacts/{reports,data}`; persist `NOTES_WORKSPACE` hint)
- Modify: `scripts/tests/run-tests.sh` (aggregate the new sub-suites)

**Interfaces:** none new.

- [ ] **Step 1: Add an artifacts-dir phase to `bootstrap.sh`** — after Phase 4 (Agent output directories, around line 390), insert a block that also creates the workspace `artifacts/` dirs:

```bash
# ── Phase 4b: artifacts directories (reports + CPD data) ───────────────────────
log_section "Phase 4b: artifacts directories"

for dir in "$TARGET_REPO/$NOTES_VAULT/artifacts/reports" "$TARGET_REPO/$NOTES_VAULT/artifacts/data"; do
  rel="${dir#"$TARGET_REPO"/}"
  if [[ -d "$dir" ]]; then
    log_skip "$rel/ already exists"
  else
    act "Create $rel/" mkdir -p "$dir"
  fi
done
```

- [ ] **Step 2: Add a `NOTES_WORKSPACE` hint to the CLAUDE.md managed block** — in `generate_claude_block()` (around line 335), append a line documenting the write anchor. Replace the `**Write constraint**...` line with:

```bash
**Write constraint**: agent output goes to \`$AGENTS_DIR/\` and \`$NOTES_VAULT/artifacts/\`. Never write to \`$NOTES_VAULT/\` outside those paths.
Set \`NOTES_WORKSPACE=$TARGET_REPO\` (or rely on the git toplevel) so the skills resolve writes here.
```

- [ ] **Step 3: Aggregate the new sub-suites in `run-tests.sh`** — before the final `echo ""` / `Results:` block (line 38), add:

```bash
# new portability + correctness sub-suites
check "workspace resolver suite"   pass bash "$TESTS_DIR/test-workspace.sh"
check "portability suite"          pass bash "$TESTS_DIR/test-portability.sh"
check "doctor smoke suite"         pass bash "$TESTS_DIR/test-doctor.sh"
check "prose linter"               pass bash "$TESTS_DIR/test-prose.sh"
```

- [ ] **Step 4: Run the full suite**

Run: `bash scripts/tests/run-tests.sh`
Expected: all checks `PASS`, final line `Results: N passed, 0 failed`, exit 0.

- [ ] **Step 5: Run bootstrap dry-run as a smoke check**

Run: `bash scripts/bootstrap.sh --dry-run`
Expected: Phase 4b appears and shows it would create `artifacts/reports/` and `artifacts/data/`; no errors.

- [ ] **Step 6: Commit**

```bash
git add scripts/bootstrap.sh scripts/tests/run-tests.sh
git commit -m "[ai] bootstrap: create artifacts dirs + NOTES_WORKSPACE hint; aggregate new test suites"
```

---

## Self-Review

**Spec coverage (Plan 1 portion):**
- Path breakage fix → Tasks 1, 2 (resolver + notes scripts). ✓
- Reads install-relative / writes under `$NOTES_WORKSPACE` → Tasks 1, 2, 3, 4. ✓
- Report shard align to `YYYY/MM` + migrate → Task 3. ✓
- Reports/CPD guides read/write split → Task 3. ✓
- `dependencies.json` + manifest-driven, layout-aware doctor → Task 4. ✓
- Prose scrub + `test-prose.sh` (skills + guides; forbids `agent-resources/`, retired binaries, `YYYY/MM/DD`) → Task 5. ✓
- `bootstrap.sh` creates `artifacts/{reports,data}`, sets `NOTES_WORKSPACE` hint → Task 6. ✓
- Tests aggregated into `run-tests.sh` → Task 6. ✓
- **Deferred to Plan 2** (correctly out of this plan): `.claude-plugin` + cross-harness manifests, `using-ar` + hooks, `doctor` staleness, version-sync test, `docs/INSTALL.md`, README rewrite, normative report.

**Placeholder scan:** No TBD/TODO; every code step shows full content. The `<notes-skill>` / `<install>` tokens in prose are intentional human-readable placeholders for the reader to resolve to the skill/extension dir, not code placeholders.

**Type/name consistency:** `resolve_workspace` / `agents_dir` named identically in Tasks 1, 2, 4. `dependencies.json` `.cli[].{name,check,required}` consumed exactly as produced. Sub-suite filenames (`test-workspace.sh`, `test-portability.sh`, `test-doctor.sh`, `test-prose.sh`) match between their creating tasks and the Task 6 aggregation.
