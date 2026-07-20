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
  - [2, {name: "beta-1", temperature: ~}]
```

## Write compactly

The `data:` array is where a CPD file spends most of its bytes. Three habits keep accumulated files small and readable, and all three must be applied at write time — reshaping a compaction choice afterward is a migration, not an append.

1. **Null is `~`.** Write null as `~` (1 byte), not `null` (4 bytes) — valid YAML everywhere in a row, saving 3 bytes per occurrence, which adds up over a long file. This holds in positional slots and inside splat dicts alike; cpd itself emits `~` when it compacts.

2. **Declare known categoricals as join tables.** When you already know a field is categorical before writing — campaign name, publisher, book title, artist, album, model id — make it a join table so the repeated string is stored once and each row carries a small integer instead. cpd auto-promotes low-cardinality strings, but auto-detection only sees the current batch; when you know the category up front, force it rather than hope: `-join-tables campaign,publisher` on ingestion, or hand-author the `_columns` entry plus its `name: int` mapping. Join columns go before the splat `...`.

3. **Push a size-dominating payload to the end.** When one field dominates row size — a lyrics string, a document body, a raw response blob — make it the last column and write it as a YAML block scalar (`|-`) so it stays human-readable. A block scalar cannot sit inside a flow `[...]` row, so that row must be written in block style. Two forms:
   - a dedicated trailing column — `_columns: [..., lyrics]`, value is the bare `|-` block;
   - inside the splat `...` catch-all — wrap it in a dict so the field key survives: `{lyrics: |- ...}`.

   ```yaml
   _columns: [artist, album, ...]
   artist: {radiohead: 1}
   album: {ok-computer: 1}
   data:
     - - 1
       - 1
       - released: "1997-05-21"
         lyrics: |-
           In the next world war
           In a jackknifed juggernaut
   ```

   This is a deliberate trade: the row grows taller but reads cleanly. Apply it **only** when a payload actually dominates. For highly structured rows with no dominant field, do the opposite — keep compact flow arrays (`- [1, ~, "alpha"]`) with the `~` trick; plain arrays are both smaller and easier to scan.

## Store by dataset

Write records to `$NOTES_WORKSPACE/artifacts/data/<scope-or-dataset-slug>/<dataset-slug>.cpd.yaml` (`$NOTES_WORKSPACE` resolves env → git toplevel → CWD; see `scripts/lib/workspace.sh`). Continue appending to the same CPD file while the accumulation scope and schema remain compatible; do not rotate files merely because the calendar date changes.

Use CPD defaults unless a reader requires otherwise. Check `cpd --help` or `cpd --examples` when unsure.

For long-lived datasets, add `$NOTES_WORKSPACE/artifacts/data/<scope-or-dataset-slug>/README.md` with the dataset purpose, active CPD file, schema lineage, append policy, and migration notes.

## Evolve deliberately

When continuing an accumulation, read the existing schema first. If it still fits, append. If later records need a compatible schema expansion, update the schema using CPD's documented mechanism, then append.

If the new shape is compatible but needs normalization, migrate old data into the new CPD file, update readers and pointers, then remove the obsolete file. If the shape is incompatible, start a new CPD file.

Any CPD schema change, data migration, file replacement, or directive change is a normative report. Pure appends that continue the existing schema unchanged do not require a new report.
