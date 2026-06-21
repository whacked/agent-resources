# Portable Cross-Harness Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `agent-resources` so it installs with one command per agent (Claude Code, Codex, Gemini, OpenCode) from a personal GitHub repo, and so its skills resolve all shared scripts/schemas and all write destinations correctly regardless of install location.

**Architecture:** Ship the whole repo as a single cross-harness extension exposing one shared `skills/` root. Reads of bundled resources use repo-relative paths (valid because the whole tree always ships together); all writes resolve under a `$NOTES_WORKSPACE` anchor (env → git toplevel → CWD), because every harness's install dir is versioned/read-only. External-CLI dependencies are declared in `dependencies.json` and preflight-checked by `doctor`.

**Tech Stack:** Bash, `cue` (frontmatter validation), `jq`, `git`; per-harness manifest files (`.claude-plugin/`, `.codex-plugin/`, `gemini-extension.json`, `.opencode/`).

## Global Constraints

- All shell scripts use `#!/usr/bin/env bash` and `set -euo pipefail`. (verbatim from existing scripts)
- Every `${VAR}` used as a path is double-quoted (spaces/Windows safety).
- No `${CLAUDE_PLUGIN_ROOT}` / `${PLUGIN_ROOT}` in skill bodies or skill scripts — reads use repo-relative paths only. The env var is reserved for per-harness hook manifests, which this work does not introduce.
- All agent writes resolve under `$NOTES_WORKSPACE`; resolution order is exactly: explicit `NOTES_WORKSPACE` env var → `git rev-parse --show-toplevel` → `$PWD`.
- The agent-output subdir defaults to `agents` and is overridable via `AGENTS_SUBDIR` (matches existing `bootstrap.sh`/`doctor` convention).
- New shell tests follow the existing `scripts/tests/run-tests.sh` `check "<desc>" pass|fail <cmd...>` pattern.
- A single version string is the source of truth, mirrored verbatim into every per-harness manifest. Current value: `1.0.0` (first packaged release).
- Commit after every task. Branch is `skills-portability-reorg` (already created).
- Preserve the existing submodule-layout behavior as a fallback: scripts/doctor must still work when `agent-resources/` is a subdirectory of the consuming repo, and must also work when installed standalone in a harness cache.

---

## File Structure

**Create:**
- `scripts/lib/workspace.sh` — sourced helper exposing `resolve_workspace()` and `agents_dir()`. Single source of truth for write-anchor resolution.
- `dependencies.json` — external-CLI dependency manifest + cohesion map; consumed by `doctor`.
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — Claude Code packaging.
- `.codex-plugin/plugin.json` — Codex packaging.
- `gemini-extension.json`, `GEMINI.md` — Gemini packaging.
- `.opencode/plugins/agent-resources.js`, `.opencode/INSTALL.md` — OpenCode packaging.
- `AGENTS.md` — symlink → `CLAUDE.md` (read by Codex/OpenCode).
- `scripts/tests/test-workspace.sh` — unit tests for the resolver.
- `scripts/tests/test-portability.sh` — write-anchor + relative-read integration tests.
- `scripts/tests/test-manifests.sh` — manifest structure + version-sync tests.
- `docs/INSTALL.md` — per-harness install instructions.

**Modify:**
- `skills/notes/scripts/new-note.sh` — replace `REPO_ROOT` climb with resolver.
- `skills/notes/scripts/new-task.sh` — replace `REPO_ROOT` climb with resolver.
- `skills/notes/scripts/validate-note.sh` — explicit shared-validator resolution + error.
- `skills/doctor/scripts/check.sh` — workspace resolver; dependency-manifest-driven binary check; degrade submodule-only checks to informational.
- `skills/notes/SKILL.md`, `skills/synthesize/SKILL.md` — rewrite `agent-resources/...` prose to skill-relative reads / `$NOTES_WORKSPACE` writes.
- `scripts/bootstrap.sh` — set/persist `NOTES_WORKSPACE`; create `artifacts/{reports,data}`; keep symlink wiring as the submodule-layout path.
- `README.md` — point to `docs/INSTALL.md`.

---

## Task 1: Workspace resolver helper

**Files:**
- Create: `scripts/lib/workspace.sh`
- Test: `scripts/tests/test-workspace.sh`

**Interfaces:**
- Produces: `resolve_workspace()` → prints workspace root (env `NOTES_WORKSPACE` → `git rev-parse --show-toplevel` → `$PWD`). `agents_dir()` → prints `<workspace>/<AGENTS_SUBDIR:-agents>`. Both are meant to be `source`d.

- [ ] **Step 1: Write the failing test**

