---
name: doctor
description: Use this skill when the user asks to check, verify, or repair the project setup — confirming binaries are installed, vault indexes built, agent directory structure exists, ck index is present, skills are registered, and agent notes have correct provenance frontmatter.
version: 2.0.0
---

# doctor

Validates the full project setup: binaries, ov vaults, taskmd, ck index, agent directory structure, skill registration, and provenance compliance.

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
