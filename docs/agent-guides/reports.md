# Agent Report Guide

Write every agent-generated report, analysis, implementation decision, architectural change, or significant design choice as a Markdown file conforming to `schemas/reports.cue.template.md`.

Use `intent: descriptive` when the report only describes what is true. Use `intent: normative` when the report establishes, justifies, or affects a change.

## Location and naming

- Location: `artifacts/reports/YYYY/MM/DD/`
- Filename: `YYYY-MM-DD.NNN-short-slug.md`
- Example: `2026-04-22.001-replace-metrics-pipeline.md`

## Validation

Run this before committing a report:

```sh
scripts/validate-frontmatter.sh schemas/reports.cue.template.md artifacts/reports/YYYY/MM/DD/<your-report.md>
```

A non-zero exit means the report is invalid and must be corrected before proceeding.
