---
name: tfq
description: Use this skill for note, task, and frontmatter operations over a directory of frontmatter'd markdown — searching, reading, listing, or linking notes (supersedes ov); creating, listing, updating, sequencing, or graphing tasks and their dependencies (supersedes taskmd); and validating frontmatter against a CUE schema (supersedes cue). One index-free binary; semantic search stays with ck.
version: 1.0.0
---

# tfq — one binary for notes, tasks, and frontmatter validation

`tfq` (text-file query) treats a directory of frontmatter'd text files as
**records forming a typed graph** and exposes read + write + validate over them.
It supersedes three tools in this repo:

| Was | Now | Note |
|---|---|---|
| `ov` (vault read/search/links/tags) | `tfq --show / <search> / --links / --backlinks / --tags` | **index-free** — no `ov index build` |
| `taskmd` (tasks + dependency graph) | `tfq --task / --list / --next / --set / --done / --graph` | same one-file-per-record model, `dependencies` blocks `--next` |
| `cue` (frontmatter `cue vet`) | `tfq --validate FILE --schema TPL` | **bundles cuelang** — no `cue` binary |

Not covered: semantic / embedding search — keep `ck`. tfq also shells to `rg`
(required) and pairs with `jq` for `--json` output.

## Mental model

A *collection* is a directory; each file is a *record* = `{path, frontmatter,
headings, links, markers}`. Edges come from body links (`[[wiki]]`, markdown,
org) and frontmatter fields (`dependencies`, `parent`). One record = one file.
No index, no services; search is ripgrep over plaintext.

**Collection root** — every call needs to know which collection it is on:
`--root DIR` → `$TFQ_ROOT` → nearest ancestor with `.tfq.cue`/`.tfq.yaml`/`.tfq/`
→ cwd. In this repo, agent tasks and notes are **separate collections**, so pass
`--root` explicitly: `--root agents/tasks` or `--root agents/notes`.

## The querying funnel (ov replacement)

```bash
tfq --root <vault> battery supply        # 1. discover: ripgrep-style search of bodies
tfq --root <vault> battery --in heading  # 2. narrow: keep matches inside heading|tag|link
tfq --root <vault> -i -l battery         # 3. reduce: -i case-insensitive, -l files-only, -c counts
tfq --root <vault> --show <ref>          # one record (--raw body-only, --frontmatter meta-only)
tfq --root <vault> --links <ref>         # outbound + inbound (--backlinks = inbound only)
tfq --root <vault> --tags                # tag index    --types = frontmatter type: index
tfq --root <vault> --list --tag power    # list records (filters: --type T, --tag T×, --status S, --limit N)
```

Each search hit is labeled by where it landed (`[heading]`, `[tag]`, `[link]`).
`<ref>` resolves by path, basename, seq-stripped basename (`001-x.md`→`x`), or
frontmatter `id`/`slug`/`title`.

## Tasks + dependencies (taskmd replacement)

Prefer `skills/notes/scripts/new-task.sh` for *creating* agent tasks (it pins
`--root agents/tasks`, shards into `YYYY/MM/`, and translates `--tags`/`--context`).
The raw verbs:

```bash
tfq --root agents/tasks --task --title "Audit vendors" --priority high --depends-on 001,002
tfq --root agents/tasks --list --status pending      # filtered list
tfq --root agents/tasks --next                       # ready tasks (deps satisfied)
tfq --root agents/tasks --set 003 --status in-progress
tfq --root agents/tasks --done 003                   # mark completed
tfq --root agents/tasks --graph                      # all resolved dependency edges
```

`--task` is `--new --type task`. Task fields: `--priority P` · `--effort E` ·
`--parent REF` · `--depends-on REF[,REF]` · `--tag T`× · `--field k=v`. Writes
preserve body + key order. A task stays out of `--next` until every ref in its
`dependencies` is done.

## Frontmatter validation (cue replacement)

```bash
tfq --validate FILE --schema TPL    # one file vs a schema; exit 0 ok, 1 violations
tfq --validate [--strict]           # whole collection vs the discovered .tfq.cue
```

`--schema` reads a `.cue` file **or** the first ```` ```cue ```` block inside a
markdown template (e.g. `schemas/reports.cue.template.md`,
`skills/notes/schemas/notes.cue.template.md`). Semantics match `cue vet`
exactly, including RE2 `=~` regex constraints and date normalization. This is
what `scripts/validate-frontmatter.sh` and `validate-note.sh` call under the hood
— use those for the full note/report check (they add filename + H1-order checks
tfq does not do by design).

## Output & exit codes

`--json` for tooling (shapes are stable, pipe to `jq`); `--color auto|always|never`
(honors `NO_COLOR`). Exit codes: `0` ok · `1` runtime / validate-not-ok · `2`
usage. Writes hard-error on an ambiguous `<ref>`.

Run `tfq --help` for the full flag reference and `tfq --examples` for the
extended agent guide.
