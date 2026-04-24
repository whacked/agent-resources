# Agent Directives

## Write agent reports as sharded artifacts

Every agent-generated report, analysis, implementation decision, architectural change, or significant design choice must be recorded as a Markdown file conforming to `schemas/reports.cue.template.md`.

Use `intent: descriptive` when the report only describes what is true. Use `intent: normative` when the report establishes, justifies, or affects a change.

**Location:** `artifacts/reports/YYYY/MM/DD/`
**Filename:** `YYYY-MM-DD.NNN-short-slug.md` (e.g. `2026-04-22.001-replace-metrics-pipeline.md`)

The document must pass validation before being committed:

```
scripts/validate-frontmatter.sh schemas/reports.cue.template.md artifacts/reports/YYYY/MM/DD/<your-report.md>
```

A non-zero exit means the document is invalid and must be corrected before proceeding.

## Manage cumulative data with CPD

Use CPD YAML, not ad hoc JSONL, for accumulated structured records from exploratory analysis, data generation, ETL, or other long-running work.

Before writing records, decide the expanded JSON object shape the workflow emits and encode it under `_schemas`. Prefer CUE block syntax under `_schemas.data...`: the schema describes one expanded record. The `data:` array stores compact rows using declared `_columns`, join tables, data columns, and the default `...` catch-all. Example:

```yaml
_schemas:
  data...: |
    status: "ok" | "fail" | "warn" | null
    name: string
    temperature?: number | null
_columns: [status, ...]
status:
  ok: 1
  fail: 2
  warn: 3
data:
  - [1, {name: "alpha-1", temperature: 22.5}]
  - [2, {name: "beta-1", temperature: null}]
```

Write records to `artifacts/data/<scope-or-dataset-slug>/<dataset-slug>.cpd.yaml`. Continue appending to the same CPD file while the accumulation scope and schema remain compatible; do not rotate files merely because the calendar date changes. Use CPD defaults unless a reader requires otherwise. Check `cpd --help` or `cpd --examples` when unsure.

When continuing an accumulation, read the existing schema first. If it still fits, append. If later records need a compatible schema expansion, update the schema using CPD's documented mechanism, then append. If the new shape is compatible but needs normalization, migrate old data into the new CPD file, update readers and pointers, then remove the obsolete file. If the shape is incompatible, start a new CPD file.

Any CPD schema change, data migration, file replacement, or directive change is a normative report. Pure appends that continue the existing schema unchanged do not require a new report.
