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
