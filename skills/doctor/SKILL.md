---
name: doctor
description: Use this skill when the user asks to check, verify, or repair the project setup — confirming binaries are installed, vault indexes built, agent directory structure exists, ck index is present, skills are registered, and agent notes have correct provenance frontmatter.
version: 2.0.0
---

# doctor

Validates the full project setup: binaries (`tfq` + `rg`/`jq`, with `ck`/`cpd` optional), agent directory structure, note sharding, frontmatter validity, ck index, skill registration, supersession link consistency, and provenance compliance.

## Run the check

```bash
bash /workspace/skills/doctor/scripts/check.sh
```

Each line is `PASS`, `FAIL`, or `WARN`.
- `FAIL`: blocking — the fix command is shown on the next line. Run it, then re-run the script.
- `WARN`: non-blocking — advisory, may degrade functionality.

## After running

- All `PASS`: report ready.
- Any `FAIL`: run each fix in order shown, then re-run to confirm clean.
- Do not guess fixes — the script tells you exactly what to run.

## Supersession janitor

The check verifies that every superseded file carries the reverse edge (`superseded_by:` + `status: superseded`) implied by the forward `supersedes:` edges. The forward edge is the source of truth; the janitor recomputes each `superseded_by` list from it (fork-safe, idempotent). Repair reported drift with:

```bash
bash /workspace/skills/doctor/scripts/supersession-repair.sh --root <collection> --fix
```

Run it on any collection — `agents/notes`, `artifacts/reports`, or another repo — to ensure both link directions exist. Drop `--fix` for a read-only check (exit 1 on drift).
