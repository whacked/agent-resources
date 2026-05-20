#!/usr/bin/env bash
# bootstrap.sh — wire agent-resources into a target repo
#
# Run this from the ROOT of the target repo:
#
#   bash agent-resources/scripts/bootstrap.sh [OPTIONS]
#
# What it does (in order):
#   1. Validates environment (git repo root, agent-resources path)
#   2. Creates or updates .claude/skills symlink(s)
#   3. Appends agent-resources block to CLAUDE.md (or creates minimal starter)
#   4. Creates <notes-vault>/agents/{notes,tasks}/ directories
#   5. Initialises taskmd in the tasks directory
#   6. Prints a summary of everything done and any manual actions needed
#
# OPTIONS:
#   --agent-resources PATH   Path to agent-resources dir (default: auto-detected
#                            from this script's location — works when run via
#                            agent-resources/scripts/bootstrap.sh)
#   --notes-vault NAME       Human notes directory (default: "." = repo root is vault)
#                            Pass a subdirectory name if vault is not at repo root.
#   --agents-subdir NAME     Subdir for agent output inside vault
#                            (default: agents → agents/ or <vault>/agents/)
#   --dry-run                Print every action but change nothing on disk
#   --help / -h              Show this help and exit
#
# SAFETY POLICY:
#   - Never overwrites an existing file without explicit notice
#   - Never clobbers a .claude/skills symlink that points somewhere unexpected
#   - CLAUDE.md append is idempotent: marker prevents double-insertion
#   - taskmd init is only run if .taskmd.yaml does not already exist
#   - --dry-run makes every action a no-op: safe to run for inspection first
#
# AFTER RUNNING:
#   bash agent-resources/skills/doctor/scripts/check.sh

set -euo pipefail

# ── Script location ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_AGENT_RESOURCES="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
AGENT_RESOURCES="$DEFAULT_AGENT_RESOURCES"
NOTES_VAULT="."
AGENTS_SUBDIR="agents"
DRY_RUN=0
TARGET_REPO="$PWD"

# ── Idempotency markers (appear in files to prevent double-insertion) ──────────
CLAUDE_BLOCK_START="<!-- agent-resources: managed block start -->"
CLAUDE_BLOCK_END="<!-- agent-resources: managed block end -->"

# ── Counters for summary ───────────────────────────────────────────────────────
ACTIONS_TAKEN=0
ACTIONS_SKIPPED=0
WARNINGS_ISSUED=0
MANUAL_ACTIONS=()

# ══════════════════════════════════════════════════════════════════════════════
# Logging helpers
# ══════════════════════════════════════════════════════════════════════════════

log_section() {
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

log_action() {
  echo "[ACTION]   $*"
  ACTIONS_TAKEN=$((ACTIONS_TAKEN + 1))
}

log_skip() {
  echo "[SKIP]     $*"
  ACTIONS_SKIPPED=$((ACTIONS_SKIPPED + 1))
}

log_warn() {
  echo "[WARN]     $*"
  WARNINGS_ISSUED=$((WARNINGS_ISSUED + 1))
}

log_info() {
  echo "[INFO]     $*"
}

log_dryrun() {
  echo "[DRY-RUN]  $*"
  ACTIONS_TAKEN=$((ACTIONS_TAKEN + 1))
}

log_error() {
  echo "[ERROR]    $*" >&2
}

add_manual() {
  MANUAL_ACTIONS+=("$*")
}

# Execute an action or print it under dry-run.
# Usage: act "description" cmd [args...]
act() {
  local desc="$1"; shift
  if [[ $DRY_RUN -eq 1 ]]; then
    log_dryrun "$desc"
    log_dryrun "  command: $*"
  else
    log_action "$desc"
    "$@"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
# Usage
# ══════════════════════════════════════════════════════════════════════════════

usage() {
  cat <<EOF
Usage: bash agent-resources/scripts/bootstrap.sh [OPTIONS]

Run from the ROOT of the target repo.

Options:
  --agent-resources PATH   Path to agent-resources dir
                           (default: derived from this script's location)
  --notes-vault NAME       Human notes directory (default: "." = repo root is vault)
  --agents-subdir NAME     Agent output subdir inside vault (default: agents)
  --dry-run                Show what would happen; change nothing
  --help, -h               Show this help

Example — vault is a subdirectory named "notes":
  bash agent-resources/scripts/bootstrap.sh --notes-vault notes
EOF
}

# ══════════════════════════════════════════════════════════════════════════════
# Argument parsing
# ══════════════════════════════════════════════════════════════════════════════

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent-resources) AGENT_RESOURCES="$(cd "$2" && pwd)"; shift 2 ;;
    --notes-vault)     NOTES_VAULT="$2"; shift 2 ;;
    --agents-subdir)   AGENTS_SUBDIR="$2"; shift 2 ;;
    --dry-run)         DRY_RUN=1; shift ;;
    --help|-h)         usage; exit 0 ;;
    *) log_error "Unknown option: $1"; echo; usage; exit 1 ;;
  esac