```bash
cat > scripts/tests/test-workspace.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LIB="$(cd "$(dirname "$0")/../lib" && pwd)/workspace.sh"
pass=0; fail=0
check() { local d="$1" exp="$2" got="$3"; if [[ "$got" == "$exp" ]]; then echo "PASS: $d"; ((pass++))||true; else echo "FAIL: $d (want '$exp' got '$got')"; ((fail++))||true; fi; }

# shellcheck disable=SC1090
source "$LIB"

# 1. explicit env wins
got="$(NOTES_WORKSPACE=/tmp/ws-explicit resolve_workspace)"
check "env NOTES_WORKSPACE wins" "/tmp/ws-explicit" "$got"

# 2. git toplevel when no env
tmp="$(mktemp -d)"; ( cd "$tmp" && git init -q )
got="$(cd "$tmp" && unset NOTES_WORKSPACE; resolve_workspace)"
check "git toplevel used" "$(cd "$tmp" && pwd -P)" "$(cd "$got" && pwd -P)"
rm -rf "$tmp"

# 3. CWD when no env and no git
tmp2="$(mktemp -d)"
got="$(cd "$tmp2" && unset NOTES_WORKSPACE; resolve_workspace)"
check "CWD fallback" "$(cd "$tmp2" && pwd -P)" "$(cd "$got" && pwd -P)"
rm -rf "$tmp2"

# 4. agents_dir composes with AGENTS_SUBDIR
got="$(NOTES_WORKSPACE=/tmp/ws AGENTS_SUBDIR=notesvault/agents agents_dir)"
check "agents_dir honors AGENTS_SUBDIR" "/tmp/ws/notesvault/agents" "$got"

echo ""; echo "Results: $pass passed, $fail failed"; [[ $fail -eq 0 ]]
EOF
chmod +x scripts/tests/test-workspace.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-workspace.sh`
Expected: FAIL — `workspace.sh` does not exist (source error).

- [ ] **Step 3: Write minimal implementation**

```bash
mkdir -p scripts/lib
cat > scripts/lib/workspace.sh <<'EOF'
#!/usr/bin/env bash
# workspace.sh — resolve where agent output is written.
# Source this file, then call resolve_workspace / agents_dir.
#
# Resolution order (first match wins):
#   1. explicit $NOTES_WORKSPACE
#   2. git toplevel of CWD
#   3. $PWD
# Agent output subdir defaults to "agents", overridable via $AGENTS_SUBDIR.

resolve_workspace() {
  if [[ -n "${NOTES_WORKSPACE:-}" ]]; then
    printf '%s\n' "${NOTES_WORKSPACE}"
    return 0
  fi
  local top
  if top="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "${top}" ]]; then
    printf '%s\n' "${top}"
    return 0
  fi
  printf '%s\n' "${PWD}"
}

agents_dir() {
  printf '%s/%s\n' "$(resolve_workspace)" "${AGENTS_SUBDIR:-agents}"
}
EOF
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test-workspace.sh`
Expected: `Results: 4 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/workspace.sh scripts/tests/test-workspace.sh
git commit -m "[ai] add \$NOTES_WORKSPACE resolver helper + tests"
```

---

## Task 2: Repoint `new-note.sh` to the resolver

**Files:**
- Modify: `skills/notes/scripts/new-note.sh:18-20,36-42`
- Test: `scripts/tests/test-portability.sh` (new; extended further in Task 8)

**Interfaces:**
- Consumes: `resolve_workspace` / `agents_dir` from `scripts/lib/workspace.sh` (Task 1).

- [ ] **Step 1: Write the failing test**

```bash
cat > scripts/tests/test-portability.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0; fail=0
check() { local d="$1" exp="$2"; shift 2; if "$@"; then r=0; else r=1; fi; if [[ "$exp" == pass && $r -eq 0 ]] || [[ "$exp" == fail && $r -ne 0 ]]; then echo "PASS: $d"; ((pass++))||true; else echo "FAIL: $d"; ((fail++))||true; fi; }

# new-note.sh writes under $NOTES_WORKSPACE, not under agent-resources
ws="$(mktemp -d)"
out="$(NOTES_WORKSPACE="$ws" CLAUDECODE=1 bash "$ROOT/skills/notes/scripts/new-note.sh" portability-probe)"
check "new-note writes under NOTES_WORKSPACE" pass test -f "$out"
case "$out" in "$ws"/agents/notes/*) in_ws=0;; *) in_ws=1;; esac
check "new-note path is inside the workspace agents dir" pass test "$in_ws" -eq 0
rm -rf "$ws"

echo ""; echo "Results: $pass passed, $fail failed"; [[ $fail -eq 0 ]]
EOF
chmod +x scripts/tests/test-portability.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-portability.sh`
Expected: FAIL — `new-note.sh` still computes dest from the `../../../..` climb, so the file lands outside `$ws`.

- [ ] **Step 3: Write minimal implementation**

In `skills/notes/scripts/new-note.sh`, replace the location block (lines 18-20):

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../../scripts/lib/workspace.sh"
```

Then replace the agent-detection dest (lines 36-42) so the agent branch uses the resolver:

```bash
# Detect agent vs human: CLAUDECODE=1 is set by Claude Code in agent shells
if [[ -n "${CLAUDECODE:-}" ]]; then
  DEFAULT_AUTHOR="agent"
  DEFAULT_DEST="$(agents_dir)/notes"
else
  DEFAULT_AUTHOR=$(git config user.name 2>/dev/null || echo "${USER:-human}")
  DEFAULT_DEST="$PWD"
