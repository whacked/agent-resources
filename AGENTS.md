# Agent directives — agent-resources

Read this before creating or modifying any artifact in this directory.

## Routing

- **Creating or managing notes/tasks**: read `skills/notes/SKILL.md` first
- **Writing to `artifacts/reports/`**: read `docs/agent-guides/reports.md` first
- **Writing or appending CPD data files**: read `docs/agent-guides/cpd-data.md` first

## Invariants

- Every significant agent decision, architectural change, schema change, or directive change must be recorded as a report in `artifacts/reports/`
- Any CPD schema change, data migration, or data file replacement requires a normative report
- Pure CPD appends under an existing compatible schema do not require a report
- Never edit a prior report's or note's **body** — supersede it with a new file carrying `supersedes:` (the authoritative forward edge)
- Supersession is **bidirectional**: also record the reverse edge on the superseded file — its `superseded_by:` list and `status: superseded`. The body stays immutable; `superseded_by` and `status` are the only frontmatter fields allowed to change post-hoc. Forward `supersedes:` wins on any disagreement; the `doctor` supersession janitor reconciles drift

## Write constraint

Agent output in the notes repo goes to the `agents/` subdirectory of the notes vault only. The exact path is specified in the root `CLAUDE.md`. Never write to the human edited vault outside that path.

## Consumer routing (when this repo is installed as the `ar` extension)

When a workspace has this extension installed, route requests using `skills/using-ar/SKILL.md` — it maps intents (notes, synthesis, reports, CPD, search, doctor) to the right `ar:` skill or bundled guide. Agent writes resolve under `$NOTES_WORKSPACE` (env → git toplevel → CWD).
