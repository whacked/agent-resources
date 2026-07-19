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

## Supersession (bidirectional)

Reports are immutable once written — **never edit a prior report's body**. To revise a decision, write a **new** report carrying `supersedes: <prior-slug>` (the authoritative forward edge), then record the reverse edge on the superseded report so its obsolescence is visible without running a tool:

- set its `status: superseded`
- add the new report's slug to its `superseded_by:` list (a **list** — a report can be superseded by more than one successor)

`superseded_by` and `status` are the only frontmatter fields you may change on an already-written report; the body stays immutable. Forward `supersedes` is the source of truth. Write and verify both ends with tfq (`<slug>` is the filename without `.md`; refs resolve across `YYYY/MM/` shards):

```sh
# forward edge — usually already set when the new report is created
tfq --root "$NOTES_WORKSPACE/artifacts/reports" --set <new-slug> --field supersedes=<prior-slug>

# reverse edge — one call sets both fields on the prior report
tfq --root "$NOTES_WORKSPACE/artifacts/reports" --set <prior-slug> \
    --field-list superseded_by=<new-slug> --field status=superseded
```

`--field-list` **replaces** the list — if the prior report already has successors, include them all. The safe way to reconcile (recomputes the full `superseded_by` set from the forward edges, fork-safe and idempotent) is the `doctor` supersession janitor:

```sh
bash <install>/skills/doctor/scripts/supersession-repair.sh --root "$NOTES_WORKSPACE/artifacts/reports"        # check (exit 1 on drift)
bash <install>/skills/doctor/scripts/supersession-repair.sh --root "$NOTES_WORKSPACE/artifacts/reports" --fix  # apply
```