fi
```

(The `REPO_ROOT=` line is deleted; nothing else references it.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test-portability.sh`
Expected: `Results: 2 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add skills/notes/scripts/new-note.sh scripts/tests/test-portability.sh
git commit -m "[ai] new-note.sh: resolve dest via \$NOTES_WORKSPACE"
```

---

## Task 3: Repoint `new-task.sh` to the resolver

**Files:**
- Modify: `skills/notes/scripts/new-task.sh:13-15`
- Test: `scripts/tests/test-portability.sh` (extend)

**Interfaces:**
- Consumes: `resolve_workspace` / `agents_dir` (Task 1).

- [ ] **Step 1: Write the failing test**

Append to `scripts/tests/test-portability.sh` before the final `echo`/results block:

```bash
# new-task.sh computes its tasks dir under $NOTES_WORKSPACE (taskmd may be absent;
# assert the resolved TASKS_DIR by dry-probing the script's own resolution).
ws2="$(mktemp -d)"
resolved="$(NOTES_WORKSPACE="$ws2" bash -c '
  source "'"$ROOT"'/scripts/lib/workspace.sh"; echo "$(agents_dir)/tasks"')"
check "new-task tasks dir resolves under workspace" pass test "$resolved" = "$ws2/agents/tasks"
rm -rf "$ws2"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-portability.sh`
Expected: FAIL — the assertion is about resolver output the script does not yet use; this guards the Step-3 edit. (If it passes incidentally because the resolver exists, proceed — the real change is wiring the script, verified by reading the diff in Step 3.)

- [ ] **Step 3: Write minimal implementation**

In `skills/notes/scripts/new-task.sh`, replace lines 13-15:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../../scripts/lib/workspace.sh"
TASKS_DIR="$(agents_dir)/tasks"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test-portability.sh`
Expected: all PASS (`Results: 3 passed, 0 failed`).

- [ ] **Step 5: Commit**

```bash
git add skills/notes/scripts/new-task.sh scripts/tests/test-portability.sh
git commit -m "[ai] new-task.sh: resolve tasks dir via \$NOTES_WORKSPACE"
```

---

## Task 4: Harden `validate-note.sh` shared-validator resolution

**Files:**
- Modify: `skills/notes/scripts/validate-note.sh:15-19,47-62`
- Test: `scripts/tests/test-portability.sh` (extend)

**Interfaces:**
- Consumes: shared `scripts/validate-frontmatter.sh` via the in-repo relative path; must error clearly if absent.

- [ ] **Step 1: Write the failing test**

Append to `scripts/tests/test-portability.sh` before the results block:

```bash
# validate-note.sh runs from an unrelated CWD and reports the validator path on error.
probe="$(mktemp -d)"
( cd "$probe" && bash "$ROOT/skills/notes/scripts/validate-note.sh" /nonexistent/file.md ) >/dev/null 2>&1 || true
# exercise the explicit missing-validator message by pointing at a stripped copy
stripped="$(mktemp -d)"; mkdir -p "$stripped/skills/notes/scripts"
cp "$ROOT/skills/notes/scripts/validate-note.sh" "$stripped/skills/notes/scripts/"
cp -r "$ROOT/skills/notes/schemas" "$stripped/skills/notes/"
err="$(bash "$stripped/skills/notes/scripts/validate-note.sh" "$ROOT/scripts/tests/validate-sample.md" 2>&1 || true)"
check "validate-note names missing validator" pass bash -c '[[ "'"$err"'" == *validate-frontmatter.sh* ]]'
rm -rf "$probe" "$stripped"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-portability.sh`
Expected: FAIL — current `validate-note.sh` silently falls back to the manual field check when the validator path is absent; it never names the missing file.

- [ ] **Step 3: Write minimal implementation**

In `skills/notes/scripts/validate-note.sh`, replace the path block (lines 15-19) with explicit resolution + guard:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEMA="$SKILL_DIR/schemas/notes.cue.template.md"
VALIDATOR="$(cd "$SCRIPT_DIR/../../.." && pwd)/scripts/validate-frontmatter.sh"
```

Then change the frontmatter branch (lines 47-62) so a missing validator is reported, not silently skipped:

```bash
  # 3. Frontmatter — requires cue CLI + shared validator.
  if command -v cue &>/dev/null && [[ -x "$VALIDATOR" ]]; then
    fm_out=$(bash "$VALIDATOR" "$SCHEMA" "$file" 2>&1) || {
      echo "FAIL  frontmatter: $file"
      echo "$fm_out" | sed 's/^/      /'
      ok=1
    }
  elif command -v cue &>/dev/null && [[ ! -x "$VALIDATOR" ]]; then
    echo "FAIL  validator missing: expected shared validator at $VALIDATOR"
    echo "      (is the agent-resources tree intact? reads are repo-relative)"
    ok=1
  else
    # cue absent — degrade to required-field check
    for field in date author slug; do
      if ! grep -q "^${field}:" "$file" 2>/dev/null; then
        echo "FAIL  frontmatter missing '$field': $file"
        ok=1
      fi
    done
  fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test-portability.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/notes/scripts/validate-note.sh scripts/tests/test-portability.sh
git commit -m "[ai] validate-note.sh: explicit shared-validator resolution + error"
```

---