done

# When vault is "." (repo root is vault), agents/ sits directly at repo root
if [[ "$NOTES_VAULT" == "." ]]; then
  AGENTS_DIR="$AGENTS_SUBDIR"
else
  AGENTS_DIR="$NOTES_VAULT/$AGENTS_SUBDIR"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Banner
# ══════════════════════════════════════════════════════════════════════════════

echo
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           agent-resources bootstrap                     ║"
if [[ $DRY_RUN -eq 1 ]]; then
echo "║                    ── DRY RUN ──                         ║"
fi
echo "╚══════════════════════════════════════════════════════════╝"
echo
echo "  Target repo       : $TARGET_REPO"
echo "  agent-resources   : $AGENT_RESOURCES"
echo "  Notes vault       : $NOTES_VAULT/"
echo "  Agent output dir  : $AGENTS_DIR/"
if [[ $DRY_RUN -eq 1 ]]; then
echo
echo "  DRY RUN mode: no files will be created or modified."
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 1: Validation
# ══════════════════════════════════════════════════════════════════════════════

log_section "Phase 1: Validation"

# 1a. Must be run from a git repo root (or at least a directory that exists)
if [[ ! -d "$TARGET_REPO" ]]; then
  log_error "Target repo does not exist: $TARGET_REPO"
  exit 1
fi

if [[ ! -d "$TARGET_REPO/.git" ]]; then
  log_warn "No .git directory found at $TARGET_REPO"
  log_warn "This does not appear to be a git repository root."
  log_warn "Bootstrap will continue, but consider running 'git init' first."
  add_manual "git init  # if you haven't already — not required but recommended"
else
  log_info "Git repo root confirmed: $TARGET_REPO"
fi

# 1b. agent-resources must exist and have expected structure
if [[ ! -d "$AGENT_RESOURCES" ]]; then
  log_error "agent-resources directory not found: $AGENT_RESOURCES"
  log_error "Either run this script from inside the target repo (with agent-resources/ present),"
  log_error "or pass --agent-resources /path/to/agent-resources"
  exit 1
fi

if [[ ! -d "$AGENT_RESOURCES/skills" ]]; then
  log_error "agent-resources/skills/ not found at: $AGENT_RESOURCES/skills"
  log_error "The agent-resources directory appears incomplete."
  exit 1
fi

if [[ ! -f "$AGENT_RESOURCES/CLAUDE.md" ]]; then
  log_warn "agent-resources/CLAUDE.md not found — agent-resources may be incomplete."
  add_manual "Check that agent-resources is fully checked out (git submodule update --init)"
else
  log_info "agent-resources looks intact: $AGENT_RESOURCES"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 2: .claude/skills symlink
# ══════════════════════════════════════════════════════════════════════════════

log_section "Phase 2: .claude/skills symlink"

CLAUDE_DIR="$TARGET_REPO/.claude"
SKILLS_LINK="$CLAUDE_DIR/skills"
SKILLS_TARGET="$AGENT_RESOURCES/skills"

# Ensure .claude/ directory exists
if [[ ! -d "$CLAUDE_DIR" ]]; then
  act "Create .claude/ directory" mkdir -p "$CLAUDE_DIR"
else
  log_info ".claude/ directory already exists"
fi

if [[ ! -e "$SKILLS_LINK" && ! -L "$SKILLS_LINK" ]]; then
  # ── Case 1: .claude/skills does not exist at all ──────────────────────────
  log_info "No existing .claude/skills — will create full symlink"
  act "Create .claude/skills → $SKILLS_TARGET" \
    ln -s "$SKILLS_TARGET" "$SKILLS_LINK"

elif [[ -L "$SKILLS_LINK" ]]; then
  CURRENT_TARGET="$(readlink "$SKILLS_LINK")"
  if [[ "$CURRENT_TARGET" == "$SKILLS_TARGET" ]]; then
    # ── Case 2: symlink already points to our agent-resources/skills ─────────
    log_skip ".claude/skills already points to agent-resources/skills — nothing to do"

  else
    # ── Case 3: symlink points somewhere else — do NOT clobber ───────────────
    log_warn ".claude/skills is a symlink, but points to: $CURRENT_TARGET"
    log_warn "Expected: $SKILLS_TARGET"
    log_warn "Bootstrap will NOT overwrite it. You have two options:"
    log_warn "  Option A (replace whole symlink):"
    log_warn "    rm '$SKILLS_LINK' && ln -s '$SKILLS_TARGET' '$SKILLS_LINK'"
    log_warn "  Option B (keep existing skills, add ours individually):"
    log_warn "    for dir in '$SKILLS_TARGET'/*/; do"
    log_warn "      skill=\$(basename \"\$dir\")"
    log_warn "      ln -s \"\$dir\" '$SKILLS_LINK'/\"\$skill\""
    log_warn "    done"
    add_manual "Resolve .claude/skills symlink conflict — see [WARN] output above"
  fi

