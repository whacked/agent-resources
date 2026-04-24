# Agent Directives

This file is a routing layer. When a task matches a workflow below, read the linked guide before creating or changing the matching artifacts.

## Workflow guides

- Reports: before writing or editing `artifacts/reports/**`, read `docs/agent-guides/reports.md`.
- Cumulative data: before creating, appending, migrating, or replacing accumulated structured data, read `docs/agent-guides/cpd-data.md`.

## Invariants

- Every agent-generated report, analysis, implementation decision, architectural change, or significant design choice must be recorded as a report artifact.
- Any directive change, CPD schema change, data migration, or data file replacement is a normative report.
- Pure CPD appends under an existing compatible schema do not require a new report.
