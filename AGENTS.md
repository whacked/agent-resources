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

When an agent accumulates structured records during exploratory analysis, data generation, ETL, or other long-running work, it must use CPD YAML instead of ad hoc JSONL.

Before accumulation starts, deliberate on the record shape that the producing script or workflow will emit. Encode that shape in the CPD file under `_schemas`, using CUE block syntax when it is concise or JSON Schema in YAML when it is clearer. Prefer `_schemas.data...` for the normal case where the schema describes one record in the `data` table. Declare known enum-like fields as join-table columns when useful, and keep intentionally loose fields in the `payload` catch-all column only when the loose shape is part of the design.

Write accumulated records to `artifacts/records/YYYY/MM/DD/<prefix><slug>.cpd.yaml`. Use the default CPD application-level names unless there is a specific reason not to: `data` as the main data section key and `payload` as the catch-all payload column. If a different data table name or payload column is necessary, make the choice explicit in the CPD structure and in any code or command that reads it by using CPD's `-data-key` or `-payload-column` flags.

When continuing an existing accumulation, read the existing CPD schema before appending. If the existing schema still fits, append only. If later records require a compatible schema expansion, update the schema using CPD's documented schema mechanism, then append. If the new shape is a subset, sibling, or otherwise compatible but requires normalization, migrate the old data into the new CPD schema, update code and pointers to the new file, then remove the obsolete CPD file. If the new shape is incompatible, start a new CPD file with its own schema.

Any CPD schema change, data migration, file replacement, or directive change is a normative report. Pure appends that continue the existing schema unchanged do not require a new report.