elif [[ -d "$SKILLS_LINK" ]]; then
  # ── Case 4: .claude/skills is a real directory — symlink individual skills ─
  log_info ".claude/skills is a real directory — will symlink individual skills into it"
  SKILLS_ADDED=0
  SKILLS_SKIPPED=0
  SKILLS_CONFLICTED=0

  for skill_dir in "$SKILLS_TARGET"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill_name="$(basename "$skill_dir")"
    dest="$SKILLS_LINK/$skill_name"

    if [[ ! -e "$dest" && ! -L "$dest" ]]; then
      act "Symlink skill '$skill_name' into .claude/skills/" \
        ln -s "$skill_dir" "$dest"
      SKILLS_ADDED=$((SKILLS_ADDED + 1))

    elif [[ -L "$dest" ]]; then
      dest_target="$(readlink "$dest")"
      if [[ "$dest_target" == "$skill_dir" || "$dest_target" == "${skill_dir%/}" ]]; then
        log_skip "  Skill '$skill_name' already correctly symlinked"
        SKILLS_SKIPPED=$((SKILLS_SKIPPED + 1))
      else
        log_warn "  Skill '$skill_name' at .claude/skills/$skill_name points to: $dest_target"
        log_warn "  Expected: $skill_dir"
        log_warn "  Skipping — resolve manually:"
        log_warn "    rm '$dest' && ln -s '$skill_dir' '$dest'"
        add_manual "Resolve skill symlink conflict for '$skill_name': rm '$dest' && ln -s '$skill_dir' '$dest'"
        SKILLS_CONFLICTED=$((SKILLS_CONFLICTED + 1))
      fi

    else
      log_warn "  .claude/skills/$skill_name exists as a real file/dir — skipping"
      log_warn "  To install our version: rm -rf '$dest' && ln -s '$skill_dir' '$dest'"
      add_manual "Resolve .claude/skills/$skill_name conflict — it is not a symlink"
      SKILLS_CONFLICTED=$((SKILLS_CONFLICTED + 1))
    fi
  done

  log_info "Individual skills: $SKILLS_ADDED added, $SKILLS_SKIPPED already present, $SKILLS_CONFLICTED conflicts"

else
  log_warn ".claude/skills exists but is neither a symlink nor a directory — unexpected state"
  log_warn "Path: $SKILLS_LINK"
  log_warn "Inspect manually and re-run bootstrap after resolving."
  add_manual "Inspect and remove $SKILLS_LINK, then re-run bootstrap"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 3: CLAUDE.md
# ══════════════════════════════════════════════════════════════════════════════

log_section "Phase 3: CLAUDE.md"

CLAUDE_MD="$TARGET_REPO/CLAUDE.md"