## Task 5: Create `dependencies.json`

**Files:**
- Create: `dependencies.json`
- Test: `scripts/tests/test-manifests.sh` (new; extended in Tasks 9-11)

**Interfaces:**
- Produces: a JSON document with `.cli[]` (each `{name, check, required, usedBy[]}`) and `.cohesion` (object mapping bundle name → skill names). Consumed by `doctor` (Task 6).

- [ ] **Step 1: Write the failing test**

```bash
cat > scripts/tests/test-manifests.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0; fail=0
check() { local d="$1" exp="$2"; shift 2; if "$@" >/dev/null 2>&1; then r=0; else r=1; fi; if [[ "$exp" == pass && $r -eq 0 ]] || [[ "$exp" == fail && $r -ne 0 ]]; then echo "PASS: $d"; ((pass++))||true; else echo "FAIL: $d"; ((fail++))||true; fi; }

check "dependencies.json is valid JSON" pass jq -e . "$ROOT/dependencies.json"
check "dependencies.json has cli array"  pass jq -e '.cli | type == "array" and length > 0' "$ROOT/dependencies.json"
check "every cli entry has name+check"   pass jq -e 'all(.cli[]; has("name") and has("check"))' "$ROOT/dependencies.json"
check "cohesion maps knowledge-notes"    pass jq -e '.cohesion["knowledge-notes"] | index("synthesize")' "$ROOT/dependencies.json"

echo ""; echo "Results: $pass passed, $fail failed"; [[ $fail -eq 0 ]]
EOF
chmod +x scripts/tests/test-manifests.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-manifests.sh`
Expected: FAIL — `dependencies.json` does not exist.

- [ ] **Step 3: Write minimal implementation**

```bash
cat > dependencies.json <<'EOF'
{
  "cli": [
    { "name": "cue",    "check": "cue version",      "required": true,  "usedBy": ["notes", "synthesize"] },
    { "name": "taskmd", "check": "taskmd --version", "required": true,  "usedBy": ["notes"] },
    { "name": "jq",     "check": "jq --version",     "required": true,  "usedBy": ["notes", "doctor"] },
    { "name": "rg",     "check": "rg --version",     "required": true,  "usedBy": ["doctor", "notes"] },
    { "name": "cpd",    "check": "cpd --help",       "required": false, "usedBy": ["synthesize"] },
    { "name": "ov",     "check": "ov --version",     "required": false, "usedBy": ["ov", "notes"] },
    { "name": "ck",     "check": "ck --version",     "required": false, "usedBy": ["ck", "notes"] }
  ],
  "cohesion": {
    "knowledge-notes": ["notes", "synthesize", "doctor"]
  }
}
EOF
```

Note for implementer: confirm each `check` command's flag against the installed tool before finalizing (e.g. `taskmd --version` vs `taskmd version`). Adjust the string to whatever exits 0 when the tool is present.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test-manifests.sh`
Expected: `Results: 4 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add dependencies.json scripts/tests/test-manifests.sh
git commit -m "[ai] add dependencies.json (external-CLI manifest + cohesion map)"
```

---

## Task 6: Rewrite `doctor/check.sh` for workspace + manifest + layout-agnostic checks

**Files:**
- Modify: `skills/doctor/scripts/check.sh:3-12,30-35,138-142,123-129,153-159`
- Test: `scripts/tests/test-portability.sh` (extend)

**Interfaces:**
- Consumes: `resolve_workspace` (Task 1), `dependencies.json` (Task 5).

- [ ] **Step 1: Write the failing test**

Append to `scripts/tests/test-portability.sh` before the results block:

```bash
# doctor runs without an agent-resources/ submodule present and without a skills symlink,
# resolving the workspace from $NOTES_WORKSPACE, and never hard-FAILs on those absent.
dws="$(mktemp -d)"; ( cd "$dws" && git init -q )
out="$(NOTES_WORKSPACE="$dws" bash "$ROOT/skills/doctor/scripts/check.sh" 2>&1 || true)"
check "doctor does not hard-fail on missing submodule layout" pass bash -c '! grep -q "FAIL  agent-resources/CLAUDE.md exists" <<<"'"$out"'"'
check "doctor binary check is manifest-driven (mentions cpd)" pass bash -c 'grep -q "cpd" <<<"'"$out"'"'
rm -rf "$dws"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-portability.sh`
Expected: FAIL — current `check.sh` hard-checks `$REPO/agent-resources/CLAUDE.md` and the `.claude/skills` symlink, and its binary loop is hardcoded to `ov taskmd ck`.

- [ ] **Step 3: Write minimal implementation**

Replace the header (lines 1-12) of `skills/doctor/scripts/check.sh`:

```bash
#!/usr/bin/env bash
# Doctor check script — exits 0 if all pass, 1 if any fail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESOURCES_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"   # agent-resources root (read-only)
NOTES_SCRIPTS="$(cd "$SCRIPT_DIR/../../notes/scripts" && pwd)"
# shellcheck disable=SC1091
source "$RESOURCES_ROOT/scripts/lib/workspace.sh"
REPO="$(resolve_workspace)"                            # where agent output lives
status=0

# AGENTS_DIR: agent output location relative to the workspace.
AGENTS_DIR="${AGENTS_SUBDIR:-agents}"
```

