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
