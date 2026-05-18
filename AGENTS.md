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
- Never edit a prior report's body — supersede it with a new file using `supersedes:` frontmatter

## Write constraint

Agent output in the notes repo goes to the `agents/` subdirectory of the notes vault only. The exact path is specified in the root `CLAUDE.md`. Never write to the human edited vault outside that path.