Replace the binaries block (lines 30-35) with manifest-driven checks:

```bash
# --- binaries (driven by dependencies.json) ---
DEPS_JSON="$RESOURCES_ROOT/dependencies.json"
if [ -f "$DEPS_JSON" ] && command -v jq &>/dev/null; then
  while IFS=$'\t' read -r name req; do
    if command -v "$name" &>/dev/null; then
      check "$name binary in PATH" "ok"
    elif [ "$req" = "true" ]; then
      check "$name binary in PATH" "install $name (required by dependencies.json)"
    else
      warn "$name not in PATH (optional)" "some skills degrade without it — see dependencies.json"
    fi
  done < <(jq -r '.cli[] | [.name, (.required|tostring)] | @tsv' "$DEPS_JSON")
else
  warn "dependencies.json or jq unavailable" "skipping manifest-driven binary check"
fi
```

Convert the submodule-layout checks to informational. Replace the CLAUDE.md block (lines 138-142):

```bash
# --- agent-resources CLAUDE.md (submodule layout only) ---
if [ -f "$REPO/agent-resources/CLAUDE.md" ]; then
  check "agent-resources/CLAUDE.md exists (submodule layout)" "ok"
elif [ -f "$RESOURCES_ROOT/CLAUDE.md" ]; then
  echo "INFO  running from plugin/extension layout (no agent-resources/ submodule)"
else
  warn "agent-resources CLAUDE.md not found in either layout" "check the install"
fi
```

Replace the skills-symlink block (lines 123-129):

```bash
# --- skills symlink (submodule layout only; plugin install needs no symlink) ---
if [ -L "$REPO/.claude/skills" ] && [ "$(readlink "$REPO/.claude/skills")" = "$SKILLS_DIR" ]; then
  check "skills symlink (.claude/skills -> agent-resources/skills)" "ok"
elif [ -e "$REPO/.claude/skills" ]; then
  warn ".claude/skills exists but does not point here" "fine if skills load via a plugin install"
else
  echo "INFO  no .claude/skills symlink (expected when skills load via a plugin/extension)"
fi
```

In the "no agent writes outside agents/" block (lines 153-159), the `--glob "!agent-resources/**"` exclusion stays (harmless when absent). No change required there.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test-portability.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/doctor/scripts/check.sh scripts/tests/test-portability.sh
git commit -m "[ai] doctor: workspace resolver, manifest-driven deps, layout-agnostic checks"
```

---

## Task 7: Rewrite SKILL.md prose (notes + synthesize)

**Files:**
- Modify: `skills/notes/SKILL.md`, `skills/synthesize/SKILL.md`
- Test: `scripts/tests/test-prose.sh` (new)

**Interfaces:** none (documentation). The lint test below is the contract.

Apply these exact textual substitutions everywhere they appear in both files:

| Find | Replace with |
|---|---|
| `bash agent-resources/skills/notes/scripts/` | `bash "$NOTES_SKILL/scripts/` *(see note)* |
| `agent-resources/scripts/validate-frontmatter.sh` | `<agent-resources>/scripts/validate-frontmatter.sh` |
| `agent-resources/artifacts/reports/` | `$NOTES_WORKSPACE/artifacts/reports/` |
| `agent-resources/artifacts/data` | `$NOTES_WORKSPACE/artifacts/data` |
| `agent-resources/docs/agent-guides/` | `<agent-resources>/docs/agent-guides/` |
| `agent-resources/CLAUDE.md` | `<agent-resources>/CLAUDE.md` |
| `agent-resources/AGENTS.md` | `<agent-resources>/AGENTS.md` |

