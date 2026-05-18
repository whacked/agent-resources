---
name: synthesize
description: Use this skill when reading accumulated material — daily notes, meeting minutes, TILs, tasks, scratchpads, fragments, CPD data files — and reprocessing it into something more coherent, structured, or actionable. Covers weekly digests, fragment merges, task deduplication, debug distillation, meeting sync, ADR creation, and synthesis over multi-session structured data. May involve back-and-forth Q&A before committing output.
version: 1.0.0
---

# synthesize — Read a Bunch of Stuff, Make Something Better

This skill handles the family of operations where accumulated raw material needs to become more integrated, structured, or actionable. The output format, the relationship to prior content, and whether to ask for confirmation first all depend on what the material is and what the human needs.

---

## Step 1 — Identify the mode

Read the human's request and categorize it. The mode determines everything that follows.

| Mode | Signal phrases | Output |
|---|---|---|
| **Periodic digest** | "weekly wrap", "what happened Mon-Thu", "week 21 status" | New dated summary note; sources intact |
| **Fragment merge** | "combine my DuckDB notes", "merge these TILs", "make one note from these" | New reference note; old ones marked superseded in new note's frontmatter |
| **Task deduplication** | "these todos are all the same thing", "aggregate these into one task" | New tracked task; annotation in synthesis note pointing to sources |
| **Distillation** | "extract the useful bits", "clean up this scratchpad", "turn this mess into a recipe" | New clean note with distilled knowledge; archive raw material |
| **Live doc sync** | "update the roadmap", "sync meeting minutes into the project doc" | New agent synthesis capturing current state; flag human to update their doc |
| **ADR / decision record** | "write up the decision", "formalize this architecture choice", "record why we picked X" | Formal report via agent-resources pathway; confirm with human before committing |
| **Multi-session data synthesis** | "combine my benchmark runs", "what does the accumulated data show", "roll up these analysis sessions" | CPD append for new session records + synthesis note for narrative insights; see CPD section |

If the request spans multiple modes (e.g. merge fragments AND create a tracked task), handle them in sequence.

---

## Step 2 — Discover all relevant material

Cast wide first, then read everything that surfaces.

```bash
# Semantic sweep across full repo
cd /workspace && ck --hybrid "<topic or phrase>" . --limit 20

# Time-bounded search (for periodic digests)
find <vault>/journals -name "*.md" -newer <vault>/journals/YYYY-MM-DD.md | sort
rg -l "<topic>" <vault>/journals/ --include="*.md"

# Task picture
taskmd list --task-dir agents/tasks --format json
taskmd graph --task-dir agents/tasks

# Open action items in human notes
rg -n "TODO|FIXME|#todo|#TODOS|#ActionItem|\- \[ \]" \
   --type md . --no-heading

# Prior agent synthesis
rg "slug:" agents/notes/ --include="*.md" -l
ov backlinks "<canonical-note>" --vault <vault>/pages

# CPD data files (structured multi-session records)
find agent-resources/artifacts/data -name "*.cpd.yaml" 2>/dev/null
find agent-resources/artifacts/data -name "*.cpd.yaml" | xargs grep -l "<topic>" 2>/dev/null
```

Read the full content of everything that surfaces. Don't skim.

**Reading CPD files:** CPD YAML is human-readable directly. For processing records programmatically, convert to JSONL first:
```bash
cpd agent-resources/artifacts/data/<scope>/<file>.cpd.yaml  # → JSONL to stdout
cpd agent-resources/artifacts/data/<scope>/<file>.cpd.yaml -sql  # → SQLite DDL+INSERT for querying
```

---

## Step 3 — Assess what you have

Before writing anything, answer these explicitly:

