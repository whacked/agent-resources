---
name: audit-skills
description: Use this skill when the user asks to audit, review, or improve Claude skills — checking for risky auto-invocation, deterministic steps that should be scripts, or duplicated logic across skills.
version: 1.0.0
---

# audit-skills

Audit the skills in `.claude/skills/` (i.e. `./skills/`) for three issues:

## 1. Visibility / Invocation Safety

- Skills with high-risk side effects (deploy, commit, send messages, delete): flag for `disable-model-invocation: true` so Claude can't auto-fire them.
- Skills that are pure background knowledge a user would never `/run` themselves: flag for `user-invocable: false` to hide from the menu.

## 2. Deterministic vs Non-Deterministic Steps

- Find any step inside a skill where Claude is interpreting something that is actually a fixed, repeatable operation.
- Suggest replacing those steps with a script saved inside the skill folder. Code = same result every time, no token cost.
- Keep Claude for steps that genuinely need judgment.

## 3. Composability

- Flag any skill that duplicates logic another skill already has.
- Suggest extracting shared logic into a callable script or a smaller composable skill.

## Output Format

For each finding, show:
- Which skill and what issue was found
- A rewritten snippet or proposed change
- A one-line changelog entry: what changed and why