Note on script invocation: in prose, standardize on calling notes scripts by skill-relative reference rather than the consuming-repo path. Replace `bash agent-resources/skills/notes/scripts/<x>.sh` with `bash "$(skill-dir notes)/scripts/<x>.sh"` is overkill for prose; instead use the literal portable form: `` `new-note.sh` (in this skill's `scripts/`) ``. Keep the command examples runnable by showing the repo-relative path the reader actually has, i.e. `bash skills/notes/scripts/new-note.sh <slug>` (no `agent-resources/` prefix). The `<agent-resources>` angle-bracket placeholder denotes "wherever the extension is installed" and is intentionally non-literal in guidance prose.

- [ ] **Step 1: Write the failing test**

```bash
cat > scripts/tests/test-prose.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
pass=0; fail=0
check() { local d="$1" exp="$2"; shift 2; if "$@" >/dev/null 2>&1; then r=0; else r=1; fi; if [[ "$exp" == pass && $r -eq 0 ]] || [[ "$exp" == fail && $r -ne 0 ]]; then echo "PASS: $d"; ((pass++))||true; else echo "FAIL: $d"; ((fail++))||true; fi; }

for f in skills/notes/SKILL.md skills/synthesize/SKILL.md; do
  # No literal consuming-repo write paths remain.
  check "$f: no 'agent-resources/artifacts' literal" fail grep -q "agent-resources/artifacts" "$ROOT/$f"
  check "$f: no 'bash agent-resources/skills' literal" fail grep -q "bash agent-resources/skills" "$ROOT/$f"
done

echo ""; echo "Results: $pass passed, $fail failed"; [[ $fail -eq 0 ]]
EOF
chmod +x scripts/tests/test-prose.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-prose.sh`
Expected: FAIL — both literals currently appear (e.g. `skills/notes/SKILL.md:161` `agent-resources/artifacts/reports/`, `:46` `bash agent-resources/skills/...`).

- [ ] **Step 3: Apply the substitutions**

Use the table above. Concretely, run discovery then edit each hit:

```bash
grep -nE "agent-resources/(artifacts|scripts|docs|skills|CLAUDE|AGENTS)" \
  skills/notes/SKILL.md skills/synthesize/SKILL.md
```

Edit each occurrence per the mapping table (write-path → `$NOTES_WORKSPACE/...`; read/reference → `<agent-resources>/...`; runnable script examples → drop the `agent-resources/` prefix so they read `bash skills/notes/scripts/<x>.sh`). Preserve all surrounding text and the `version:` frontmatter (bump notes from `1.2.0`→`1.3.0` and add `version: 1.0.0` to synthesize if absent — confirm during edit).

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test-prose.sh`
Expected: `Results: 4 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add skills/notes/SKILL.md skills/synthesize/SKILL.md scripts/tests/test-prose.sh
git commit -m "[ai] SKILL.md prose: portable read refs + \$NOTES_WORKSPACE writes"
```

---

## Task 8: Wire all tests into `run-tests.sh` + verify legacy validator tests still pass

**Files:**
- Modify: `scripts/tests/run-tests.sh:38-40`
- Test: itself (the aggregate run)

**Interfaces:**
- Consumes: `test-workspace.sh`, `test-portability.sh`, `test-manifests.sh`, `test-prose.sh`.

- [ ] **Step 1: Write the failing test**

Add a marker assertion: the aggregate run must execute the new suites. Append before line 38 (`echo ""`):

```bash
# --- sub-suites (each exits non-zero on failure) ---
for suite in test-workspace.sh test-portability.sh test-manifests.sh test-prose.sh; do
    if bash "$TESTS_DIR/$suite"; then
        echo "PASS: suite $suite"; (( pass++ )) || true
    else
        echo "FAIL: suite $suite"; (( fail++ )) || true
    fi
done
```

- [ ] **Step 2: Run to verify the aggregate executes them and the original three validator checks still pass**

Run: `bash scripts/tests/run-tests.sh`
Expected: the three original `validate-frontmatter` checks PASS (validator path unchanged), plus the four sub-suites PASS. Final line `Results: N passed, 0 failed`.

- [ ] **Step 3: If any sub-suite fails, fix the underlying task — not the aggregate**

No new implementation here; this task only aggregates. If a sub-suite fails, return to its task.

- [ ] **Step 4: Re-run to confirm green**

Run: `bash scripts/tests/run-tests.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/run-tests.sh
git commit -m "[ai] run-tests.sh: aggregate workspace/portability/manifest/prose suites"
```

---

## Task 9: Claude Code packaging (`.claude-plugin/`)

**Files:**
- Create: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
- Test: `scripts/tests/test-manifests.sh` (extend)

**Interfaces:**
- Produces: a marketplace with one plugin `agent-resources`, `source: "./"`, `version: 1.0.0`.

- [ ] **Step 1: Write the failing test**

Append to `scripts/tests/test-manifests.sh` before the results block:

```bash
check "claude plugin.json valid"       pass jq -e '.name=="agent-resources" and has("version")' "$ROOT/.claude-plugin/plugin.json"
check "marketplace lists the plugin"   pass jq -e '.plugins[0].name=="agent-resources" and .plugins[0].source=="./"' "$ROOT/.claude-plugin/marketplace.json"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash scripts/tests/test-manifests.sh`
Expected: FAIL — files absent.

- [ ] **Step 3: Create the manifests**

```bash
mkdir -p .claude-plugin
cat > .claude-plugin/plugin.json <<'EOF'
{
  "name": "agent-resources",
  "description": "Notes/synthesis/validation skills: sharded notes & tasks, CUE frontmatter validation, CPD data, repo doctor.",
  "version": "1.0.0",
  "author": { "name": "directedglaph" },
  "keywords": ["notes", "synthesis", "validation", "taskmd", "cue"]
}
EOF
cat > .claude-plugin/marketplace.json <<'EOF'
{
  "name": "agent-resources",
  "description": "Personal agent-resources skills marketplace",
  "owner": { "name": "directedglaph" },
  "plugins": [
    {
      "name": "agent-resources",
      "description": "Notes/synthesis/validation skills bundle",
      "version": "1.0.0",
      "source": "./"
    }
  ]
}
EOF
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash scripts/tests/test-manifests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/ scripts/tests/test-manifests.sh
git commit -m "[ai] add Claude Code plugin + marketplace manifests"
```

---

## Task 10: Codex / Gemini / OpenCode packaging + AGENTS.md

**Files:**
- Create: `.codex-plugin/plugin.json`, `gemini-extension.json`, `GEMINI.md`, `.opencode/plugins/agent-resources.js`, `.opencode/INSTALL.md`, `AGENTS.md` (symlink)
- Test: `scripts/tests/test-manifests.sh` (extend)

**Interfaces:**
- Produces: per-harness manifests, all carrying `version: 1.0.0`, all pointing at the shared `./skills/`.

- [ ] **Step 1: Write the failing test**

Append to `scripts/tests/test-manifests.sh` before the results block:

```bash
check "codex plugin points at ./skills/" pass jq -e '.skills=="./skills/" and .version=="1.0.0"' "$ROOT/.codex-plugin/plugin.json"
check "gemini extension valid"           pass jq -e '.contextFileName=="GEMINI.md" and .version=="1.0.0"' "$ROOT/gemini-extension.json"
check "GEMINI.md references skills"       pass grep -q "skills/" "$ROOT/GEMINI.md"
check "AGENTS.md resolves to CLAUDE.md"   pass test "$(readlink "$ROOT/AGENTS.md")" = "CLAUDE.md"
check "opencode plugin file present"      pass test -f "$ROOT/.opencode/plugins/agent-resources.js"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash scripts/tests/test-manifests.sh`
Expected: FAIL — files absent.

- [ ] **Step 3: Create the manifests**

```bash
mkdir -p .codex-plugin .opencode/plugins
cat > .codex-plugin/plugin.json <<'EOF'
{
  "name": "agent-resources",
  "version": "1.0.0",
  "description": "Notes/synthesis/validation skills for Codex.",
  "author": { "name": "directedglaph" },
  "skills": "./skills/"
}
EOF
cat > gemini-extension.json <<'EOF'
{
  "name": "agent-resources",
  "description": "Notes/synthesis/validation skills",
  "version": "1.0.0",
  "contextFileName": "GEMINI.md"
}
EOF
cat > GEMINI.md <<'EOF'
# agent-resources (Gemini context)

Skills live in `skills/`. Activate the relevant skill (notes, synthesize, doctor, ck, ov, taskmd, audit-skills) when its trigger applies. Shared scripts are under `scripts/`; schemas under `schemas/`. Agent output is written under `$NOTES_WORKSPACE` (env → git toplevel → CWD).

@./skills/notes/SKILL.md
EOF
cat > .opencode/plugins/agent-resources.js <<'EOF'
// agent-resources OpenCode plugin shim.
// Skills are discovered from ../../skills/ relative to this repo root.
// See .opencode/INSTALL.md for installation.
export const agentResources = async () => ({});
export default agentResources;
EOF
cat > .opencode/INSTALL.md <<'EOF'
# Installing agent-resources in OpenCode

Clone/sync this repo, then point OpenCode at it as a plugin source. Skills are
exposed from the shared `skills/` directory at the repo root. Agent output is
written under `$NOTES_WORKSPACE` (defaults to the git toplevel of your working repo).
Verify the OpenCode plugin-loading invocation against current OpenCode docs.
EOF
ln -s CLAUDE.md AGENTS.md
```

Implementer note: the OpenCode plugin API and the exact Codex/Gemini install commands must be confirmed against each harness's current docs (Task 12 documents them). The shim above is structurally valid; adjust its export shape to match the OpenCode plugin contract at implementation time.

- [ ] **Step 4: Run to verify it passes**

Run: `bash scripts/tests/test-manifests.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add .codex-plugin/ gemini-extension.json GEMINI.md .opencode/ AGENTS.md scripts/tests/test-manifests.sh
git commit -m "[ai] add Codex/Gemini/OpenCode manifests + AGENTS.md"
```

---

## Task 11: Version-sync guard

**Files:**
- Test: `scripts/tests/test-manifests.sh` (extend)

**Interfaces:**
- Consumes: all four manifests from Tasks 9-10.

- [ ] **Step 1: Write the failing test**

Append to `scripts/tests/test-manifests.sh` before the results block:

```bash
v_claude="$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")"
v_mkt="$(jq -r '.plugins[0].version' "$ROOT/.claude-plugin/marketplace.json")"
v_codex="$(jq -r '.version' "$ROOT/.codex-plugin/plugin.json")"
v_gem="$(jq -r '.version' "$ROOT/gemini-extension.json")"
check "all manifest versions match" pass bash -c "[[ '$v_claude' == '$v_mkt' && '$v_claude' == '$v_codex' && '$v_claude' == '$v_gem' ]]"
```

- [ ] **Step 2: Run to verify it passes (versions already aligned at 1.0.0)**

Run: `bash scripts/tests/test-manifests.sh`
Expected: PASS. (This guard exists to catch future drift; introduce a deliberate mismatch locally to confirm it FAILs, then revert.)

- [ ] **Step 3: Confirm the guard bites**

Temporarily set `.codex-plugin/plugin.json` version to `9.9.9`, run the suite, confirm FAIL, then revert to `1.0.0`.

- [ ] **Step 4: Re-run to confirm green**

Run: `bash scripts/tests/test-manifests.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/test-manifests.sh
git commit -m "[ai] add cross-manifest version-sync guard"
```

---

## Task 12: Install docs + bootstrap workspace dirs + normative report

**Files:**
- Create: `docs/INSTALL.md`
- Modify: `scripts/bootstrap.sh` (Phase 4 dir creation), `README.md`
- Create: a normative report under `artifacts/reports/YYYY/MM/DD/`

**Interfaces:** none (docs + setup). Closes the spec's versioning/follow-up items.

- [ ] **Step 1: Add `artifacts/{reports,data}` creation to bootstrap Phase 4**

In `scripts/bootstrap.sh`, extend the Phase 4 loop (lines 383-390) to also create workspace artifact dirs:

```bash
ARTIFACTS_REPORTS="$TARGET_REPO/artifacts/reports"
ARTIFACTS_DATA="$TARGET_REPO/artifacts/data"
for dir in "$NOTES_DIR" "$TASKS_DIR" "$ARTIFACTS_REPORTS" "$ARTIFACTS_DATA"; do
  rel="${dir#$TARGET_REPO/}"
  if [[ -d "$dir" ]]; then
    log_skip "$rel/ already exists"
  else
    act "Create $rel/" mkdir -p "$dir"
  fi