# The block we will append — rendered with actual vault/agents paths.
# The start/end markers make the append idempotent.
generate_claude_block() {
  cat <<EOF

$CLAUDE_BLOCK_START
## agent-resources

Skills live in \`agent-resources/skills/\` and are symlinked to \`.claude/skills/\`.
See \`agent-resources/README.md\` for orientation; \`agent-resources/CLAUDE.md\` for routing and invariants.

**Write constraint**: agent output goes to \`$AGENTS_DIR/\`. Never write to \`$NOTES_VAULT/\` outside that path.
$CLAUDE_BLOCK_END
EOF
}

if [[ ! -f "$CLAUDE_MD" ]]; then
  log_info "CLAUDE.md does not exist — creating minimal starter"
  if [[ $DRY_RUN -eq 1 ]]; then
    log_dryrun "Would create $CLAUDE_MD with agent-resources block"
  else
    log_action "Creating $CLAUDE_MD"
    cat > "$CLAUDE_MD" <<EOF
# Project instructions

<!-- Add project-specific instructions above this line. -->
<!-- The block below is managed by agent-resources bootstrap — do not edit manually. -->
$(generate_claude_block)
EOF
    log_info "Created CLAUDE.md with agent-resources block"
  fi

elif grep -qF "$CLAUDE_BLOCK_START" "$CLAUDE_MD" 2>/dev/null; then
  log_skip "CLAUDE.md already contains agent-resources block (marker found) — not modifying"
  log_info "To update the block, remove the lines between:"
  log_info "  $CLAUDE_BLOCK_START"
  log_info "  $CLAUDE_BLOCK_END"
  log_info "and re-run bootstrap."

else
  log_info "CLAUDE.md exists but does not contain agent-resources block — will append"
  if [[ $DRY_RUN -eq 1 ]]; then
    log_dryrun "Would append agent-resources block to $CLAUDE_MD"
  else
    log_action "Appending agent-resources block to $CLAUDE_MD"
    generate_claude_block >> "$CLAUDE_MD"
    log_info "Block appended — $CLAUDE_MD now contains the agent-resources section"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 4: Agent output directories
# ══════════════════════════════════════════════════════════════════════════════

log_section "Phase 4: Agent output directories"

NOTES_DIR="$TARGET_REPO/$AGENTS_DIR/notes"
TASKS_DIR="$TARGET_REPO/$AGENTS_DIR/tasks"

for dir in "$NOTES_DIR" "$TASKS_DIR"; do
  rel="${dir#$TARGET_REPO/}"
  if [[ -d "$dir" ]]; then
    log_skip "$rel/ already exists"
  else
    act "Create $rel/" mkdir -p "$dir"
  fi
done

# ══════════════════════════════════════════════════════════════════════════════
# Phase 5b: .ckignore
# ══════════════════════════════════════════════════════════════════════════════

log_section "Phase 5b: .ckignore"

CKIGNORE_SRC="$AGENT_RESOURCES/skills/ck/.ckignore"
# .ckignore lives at the vault root (where `ck --index .` is run)
if [[ "$NOTES_VAULT" == "." ]]; then
  CKIGNORE_DEST="$TARGET_REPO/.ckignore"
else
  CKIGNORE_DEST="$TARGET_REPO/$NOTES_VAULT/.ckignore"
fi

if [[ ! -f "$CKIGNORE_SRC" ]]; then
  log_warn "skills/ck/.ckignore not found at $CKIGNORE_SRC — skipping"
  add_manual "Check that agent-resources/skills/ck/.ckignore exists"
elif [[ -f "$CKIGNORE_DEST" ]]; then
  log_skip ".ckignore already exists at ${CKIGNORE_DEST#$TARGET_REPO/} — not overwriting"
  log_info "To update: cp '$CKIGNORE_SRC' '$CKIGNORE_DEST'"
else
  act "Install .ckignore to ${CKIGNORE_DEST#$TARGET_REPO/}" cp "$CKIGNORE_SRC" "$CKIGNORE_DEST"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 6: taskmd init
# ══════════════════════════════════════════════════════════════════════════════

log_section "Phase 5: taskmd init"

TASKMD_CONFIG="$TASKS_DIR/.taskmd.yaml"

if [[ ! -f "$TASKMD_CONFIG" ]]; then
  if command -v taskmd &>/dev/null; then
    if [[ $DRY_RUN -eq 1 ]]; then
      log_dryrun "Would run: cd '$TASKS_DIR' && taskmd init --task-dir . --no-spec --no-agent -q"
    else
      log_action "Initialising taskmd in $AGENTS_DIR/tasks/"
      (cd "$TASKS_DIR" && taskmd init --task-dir . --no-spec --no-agent -q)
      log_info "taskmd config created: $AGENTS_DIR/tasks/.taskmd.yaml"
    fi
  else
    log_warn "taskmd not found in PATH — skipping taskmd init"
    log_warn "Install taskmd, then run:"
    log_warn "  cd '$TASKS_DIR' && taskmd init --task-dir . --no-spec --no-agent -q"
    add_manual "cd '$TASKS_DIR' && taskmd init --task-dir . --no-spec --no-agent -q"
  fi
else
  log_skip "taskmd already initialised ($AGENTS_DIR/tasks/.taskmd.yaml exists)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Phase 7: Summary
# ══════════════════════════════════════════════════════════════════════════════

log_section "Phase 6: Summary"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "  DRY RUN — no changes were made to disk."
  echo "  $ACTIONS_TAKEN action(s) would have been taken."
else
  echo "  $ACTIONS_TAKEN action(s) taken."
fi
echo "  $ACTIONS_SKIPPED step(s) skipped (already in place)."
echo "  $WARNINGS_ISSUED warning(s) issued."

if [[ ${#MANUAL_ACTIONS[@]} -gt 0 ]]; then
  echo
  echo "  ┌─ Manual actions required ─────────────────────────────────"
  for item in "${MANUAL_ACTIONS[@]}"; do
    echo "  │  • $item"
  done
  echo "  └────────────────────────────────────────────────────────────"
fi

echo
echo "  Next step: run the health check to verify everything is wired up:"
echo
echo "    bash agent-resources/skills/doctor/scripts/check.sh"
echo

if [[ $DRY_RUN -eq 1 ]]; then
  echo "  Re-run without --dry-run to apply changes."
  echo
fi
