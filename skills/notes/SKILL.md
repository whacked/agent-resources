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
tfq --root agents/notes "<topic>"       # keyword search of prior agent notes
ck --hybrid "<topic>" agents/notes/     # semantic match on prior notes

# Find related human notes
tfq --root <vault> "<topic>"            # keyword search (add --in heading|tag|link to narrow)
ck --hybrid "<topic>" .                 # cross-vault semantic search
```

If a relevant prior agent note exists and you are updating it, create a new note with `supersedes:` — do not edit the old file.

### 2. Read source notes

```bash
tfq --root <vault> --show <ref>             # full record (--raw = body only, --frontmatter = meta only)
tfq --root <vault> --backlinks <ref>        # notes that link here (computed live; no index)
```

`<ref>` resolves by path, basename, seq-stripped basename, or frontmatter `id`/`slug`/`title`.

Extract TODOs from human notes:
```bash
rg -n "TODO|FIXME|#todo|#TODOS|#ActionItem|\baction item:|\- \[ \]" \
   --type md . --no-heading
```

### 3. Create the note or task

```bash
# Note
bash agent-resources/skills/notes/scripts/new-note.sh <slug>
# → agents/notes/YYYY/MM/YYYY-MM-DD.NNN-slug.md

# Task (from a TODO or action item scraped from notes)
bash agent-resources/skills/notes/scripts/new-task.sh "Task title" \
  --context "aimemory/2026-05-19.md" \
  --tags foo,bar
# → agents/tasks/YYYY/MM/NNN-slug.md
```

Slug: lowercase, hyphens only (`[a-z0-9-]+`). The script returns the created file path.

**Always use `new-task.sh` — never call `tfq --task` directly.** The script pins the `agents/tasks` collection via `--root`, lets tfq do the `YYYY/MM/` sharding and the padded sequential id, and translates the friendly `--tags a,b` / `--context FILE` flags into tfq's frontmatter fields. Calling `tfq --task` by hand loses those conveniences and can write the task to the wrong directory.

**Task creation rules:**
- `--context "<source-file>"` — always set; it writes the `context:` frontmatter field, the provenance link back to the source journal/meeting note
- `--tags a,b` — comma-separated; the script expands them into tfq tags
- `--priority` — set only when clearly justified by context (e.g. legal/NDA → high, meta-tooling wish → low); leave medium otherwise
- After all tasks are created, reason about dependencies and set them with `--depends-on NNN[,MMM]` (or edit the `dependencies:` frontmatter) for any task that logically cannot start until another completes — tfq's `--next` then hides blocked tasks

### 4. Fill in the created file

Open the file and:
- Set `source_notes:` to every human note you synthesized from — this is mandatory, it's the provenance link
- Set `tags:`
- Add `supersedes: YYYY-MM-DD.NNN-prior-slug` if replacing an earlier note
- Write `[[bare-links]]` in the body to reference source notes and related notes (see Link Convention below)
- For tasks: set `context:` to the source journal file

### 5. Validate

```bash
bash agent-resources/skills/notes/scripts/validate-note.sh agents/notes/YYYY/MM/file.md
```

### 6. No index to rebuild

tfq is index-free — it computes links and backlinks live on every query, so there is **no `ov index build`** step after creating or editing notes. (If humans browse the vault in Obsidian, Obsidian maintains its own backlink index independently; that is unaffected by the agent loop.)

---

## Link convention

Always use `[[...]]` wiki-links in note bodies. Avoid `[label](path)` markdown links for internal cross-references — wiki-links are what Obsidian and this vault's conventions expect (tfq resolves both kinds, but mixing styles fragments the graph).

**Wiki-links must use paths relative to the note file**, not repo-root-relative paths. Repo-root-relative paths (`[[aimemory/2026-03-30]]`) do not resolve in standard markdown clients.

Agent notes live at `agents/notes/YYYY/MM/`. From that depth, the relative prefixes are:

```
[[../../../../aimemory/YYYY-MM-DD]]          # vault files (4 up to repo root)
[[../../../../pages/some-page]]              # pages vault (4 up)
[[../../../tasks/YYYY/MM/NNN-slug]]          # agent tasks (3 up to agents/, then tasks/)
[[./other-note-same-month]]                  # sibling note in same YYYY/MM/
```

Depth changes if a note is created at a different level — recount `../` from the actual file location.

**`source_notes:` frontmatter is different**: use repo-root-relative paths there (e.g. `aimemory/2026-05-18.md`). These are a provenance record resolved from the vault root, not filesystem-relative paths — so do not add `../` to frontmatter values. (tfq's `--backlinks` is driven by the body `[[wiki-links]]`, which is why *those* must stay file-relative.)

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

```bash
tfq --root agents/tasks --next                       # what to work on (deps satisfied)
tfq --root agents/tasks --list                       # all tasks (--status S to filter)
tfq --root agents/tasks --done 003                   # mark task 003 completed
tfq --root agents/tasks --set 003 --status in-progress
tfq --root agents/tasks --graph                      # dependency edges
```

`<ref>` (e.g. `003`) resolves by seq id, slug, basename, or title.

Task options for `new-task.sh`:
```bash
# Scraped action item (most common case)
bash agent-resources/skills/notes/scripts/new-task.sh "Title" \
  --context "aimemory/2026-05-19.md" --tags foo,bar

# With explicit priority or dependency
bash agent-resources/skills/notes/scripts/new-task.sh "Title" \
  --context "aimemory/2026-05-19.md" --priority high --depends-on 002
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
| `agent-resources/skills/notes/scripts/new-task.sh "title" [opts]` | Create sharded task via tfq | When promoting a TODO to a tracked task |
| `agent-resources/skills/notes/scripts/validate-note.sh <file\|dir>` | Check filename, path, frontmatter | After creating/editing notes; doctor runs this too |