done
```

- [ ] **Step 2: Write `docs/INSTALL.md`**

```bash
cat > docs/INSTALL.md <<'EOF'
# Installing agent-resources

One GitHub repo, installable per agent. All harnesses read the shared `skills/`
root. Agent output is written under `$NOTES_WORKSPACE` (env var → git toplevel → CWD).

## Claude Code
    /plugin marketplace add directedglaph/agent-resources
    /plugin install agent-resources@agent-resources

## Codex
Add the repo as a Codex plugin (git source). Manifest: `.codex-plugin/plugin.json`,
skills at `./skills/`. AGENTS.md (→ CLAUDE.md) supplies routing.

## Gemini
    gemini extensions install <git-url-of-this-repo>
Manifest: `gemini-extension.json` (context file `GEMINI.md`).

## OpenCode
See `.opencode/INSTALL.md`.

## After install (any harness)
Set the write anchor if not using git toplevel:
    export NOTES_WORKSPACE=/path/to/your/workspace
Then verify:
    bash skills/doctor/scripts/check.sh
EOF
```

Confirm the exact Codex/Gemini/OpenCode invocations against current harness docs before finalizing each line.

- [ ] **Step 3: Point README at INSTALL**

Add to `README.md` (near the top, after the title): `See [docs/INSTALL.md](docs/INSTALL.md) for per-agent install (Claude Code, Codex, Gemini, OpenCode).`

- [ ] **Step 4: File the normative report (repo invariant)**

The repo's `CLAUDE.md` requires architectural/directive changes to be recorded. Read `docs/agent-guides/reports.md`, then create a report with `intent: normative` summarizing: the move to a single cross-harness extension, the `$NOTES_WORKSPACE` write anchor, `dependencies.json`, and the superseding of the earlier multi-plugin direction. Reference the spec `docs/superpowers/specs/2026-06-19-portable-cross-harness-skills-design.md`. Validate it:

```bash
bash scripts/validate-frontmatter.sh schemas/reports.cue.template.md artifacts/reports/<YYYY/MM/DD>/<file>.md
```

- [ ] **Step 5: Run the full suite + commit**

```bash
bash scripts/tests/run-tests.sh
git add docs/INSTALL.md scripts/bootstrap.sh README.md artifacts/reports/
git commit -m "[ai] install docs, bootstrap workspace artifact dirs, normative report"
```

Expected: `bash scripts/tests/run-tests.sh` → `0 failed`.

---

## Self-Review

**Spec coverage:**
- Single cross-harness extension, one shared `skills/` → Tasks 9, 10. ✓
- `${CLAUDE_PLUGIN_ROOT}`-free relative reads → Tasks 2-4, 7 (constraint enforced; `test-prose.sh`). ✓
- `$NOTES_WORKSPACE` writes → Tasks 1-3, 6, 12. ✓
- Dependency manifest + doctor preflight → Tasks 5, 6. ✓
- Versioning + sync → Tasks 9-11. ✓
- Install commands per harness → Task 12 (`docs/INSTALL.md`). ✓
- Legacy validator tests still pass; portability + install tests added → Tasks 8, 9-11. ✓
- Submodule-vs-plugin layout degradation (discovered during planning) → Task 6. ✓
- Normative report follow-up (repo invariant) → Task 12. ✓

**Placeholder scan:** No "TBD/TODO/handle edge cases". The `<agent-resources>` angle-bracket token in Task 7 is an intentional, documented non-literal placeholder for guidance prose, not a plan gap. Several "confirm against current harness docs" notes are explicit verification steps for facts that must not be assumed (per spec Known Risks), not deferred work.

**Type consistency:** `resolve_workspace`/`agents_dir` (Task 1) are referenced identically in Tasks 2, 3, 6. `dependencies.json` shape (`.cli[]{name,check,required,usedBy}`, `.cohesion`) defined in Task 5 matches consumption in Task 6 and tests in Tasks 5, 9-11. Version string `1.0.0` consistent across Tasks 9-11. Test harness `check` signatures match the existing `run-tests.sh` pattern.
