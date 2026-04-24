# CPD Cumulative Data Guide

Use CPD YAML, not ad hoc JSONL, for accumulated structured records from exploratory analysis, data generation, ETL, or other long-running work.

## Shape records first

Before writing records, decide the expanded JSON object shape the workflow emits and encode it under `_schemas`. Prefer CUE block syntax under `_schemas.data...`: the schema describes one expanded record. The `data:` array stores compact rows using declared `_columns`, join tables, data columns, and the default `...` catch-all.

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

## Store by dataset

Write records to `artifacts/data/<scope-or-dataset-slug>/<dataset-slug>.cpd.yaml`. Continue appending to the same CPD file while the accumulation scope and schema remain compatible; do not rotate files merely because the calendar date changes.

Use CPD defaults unless a reader requires otherwise. Check `cpd --help` or `cpd --examples` when unsure.

For long-lived datasets, add `artifacts/data/<scope-or-dataset-slug>/DATASET.md` with the dataset purpose, active CPD file, schema lineage, append policy, and migration notes.

## Evolve deliberately

When continuing an accumulation, read the existing schema first. If it still fits, append. If later records need a compatible schema expansion, update the schema using CPD's documented mechanism, then append.

If the new shape is compatible but needs normalization, migrate old data into the new CPD file, update readers and pointers, then remove the obsolete file. If the shape is incompatible, start a new CPD file.

Any CPD schema change, data migration, file replacement, or directive change is a normative report. Pure appends that continue the existing schema unchanged do not require a new report.
