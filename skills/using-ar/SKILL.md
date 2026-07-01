---
name: using-ar
description: Routing index for the ar skills bundle — read this to send a request to the right ar skill or guide (notes/tasks, synthesis, reports, CPD data, search, setup checks).
---

# using-ar — routing index for the ar bundle

The `ar` bundle installs as one extension. Its skills surface as `ar:notes`, `ar:synthesize`, `ar:doctor`, `ar:tfq`, `ar:ck`, `ar:audit-skills`. Bundled files named below (guides, schemas, scripts) are **relative to this extension's root** — the SessionStart hook prints that absolute root above this text. All agent **writes** go under `$NOTES_WORKSPACE` (resolved env → git toplevel → CWD by `scripts/lib/workspace.sh`).

## Route by intent

| If the user wants to… | Do this |
|---|---|
| create / find / validate a note or task | invoke `ar:notes` |
| synthesize journals, meetings, or fragments into something coherent | invoke `ar:synthesize` |
| record a decision, architectural/schema change, or write a formal report or ADR | read `docs/agent-guides/reports.md`; write to `$NOTES_WORKSPACE/artifacts/reports/YYYY/MM/`; validate with `scripts/validate-frontmatter.sh schemas/reports.cue.template.md <file>` |
| accumulate append-only structured records (API JSONL ingestion, ETL, data generation) | read `docs/agent-guides/cpd-data.md`; write to `$NOTES_WORKSPACE/artifacts/data/<scope>/<dataset>.cpd.yaml` |
| keyword / structured / task-graph search over markdown | invoke `ar:tfq` |
| semantic / concept / hybrid search | invoke `ar:ck` |
| check / verify / repair the setup, or preflight dependencies | invoke `ar:doctor` |
| audit or review skills | invoke `ar:audit-skills` |

Reports are prose markdown — not a skill, never CPD-formatted. CPD is for append-only data, never the path for writing reports.
