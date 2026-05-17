#!/usr/bin/env bash
# Doctor check script — exits 0 if all pass, 1 if any fail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
NOTES_SCRIPTS="$(cd "$SCRIPT_DIR/../../notes/scripts" && pwd)"
status=0

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

# --- binaries ---
for bin in ov taskmd ck; do
  command -v $bin &>/dev/null \
    && check "$bin binary in PATH" "ok" \
    || check "$bin binary in PATH" "install $bin — expected at \$HOME/.local/bin/$bin"
done

# --- ov vaults ---
VAULTS=(
  "$REPO/orgzly/aimemory"
  "$REPO/orgzly/pages"
)
for vault in "${VAULTS[@]}"; do
  if [ -d "$vault/.obsidian" ]; then
    check "ov vault exists: $vault" "ok"
    index_status=$(OV_VAULT="$vault" ov index status --format json 2>/dev/null)
    doc_count=$(echo "$index_status" | jq -r '.data.total_docs // 0' 2>/dev/null)
    if [ "${doc_count:-0}" -gt 0 ]; then
      check "ov index built: $vault ($doc_count docs)" "ok"
    else
      check "ov index built: $vault" "run: ov index build --vault $vault"
    fi
  else
    check "ov vault exists: $vault" "vault missing or not Obsidian"
  fi
done

# --- taskmd ---
if [ -f "$REPO/orgzly/agents/tasks/.taskmd.yaml" ]; then
  check "taskmd config: orgzly/agents/tasks/.taskmd.yaml" "ok"
else
  check "taskmd config: orgzly/agents/tasks/.taskmd.yaml" \
    "run: mkdir -p $REPO/orgzly/agents/tasks && cd $REPO/orgzly/agents/tasks && taskmd init --task-dir . --no-spec --no-agent -q"
fi

# --- agent output directories ---
for dir in orgzly/agents/tasks orgzly/agents/notes; do
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
flat_notes=$(find "$REPO/orgzly/agents/notes" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l)
[ "${flat_notes:-0}" -eq 0 ] \
  && check "agents/notes: no flat .md files (all sharded)" "ok" \
  || check "agents/notes: no flat .md files (all sharded)" \
    "$flat_notes .md file(s) directly under agents/notes/ — move to YYYY/MM/DD/ subdirs"

# --- agents/notes frontmatter validation ---
note_count=$(find "$REPO/orgzly/agents/notes" -name "*.md" 2>/dev/null | wc -l)
if [ "${note_count:-0}" -gt 0 ]; then
  bad_notes=$(bash "$NOTES_SCRIPTS/validate-note.sh" "$REPO/orgzly/agents/notes" 2>/dev/null | grep -c "^FAIL" || true)
  if [ "${bad_notes:-0}" -gt 0 ]; then
    check "agents/notes frontmatter valid" \
      "$bad_notes file(s) invalid — run: bash $NOTES_SCRIPTS/validate-note.sh $REPO/orgzly/agents/notes"
  else
    check "agents/notes frontmatter valid ($note_count files)" "ok"
  fi
else
  warn "agents/notes is empty" "no notes yet — create with: bash $NOTES_SCRIPTS/new-note.sh <slug>"
fi

# --- agents/tasks sharding: warn if tasks at root (not in YYYY/MM/) ---
flat_tasks=$(find "$REPO/orgzly/agents/tasks" -maxdepth 1 -name "*.md" ! -name ".taskmd*" 2>/dev/null | wc -l)
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
for skill in ov taskmd ck audit-skills doctor notes; do
  [ -f "$SKILLS_DIR/$skill/SKILL.md" ] \
    && check "skill registered: $skill" "ok" \
    || check "skill registered: $skill" "missing $SKILLS_DIR/$skill/SKILL.md"
done

# --- guidelines file ---
[ -f "$REPO/GUIDELINES.md" ] \
  && check "GUIDELINES.md exists" "ok" \
  || check "GUIDELINES.md exists" "missing — see GUIDELINES.md in repo root"

# --- agent notes have author field ---
if [ -d "$REPO/orgzly/agents/notes" ]; then
  missing_author=$(rg -rL "^author: " "$REPO/orgzly/agents/notes" --include="*.md" 2>/dev/null | wc -l)
  [ "${missing_author:-0}" -eq 0 ] \
    && check "agents/notes all have author: field" "ok" \
    || check "agents/notes all have author: field" \
      "$missing_author file(s) missing — run: rg -rL '^author: ' $REPO/orgzly/agents/notes --include='*.md'"
fi

# --- no agent writes in human dirs (orgzly/ excluding orgzly/agents/) ---
human_authored_by_agent=$(rg -rl "^author: agent" "$REPO/orgzly" --include="*.md" \
  --glob "!agents/**" 2>/dev/null | wc -l)
[ "${human_authored_by_agent:-0}" -eq 0 ] \
  && check "no agent-authored files in orgzly/ (excl. agents/)" "ok" \
  || check "no agent-authored files in orgzly/ (excl. agents/)" \
    "$human_authored_by_agent file(s) found outside orgzly/agents/ — agent must not write to human vaults"

exit $status
