#!/usr/bin/env bash
# Doctor check script — exits 0 if all pass, 1 if any fail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
NOTES_SCRIPTS="$(cd "$SCRIPT_DIR/../../notes/scripts" && pwd)"
status=0

# AGENTS_DIR: where agent output lives, relative to REPO.
# Default assumes vault = repo root (agents/ sits directly at repo root).
# Override with env var when vault is a subdirectory:
#   AGENTS_DIR=my-notes/agents bash check.sh
AGENTS_DIR="${AGENTS_DIR:-agents}"

check() {
  local label="$1" result="$2"
  if [ "$result" = "ok" ]; then
    echo "PASS  $label"
  else
    echo "FAIL  $label"
    echo "      fix: $result"
    status=1
  fi
}

warn() {
  echo "WARN  $1"
  echo "      note: $2"
}

# --- required binaries ---
# tfq is the one binary that supersedes ov, taskmd, and cue (it shells to rg and
# bundles the cuelang library). rg and jq are hard deps of tfq and the scripts.
for bin in tfq rg jq; do
  command -v $bin &>/dev/null \
    && check "$bin binary in PATH" "ok" \
    || check "$bin binary in PATH" "install $bin and put it on PATH (e.g. \$HOME/.local/bin/$bin)"
done

# --- optional binaries (features degrade gracefully when absent) ---
for bin in ck cpd; do
  command -v $bin &>/dev/null \
    && check "$bin binary in PATH (optional)" "ok" \
    || warn "$bin not found (optional)" "semantic search / CPD features degrade without it"
done

# tfq is index-free: no `ov index build` and no `taskmd init`/.taskmd.yaml to check.

# --- agent output directories ---
for dir in "$AGENTS_DIR/tasks" "$AGENTS_DIR/notes"; do
  [ -d "$REPO/$dir" ] \
    && check "agent dir exists: $dir" "ok" \
    || check "agent dir exists: $dir" "run: mkdir -p $REPO/$dir"
done

# --- notes skill scripts present ---
for script in new-note.sh new-task.sh validate-note.sh; do
  [ -x "$NOTES_SCRIPTS/$script" ] \
    && check "notes script executable: $script" "ok" \
    || check "notes script executable: $script" "missing or not executable: $NOTES_SCRIPTS/$script"
done

# --- notes schema present ---
[ -f "$(cd "$SCRIPT_DIR/../../notes/schemas" && pwd)/notes.cue.template.md" ] \
  && check "notes schema exists" "ok" \
  || check "notes schema exists" "missing: $(cd "$SCRIPT_DIR/../../notes/schemas" && pwd)/notes.cue.template.md"

# --- agents/notes sharding: no flat .md files directly under agents/notes/ ---
flat_notes=$(find "$REPO/$AGENTS_DIR/notes" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l)
[ "${flat_notes:-0}" -eq 0 ] \
  && check "agents/notes: no flat .md files (all sharded)" "ok" \
  || check "agents/notes: no flat .md files (all sharded)" \
    "$flat_notes .md file(s) directly under $AGENTS_DIR/notes/ — move to YYYY/MM/DD/ subdirs"

# --- agents/notes frontmatter validation ---
note_count=$(find "$REPO/$AGENTS_DIR/notes" -name "*.md" 2>/dev/null | wc -l)
if [ "${note_count:-0}" -gt 0 ]; then
  bad_notes=$(bash "$NOTES_SCRIPTS/validate-note.sh" "$REPO/$AGENTS_DIR/notes" 2>/dev/null | grep -c "^FAIL" || true)
  if [ "${bad_notes:-0}" -gt 0 ]; then
    check "agents/notes frontmatter valid" \
      "$bad_notes file(s) invalid — run: bash $NOTES_SCRIPTS/validate-note.sh $REPO/$AGENTS_DIR/notes"
  else
    check "agents/notes frontmatter valid ($note_count files)" "ok"
  fi
else
  warn "agents/notes is empty" "no notes yet — create with: bash $NOTES_SCRIPTS/new-note.sh <slug>"
fi

# --- agents/tasks sharding: warn if tasks at root (not in YYYY/MM/) ---
flat_tasks=$(find "$REPO/$AGENTS_DIR/tasks" -maxdepth 1 -name "*.md" ! -name ".taskmd*" 2>/dev/null | wc -l)
[ "${flat_tasks:-0}" -eq 0 ] \
  && check "agents/tasks: no flat task files (all sharded)" "ok" \
  || warn "agents/tasks: $flat_tasks flat task file(s)" \
    "use agent-resources/skills/notes/scripts/new-task.sh to create tasks in YYYY/MM/ shards"

# --- ck index ---
if [ -d "$REPO/.ck" ]; then
  check "ck index exists at repo root" "ok"
  ck_files=$(cd $REPO && ck --status-json . 2>/dev/null | jq -r '.total_files // 0' 2>/dev/null)
  [ "${ck_files:-0}" -gt 10 ] \
    && check "ck index has content ($ck_files files)" "ok" \
    || warn "ck index small ($ck_files files)" "run: cd $REPO && ck --index ."
else
  check "ck index exists at repo root" "run: cd $REPO && ck --index ."
fi

# --- skills symlink ---
SKILLS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -L "$REPO/.claude/skills" ] && [ "$(readlink $REPO/.claude/skills)" = "$SKILLS_DIR" ]; then
  check "skills symlink (.claude/skills -> agent-resources/skills)" "ok"
else
  check "skills symlink" "run: ln -sfn $SKILLS_DIR $REPO/.claude/skills"
fi

# --- required skills registered ---
for skill in tfq ck audit-skills doctor notes synthesize; do
  [ -f "$SKILLS_DIR/$skill/SKILL.md" ] \
    && check "skill registered: $skill" "ok" \
    || check "skill registered: $skill" "missing $SKILLS_DIR/$skill/SKILL.md"
done

# --- agent-resources/CLAUDE.md (routing + invariants) ---
[ -f "$REPO/agent-resources/CLAUDE.md" ] \
  && check "agent-resources/CLAUDE.md exists" "ok" \
  || check "agent-resources/CLAUDE.md exists" \
    "missing — check agent-resources checkout: git submodule update --init"

# --- agent notes have author field ---
if [ -d "$REPO/$AGENTS_DIR/notes" ]; then
  missing_author=$(rg -rL "^author: " "$REPO/$AGENTS_DIR/notes" --include="*.md" 2>/dev/null | wc -l)
  [ "${missing_author:-0}" -eq 0 ] \
    && check "agents/notes all have author: field" "ok" \
    || check "agents/notes all have author: field" \
      "$missing_author file(s) missing — run: rg -rL '^author: ' $REPO/$AGENTS_DIR/notes --include='*.md'"
fi

# --- no agent writes outside agents/ (whole repo, excluding agents/ and agent-resources/) ---
human_authored_by_agent=$(rg -rl "^author: agent" "$REPO" --include="*.md" \
  --glob "!$AGENTS_DIR/**" --glob "!agent-resources/**" 2>/dev/null | wc -l)
[ "${human_authored_by_agent:-0}" -eq 0 ] \
  && check "no agent-authored files outside $AGENTS_DIR/" "ok" \
  || check "no agent-authored files outside $AGENTS_DIR/" \
    "$human_authored_by_agent file(s) found outside $AGENTS_DIR/ — agent must not write to human content"

exit $status
