---
name: notes
description: Use this skill whenever creating, validating, or locating agent-authored notes in this repo. Covers new-note.sh, new-task.sh, validate-note.sh, and when to write a note vs a formal report.
version: 1.2.0
---

# notes — Agent Note and Task Creation

All agent-authored content lives under `agents/` at the repo root (or `<vault>/agents/` if the vault is a subdirectory). Always use the scripts — never create files by hand.

## Full workflow (do these in order)

### 1. Discover what already exists

Before writing anything, check for prior notes and related human content.

```bash
# Find existing agent notes on the topic
rg "slug:.*<topic>" agents/notes/ --include="*.md" -l
ck --hybrid "<topic>" agents/notes/     # semantic match on prior notes

# Find related human notes
ov search "<topic>" --vault <vault>
ck --hybrid "<topic>" .                 # cross-vault semantic search
```

If a relevant prior agent note exists and you are updating it, create a new note with `supersedes:` — do not edit the old file.

### 2. Read source notes

```bash
ov read <path> --vault <vault>
ov backlinks "<note-name>" --vault <vault>
```

Extract TODOs from human notes:
```bash
rg -n "TODO|FIXME|#todo|#TODOS|#ActionItem|\baction item:|\- \[ \]" \
   --type md . --no-heading
```

### 3. Create the note or task

```bash
# Note
bash agent-resources/skills/notes/scripts/new-note.sh <slug>
# → agents/notes/YYYY/MM/DD/YYYY-MM-DD.NNN-slug.md

# Task (from a TODO or action item scraped from notes)
bash agent-resources/skills/notes/scripts/new-task.sh "Task title" \
  --template action-item \
  --context "aimemory/2026-05-19.md" \
  --tags foo,bar
# → agents/tasks/YYYY/MM/NNN-slug.md
```

Slug: lowercase, hyphens only (`[a-z0-9-]+`). The script returns the created file path.

**Always use `new-task.sh` — never call `taskmd add` directly.** `taskmd` resolves its config by walking up from CWD; the script `cd`s into `agents/tasks/` internally so the right config is found. Calling `taskmd add` from the Bash tool with a bare `cd` poisons the tool's working directory for all subsequent calls.

**Task creation rules:**
- `--template action-item` — use for any item scraped from a journal or meeting note; avoids meaningless Objective/Tasks/Acceptance-Criteria placeholders
- `--context "<source-file>"` — always set; this is the provenance link taskmd uses for `taskmd context <id>`
- `--priority` — set only when clearly justified by context (e.g. legal/NDA → high, meta-tooling wish → low); leave medium otherwise
- After all tasks are created, reason about dependencies and set `dependencies: ["NNN"]` for any task that logically cannot start until another completes

### 4. Fill in the created file

Open the file and:
- Set `source_notes:` to every human note you synthesized from — this is mandatory, it's the provenance link
- Set `tags:`
- Add `supersedes: YYYY-MM-DD.NNN-prior-slug` if replacing an earlier note
- Write `[[bare-links]]` in the body to reference source notes and related notes (see Link Convention below)
- For tasks: set `context:` to the source journal file

### 5. Validate

```bash
bash agent-resources/skills/notes/scripts/validate-note.sh agents/notes/YYYY/MM/DD/file.md
```

### 6. Rebuild ov indexes

Do this after every session that creates or modifies notes, so `ov backlinks` on human notes surfaces the new agent content.

```bash
# Discover vaults then rebuild each:
find . -maxdepth 3 -name ".obsidian" -type d | sed 's|/.obsidian$||' | xargs -I{} ov index build --vault {}
```

---

## Link convention

Always use `[[bare-target]]` links. Never use `[label](path)` for internal cross-references — it breaks `ov backlinks`.

```
[[<vault>/pages/bandgap]]          # path-qualified for cross-directory
[[agents/notes/2026/05/17/slug]]   # full path for agent note references
[[bandgap]]                        # bare for same-vault
```

---

## Note frontmatter

```yaml
---
date: YYYY-MM-DD
author: agent
slug: short-slug
source_notes:
  - <vault>/journals/2026-05-18.md
tags: [example, topic]
supersedes: 2026-05-17.001-prior-slug   # omit if not replacing anything
---
```

---

## Task queries

Run from repo root so `context:` paths resolve correctly.

```bash
taskmd next  --task-dir agents/tasks       # what to work on (respects blocking)
taskmd list  --task-dir agents/tasks
taskmd set 003 --done --task-dir agents/tasks
taskmd graph --task-dir agents/tasks
```

Task options for `new-task.sh`:
```bash
# Scraped action item (most common case)
bash agent-resources/skills/notes/scripts/new-task.sh "Title" \
  --template action-item --context "aimemory/2026-05-19.md" --tags foo,bar

# With explicit priority or dependency
bash agent-resources/skills/notes/scripts/new-task.sh "Title" \
  --template action-item --context "aimemory/2026-05-19.md" \
  --priority high --depends-on 002
```

---

## Note vs formal report

| Situation | Write |
|---|---|
| Synthesizing human journal entries | note (`new-note.sh`) |
| Task context, findings, open questions | note (`new-note.sh`) |
| Architectural decision, design change, directive change | report → `agent-resources/artifacts/reports/` |
| Schema migration, data contract change | report → `agent-resources/artifacts/reports/` |

For reports: read `agent-resources/CLAUDE.md` routing, then `agent-resources/docs/agent-guides/reports.md`.

---

## Management scripts reference

| Script | Purpose | When to call |
|---|---|---|
| `agent-resources/skills/notes/scripts/new-note.sh <slug>` | Create sharded note with frontmatter | Any time agent writes a synthesis or working note |
| `agent-resources/skills/notes/scripts/new-task.sh "title" [opts]` | Create sharded task via taskmd | When promoting a TODO to a tracked task |
| `agent-resources/skills/notes/scripts/validate-note.sh <file\|dir>` | Check filename, path, frontmatter | After creating/editing notes; doctor runs this too |
