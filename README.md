# agent-resources

Upstream capability repository for AI-assisted notes workflows. Add to any notes repo as a git submodule to get structured note/task management, semantic search, synthesis, and formal artifact tracking.

## What a repo looks like after bootstrap

Below is a small fictitious project. Human writes anywhere in `notes/`; the agent writes only inside `notes/agents/`.

```
my-project/
│
├── notes/                              # your vault — edit freely, structure however you like
│   │
│   ├── pages/
│   │   ├── bandgap-reference.md        # you wrote this
│   │   └── opamp-design.md             # you wrote this
│   │
│   ├── journals/                       # daily notes (e.g. Obsidian daily notes plugin)
│   │   ├── 2026-05-17.md               # you wrote this — can contain todos, rough thoughts
│   │   └── 2026-05-18.md               # you wrote this
│   │
│   ├── project1/
│   │   └── 2025-11-20.md               # you wrote this
│   │
│   └── agents/                         # agent writes here only — do not edit manually
│       │
│       ├── notes/                      # synthesized notes, distillations, digests
│       │   └── 2026/05/18/
│       │       ├── 2026-05-18.001-bandgap-synthesis.md   # agent synthesized from your journals
│       │       └── 2026-05-18.002-weekly-digest.md       # agent weekly summary
│       │
│       └── tasks/                      # tracked tasks, extracted from your notes
│           ├── .taskmd.yaml            # taskmd config (created by bootstrap)
│           └── 2026/05/
│               ├── 001-review-bandgap-sim.md    # agent extracted this from a journal todo
│               └── 002-write-up-opamp.md        # agent created from a meeting note
│
├── agent-resources/                    # this repo — git submodule, don't edit
│   ├── CLAUDE.md                       # agent routing + invariants (auto-loaded)
│   ├── README.md                       # you are here
│   ├── skills/                         # agent capability definitions
│   ├── scripts/                        # management scripts (see below)
│   ├── artifacts/
│   │   ├── reports/                    # formal agent decisions + ADRs
│   │   │   └── 2026/05/18/
│   │   │       └── 2026-05-18.001-switch-to-taskmd.md   # agent wrote, you confirmed
│   │   └── data/                       # accumulated structured data (CPD files)
│   │       └── benchmarks/
│   │           └── sim-runs.cpd.yaml   # agent appends each session; never overwrites
│   │
│   └── docs/agent-guides/              # detailed agent workflow guides
│
├── .claude/
│   └── skills -> agent-resources/skills/   # symlink created by bootstrap
│
└── CLAUDE.md                           # project instructions — bootstrap appends write constraint here
```

### What a journal entry looks like

```markdown
<!-- notes/journals/2026-05-18.md — you wrote this in Obsidian -->

Had a good session on the bandgap circuit today. The PTAT current is tracking well
but there's a corner case at -40°C I haven't resolved yet.

TODO: rerun sim with updated model file
- [ ] check if the 1.2V rail assumption holds at low temp
#ActionItem write up the design rationale before I forget
```

### What the agent produces from it

```markdown
<!-- notes/agents/notes/2026/05/18/2026-05-18.001-bandgap-synthesis.md — agent wrote this -->
---
date: 2026-05-18
author: agent
slug: bandgap-synthesis
source_notes:
  - notes/journals/2026-05-17.md
  - notes/journals/2026-05-18.md
tags: [bandgap, simulation]
---

# bandgap synthesis

Summary of current understanding from recent journal entries.

# Background

PTAT current tracking well. Open issue: corner case at -40°C with 1.2V rail assumption.

# Findings

Three action items extracted and tracked as tasks 001–002.

# Next steps

Rerun sim with updated model file once rail assumption is confirmed.
```

### What a task file looks like

```markdown
<!-- notes/agents/tasks/2026/05/001-review-bandgap-sim.md — agent created via taskmd -->
---
id: "001"
title: "Rerun bandgap sim with updated model file"
status: pending
priority: high
tags: [bandgap, simulation]
context:
  - notes/journals/2026-05-18.md    # source line that originated this task
---
```

---

## Scripts you can use

All scripts live in `agent-resources/`. They work for both the agent and you — the agent
auto-detects it's Claude via `$CLAUDECODE=1`; otherwise they behave as human tools.

**Setup and health:**

```bash
# Wire agent-resources into this repo (run once after cloning):
bash agent-resources/scripts/bootstrap.sh --notes-vault <your-vault-dir>

# Check the whole setup — every line should be PASS:
bash agent-resources/skills/doctor/scripts/check.sh
```

**Creating notes:**

```bash
# Create a new note — lands in <your-vault>/YYYY/MM/DD/ relative to CWD
bash agent-resources/skills/notes/scripts/new-note.sh my-idea

# Open in $EDITOR immediately:
bash agent-resources/skills/notes/scripts/new-note.sh my-idea --edit

# Override destination (e.g. put it somewhere specific):
bash agent-resources/skills/notes/scripts/new-note.sh my-idea --dest-dir notes/pages/
```

**Creating and managing tasks:**

```bash
# Create a tracked task:
bash agent-resources/skills/notes/scripts/new-task.sh "Title of task" --priority high

# List all tasks:
taskmd list --task-dir notes/agents/tasks

# What to work on next (respects dependencies):
taskmd next --task-dir notes/agents/tasks

# Mark a task done:
taskmd set 003 --done --task-dir notes/agents/tasks
```

**Validating notes:**

```bash
# Validate a single note (filename, sharding, frontmatter):
bash agent-resources/skills/notes/scripts/validate-note.sh notes/agents/notes/2026/05/18/2026-05-18.001-bandgap-synthesis.md

# Validate the whole agents/notes/ tree:
bash agent-resources/skills/notes/scripts/validate-note.sh notes/agents/notes/
```

---

## How the system works

The agent reads everything in your vault freely. It writes only to `<notes-vault>/agents/`.
You write anywhere — the agent adapts.

The eventually-consistent loop:

```
you write a journal entry or note
  → agent reads via ov / ck / rg
  → agent synthesizes into agents/notes/ with source_notes: linking back to your files
  → ov index build — backlinks now surface your agent note when browsing your original
  → you see the synthesis in Obsidian, edit your note with new thoughts
  → agent creates a new synthesis with supersedes: pointing to the prior one
  → repeat
```

Agent notes are never edited in place — each new synthesis is a new file. Old ones stay as
audit trail. You can always see what the agent understood at any point in time.

---

## Bootstrapping into a new repo

```bash
# From the target repo root, with agent-resources present:
bash agent-resources/scripts/bootstrap.sh

# Vault is a subdirectory (not repo root):
bash agent-resources/scripts/bootstrap.sh --notes-vault <your-vault>

# Preview without making changes:
bash agent-resources/scripts/bootstrap.sh --dry-run

# Verify the full setup afterward:
bash agent-resources/skills/doctor/scripts/check.sh
```

---

## Required binaries

Install to `$HOME/.local/bin` or anywhere in PATH:

- `taskmd` — task/todo/dependency tracking → see `skills/taskmd/SKILL.md`
- `ov` — Obsidian vault navigation and search → see `skills/ov/SKILL.md`
- `ck` — semantic + hybrid full-repo search → see `skills/ck/SKILL.md`
