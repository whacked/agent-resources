---
name: taskmd
description: Use this skill when creating, listing, updating, searching, or visualizing tasks tracked as markdown files — including taskmd add, set, list, next, graph, get, status, search, validate, or any other taskmd command.
version: 1.0.0
---

# taskmd — Markdown Task Tracker Skill

`taskmd` manages tasks as individual `.md` files with YAML frontmatter. Each task is a file; the directory is the database.

## Task File Format

```yaml
---
id: "001"
title: "Task title"
status: pending          # pending | in-progress | in-review | completed | blocked | cancelled
priority: medium         # low | medium | high | critical
effort: small            # small | medium | large
type: feature            # feature | bug | improvement | chore | docs
dependencies: ["002"]    # IDs that must complete first
tags: [zettelkasten, ov]
parent: "000"            # optional parent task ID
phase: "v1"              # optional sprint/release grouping
context: ["path/to/relevant/file.md"]  # explicit file links
---

Body text here. Can include [[wiki-links]] to ov vault notes.
```

## Setup

```bash
taskmd init --task-dir ./tasks --claude   # creates tasks/, .taskmd.yaml, agent config
taskmd validate                           # lint all tasks
```

## Common Workflows

### Create tasks
```bash
taskmd add "Task title" --priority high --tags foo,bar
taskmd add "Subtask" --parent 001 --depends-on 002
taskmd add "Bug title" --template bug
```

### View tasks
```bash
taskmd list                              # all tasks
taskmd list --status pending             # filter by status
taskmd list --filter "priority>=high"    # comparison filters
taskmd next                              # ranked: what to work on now
taskmd next --limit 3
taskmd get 001                           # full detail on one task (fuzzy match)
taskmd status                            # in-progress tasks
taskmd search "keyword"                  # full-text search
```

### Update tasks
```bash
taskmd set 001 --status in-progress
taskmd set 001 --done                    # marks completed
taskmd set 001 --add-tag reviewed
taskmd set 001 --depends-on 002,003
```

### Dependency graph
```bash
taskmd graph                             # ascii tree (default)
taskmd graph --format mermaid            # mermaid diagram
taskmd graph --format json               # machine-readable
taskmd graph --root 001 --downstream     # subtree from task
taskmd graph --focus 001                 # highlight one task
```

### Project health
```bash
taskmd stats
taskmd phases                            # progress per phase
taskmd validate                          # lint / warn on bad deps
taskmd board                             # kanban view
taskmd next --critical                   # critical path only
```

### Source code TODOs
```bash
taskmd todos list ./src                  # find TODO/FIXME in source files
```

## Output Formats

All read commands support `--format table|json|yaml`. Use `--format json` for scripting.

## Config (.taskmd.yaml)

```yaml
task_dir: ./tasks
id:
  strategy: sequential   # sequential | prefixed | random | ulid
  padding: 3
phases:
  - id: v1
    name: "Version 1"
    due: 2026-06-01
```

## Key Behaviors

- `dependencies` = blocking: task won't appear in `taskmd next` until deps are completed
- `parent` = organizational grouping only, no status cascading
- `context` field links tasks to specific files — supports `taskmd context <id>` to show them
- `touches` field declares code scope — used by `taskmd tracks` to detect parallel work conflicts
- Task files are plain markdown — readable and editable without the CLI
