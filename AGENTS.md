# Agent Directives

## Document every decision as an ADR

Every implementation decision, architectural change, or significant design choice must be recorded as a Markdown file conforming to `schemas/adr.cue.template.md`.

**Location:** `docs/adr/`  
**Filename:** `YYYY-MM-DD.NNN-short-slug.md` (e.g. `2026-04-22.001-replace-metrics-pipeline.md`)

The document must pass validation before being committed:

```
scripts/validate-frontmatter.sh schemas/adr.cue.template.md docs/adr/<your-adr.md>
```

A non-zero exit means the document is invalid and must be corrected before proceeding.
