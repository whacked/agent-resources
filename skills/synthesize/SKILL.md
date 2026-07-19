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
| **Fragment merge** | "combine my DuckDB notes", "merge these TILs", "make one note from these" | New reference note; a superseded prior agent note gets both supersession edges; human sources recorded in `source_notes:` |
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
# Semantic sweep across full repo (.ckignore handles binary/data exclusions)
ck --hybrid "<topic or phrase>" . --limit 20

# Time-bounded search (for periodic digests)
find <vault>/journals -name "*.md" -newer <vault>/journals/YYYY-MM-DD.md | sort
rg -l "<topic>" <vault>/journals/ --include="*.md"

# Existing tracked tasks — check BEFORE creating new ones to catch blocking relationships
tfq --root agents/tasks --list
tfq --root agents/tasks --graph

# Open action items in human notes
rg -n "TODO|FIXME|#todo|#TODOS|#ActionItem|\- \[ \]" \
   --type md . --no-heading

# Prior agent synthesis
rg "slug:" agents/notes/ --include="*.md" -l
tfq --root <vault>/pages --backlinks "<canonical-note>"

# CPD data files (structured multi-session records)
find $NOTES_WORKSPACE/artifacts/data -name "*.cpd.yaml" 2>/dev/null
find $NOTES_WORKSPACE/artifacts/data -name "*.cpd.yaml" | xargs grep -l "<topic>" 2>/dev/null
```

Read the full content of everything that surfaces. Don't skim.

**Reading CPD files:** CPD YAML is human-readable directly. For processing records programmatically, convert to JSONL first:
```bash
cpd $NOTES_WORKSPACE/artifacts/data/<scope>/<file>.cpd.yaml  # → JSONL to stdout
cpd $NOTES_WORKSPACE/artifacts/data/<scope>/<file>.cpd.yaml -sql  # → SQLite DDL+INSERT for querying
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
    (read the bundled docs/agent-guides/cpd-data.md for schema/migration rules)
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
$NOTES_WORKSPACE/artifacts/data/<scope-slug>/<dataset-slug>.cpd.yaml
```

**Do not** append session data to a synthesis note. Notes are narrative; CPD files are data. Keep them separate.

---

## The write constraint

**Agent cannot write to the human vault except inside `agents/`.**

This affects several modes:

- **Fragment merge**: cannot tag or back-annotate old human notes. Record every source in `source_notes:`. If a **single prior _agent_ note** is fully obsoleted, set `supersedes:` on the new note and back-annotate that note's `superseded_by:`/`status:` (the bidirectional rule — see the notes skill). Merging several predecessors into one is not yet expressible via the scalar `supersedes:` (deferred); list them in `source_notes:` and tell the human "you may want to add #superseded to these source files."
- **Task deduplication**: cannot delete or check off - [ ] items in human journals. Instead: create the consolidated task, add a comment in the synthesis note linking back to source lines, and tell the human "these items in [files] are now tracked as task NNN — you may want to mark them done."
- **Live doc sync**: cannot update the human's Project Roadmap. Instead: create an agent synthesis note capturing current state, and tell the human "your roadmap needs these updates: [list]."
- **Archive raw logs**: can only move files within `agents/`. If the raw scratchpad is a human note, leave it in place and just create the clean distillation in `agents/notes/`.

When you hit the write constraint, always do two things: (1) produce the agent-side output you can produce, and (2) give the human a concrete list of the manual changes they should make on their side.

---

## Step 4 — Choose output structure

**Do not force every output into the same template.** Choose structure based on content type:

**`# Background` rule:** Background states *scope* — what vault, what time range, what patterns searched. It does NOT narrate methodology ("I ran rg then ck"). Methodology belongs in the skill. A future reader of the note should learn *what was covered*, not *how the agent worked*.

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
└── Existing tasks redundant → tfq --root agents/tasks --set NNN --status cancelled
    (cancelled, not deleted — the record stays)
```

**Only `supersedes:` and `source_notes:` are frontmatter fields in this tree.** `supersedes` is bidirectional now — when you supersede a prior agent note, also set the reverse `superseded_by:`/`status:` on it (notes skill, step 4). `synthesizes`/`expands-on`/`summarizes` are descriptive labels recorded via `source_notes:` and body `[[links]]`, not schema fields (see Typed relations below).

---

## Step 6 — For ADR / normative decisions: confirm before committing

If the output is a formal architectural decision or directive change:

1. **Draft the ADR in the conversation first.** Present the Context, Analysis, Decision, and Consequences sections.
2. **Ask the human to confirm or correct** — especially the Decision section.
3. **Only after confirmation**, create the file:

```bash
# ADR goes via the formal report pathway, not new-note.sh
# Read the bundled AGENTS.md and docs/agent-guides/reports.md first
# File lands in $NOTES_WORKSPACE/artifacts/reports/YYYY/MM/
# Validate with <install>/scripts/validate-frontmatter.sh
```

Do not commit an ADR speculatively. The `intent: normative` report format exists precisely because these decisions matter and should be reviewed.

---

## Step 7 — Create output

```bash
# For notes (all modes except ADR)
bash <notes-skill>/scripts/new-note.sh <slug>
# Fill in source_notes:, supersedes: (if applicable), tags:

# For tasks — always use action-item template for scraped items; always set context
bash <notes-skill>/scripts/new-task.sh "Title" \
  --template action-item --context "<source-file>" [--priority high|low] [--depends-on <NNN>]

# After ALL tasks are created, run graph and reason about dependencies:
# tfq --root agents/tasks --graph
# For each pair where B cannot logically start until A is done, set dependencies: ["NNN"] in B's frontmatter

# For cancelling defunct tasks
tfq --root agents/tasks --set NNN --status cancelled

# For archiving (only files already in agents/)
mkdir -p agents/archive && mv agents/notes/.../file.md agents/archive/
```

### Typed relations

Supersession uses the dedicated bidirectional fields `supersedes:` (forward, scalar)
and `superseded_by:` (reverse, list) — **not** a relations block. See the notes skill
and `docs/agent-guides/reports.md`.

Other typed relations (`synthesizes`, `expands-on`, `summarizes`, `contradicts`) have
no schema field yet; express them through `source_notes:` plus `[[body links]]`. When
real demand appears, the sanctioned form is a map keyed by relation type:

```yaml
relations:
  synthesizes: [2025-11-20-aimemory, 2026-03-15.002-survey]
  contradicts: [old-assumption]
```

Do not hand-author a `relations:` block until that field is added to the schema.

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
bash <notes-skill>/scripts/validate-note.sh agents/notes/
# tfq is index-free — no index-build step. (Obsidian keeps its own backlink
# index for human browsing, independently of the agent loop.)
```