1. **What is the current state of understanding on this topic?**
2. **Does prior agent synthesis exist?** If yes: is it still accurate, stale, or contradicted?
3. **Are tasks involved?** Are any redundant, subsumed, or now clearly defunct?
4. **Is this a decision that needs human confirmation before being committed?** (ADR mode)
5. **Does any output require writing to human-authored notes?** (You can't — see constraint below.)

---

## CPD and structured data sessions

CPD files accumulate structured records across sessions — benchmark results, analysis outputs, ETL batches. They are a *source* for synthesis and sometimes an *output target*. The two are different operations that often need to happen together.

**Is the right output a CPD append, a synthesis note, or both?**

```
New session of structured data to record?
└── Yes → append records to the CPD file for this dataset
    (read agent-resources/docs/agent-guides/cpd-data.md for schema/migration rules)
    ├── Schema unchanged → append directly
    ├── Schema expanding → update schema, then append
    └── Incompatible shape → start new CPD file, write normative report

Reached a synthesis milestone (enough data to draw conclusions)?
└── Yes → synthesize narrative note over the CPD data
    Read the CPD: cpd <file>.cpd.yaml → JSONL, then analyze
    Output: synthesis note in agents/notes/ with source_notes: pointing to the CPD file

Both new data AND milestone insight?
└── Yes → append first, then synthesize over the updated file
```

**What CPD data looks like as a synthesis source:**

After converting to JSONL, you have one JSON object per record. Look for:
- Trends across sessions (metric improving/degrading over time)
- Outliers or anomalies
- Schema drift that signals a changing problem shape
- The aggregate picture the individual sessions couldn't show

The synthesis note summarizes these insights in prose. The CPD file remains the authoritative structured record. Both are linked via `source_notes:` in the note.

**Where CPD files live:**
```
agent-resources/artifacts/data/<scope-slug>/<dataset-slug>.cpd.yaml
```

**Do not** append session data to a synthesis note. Notes are narrative; CPD files are data. Keep them separate.

---

## The write constraint

**Agent cannot write to the human vault except inside `agents/`.**

This affects several modes:

- **Fragment merge**: cannot tag old human notes as #superseded. Instead: mark them superseded via `supersedes:` in the new note's frontmatter, and tell the human "you may want to add #superseded to these source files."
- **Task deduplication**: cannot delete or check off - [ ] items in human journals. Instead: create the consolidated task, add a comment in the synthesis note linking back to source lines, and tell the human "these items in [files] are now tracked as task NNN — you may want to mark them done."
- **Live doc sync**: cannot update the human's Project Roadmap. Instead: create an agent synthesis note capturing current state, and tell the human "your roadmap needs these updates: [list]."
- **Archive raw logs**: can only move files within `agents/`. If the raw scratchpad is a human note, leave it in place and just create the clean distillation in `agents/notes/`.

When you hit the write constraint, always do two things: (1) produce the agent-side output you can produce, and (2) give the human a concrete list of the manual changes they should make on their side.

---

## Step 4 — Choose output structure

**Do not force every output into the same template.** Choose structure based on content type:

| Output type | Structure |
|---|---|
| Weekly digest / periodic summary | Dated note: `## Progress`, `## Decisions`, `## Open items`, `## Next week` |
| Reference guide (merged TILs) | Topic note: subheaders per subtopic, no fixed section order |
| Distilled recipe / troubleshooting | `## Symptom`, `## Root cause`, `## Fix`, `## Why it works` |
| Current-state sync (meeting trail) | `## Current state`, `## Key changes`, `## Audit trail` (links to each meeting) |
| ADR / decision record | Use formal report format — see below |
| Task consolidation | Task file via `new-task.sh` + a synthesis note linking source fragments |

---

## Step 5 — Choose the relation to prior content

```
Prior synthesis exists?
├── No → synthesizes: all sources (first synthesis)
├── Yes, still accurate → expands-on: prior, synthesizes: new sources
├── Yes, stale / contradicted → supersedes: prior, synthesizes: new sources
└── Yes, valid but want a new entry point → synthesizes: [prior, new sources]
    (prior stays as detailed record; new note is the "start here")

Is this a periodic summary?
└── Always → summarizes: sources in period; never supersedes anything

New tasks implied?
├── Yes → new-task.sh, set dependencies: on related tasks
└── Existing tasks redundant → taskmd set NNN --status cancelled
    (cancelled, not deleted — the record stays)
```

---

## Step 6 — For ADR / normative decisions: confirm before committing

If the output is a formal architectural decision or directive change:

1. **Draft the ADR in the conversation first.** Present the Context, Analysis, Decision, and Consequences sections.
2. **Ask the human to confirm or correct** — especially the Decision section.
3. **Only after confirmation**, create the file:

```bash
# ADR goes via the formal report pathway, not new-note.sh
# Read agent-resources/AGENTS.md and agent-resources/docs/agent-guides/reports.md first
# File lands in agent-resources/artifacts/reports/YYYY/MM/DD/
# Validate with agent-resources/scripts/validate-frontmatter.sh
```

Do not commit an ADR speculatively. The `intent: normative` report format exists precisely because these decisions matter and should be reviewed.

---

## Step 7 — Create output

```bash
# For notes (all modes except ADR)
bash agent-resources/skills/notes/scripts/new-note.sh <slug>
# Fill in source_notes:, supersedes: (if applicable), tags:, relations:

# For tasks
bash agent-resources/skills/notes/scripts/new-task.sh "Title" --priority <p> --depends-on <NNN>
# Then open the file and set context: to source files

# For cancelling defunct tasks
taskmd set NNN --status cancelled --task-dir agents/tasks

# For archiving (only files already in agents/)
mkdir -p agents/archive && mv agents/notes/.../file.md agents/archive/
```

### Relations frontmatter

```yaml
relations:
  - type: synthesizes
    target: "[[<vault>/aimemory/2025-11-20]]"
  - type: supersedes
    target: "[[agents/notes/2026/04/01/2026-04-01.001-prior]]"
  - type: expands-on
    target: "[[agents/notes/2026/03/15/2026-03-15.002-survey]]"
  - type: summarizes
    target: "[[<vault>/journals/2026-05-12]]"
  - type: contradicts
    target: "[[<vault>/pages/old-assumption]]"
```

---

## Step 8 — Tell the human what they need to do manually

Always close with a concrete list of any manual changes that fall outside the write constraint:

```
## For you to do (agent can't edit these)
- <vault>/journals/2026-05-13.md line 7: the "- [ ] debug memory leak" is now task 004 — mark it done
- <vault>/pages/duckdb-memory-limits.md: consider adding #superseded tag (replaced by agents/notes/...)
- Your Project Roadmap needs: update owner from Alice → Bob, deadline → 2026-07-01
```

---

## After all output is created

```bash
bash agent-resources/skills/notes/scripts/validate-note.sh agents/notes/
ov index build --vault <vault>/pages
ov index build --vault <vault>/aimemory
ov index build --vault <vault>/journals
```
