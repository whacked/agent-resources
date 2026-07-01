# agent-resources

A cross-harness **skills extension** for AI-assisted notes workflows: structured note/task management, semantic search, synthesis, and formal artifact tracking. One GitHub repo, installable into Claude Code, Codex, Gemini, and OpenCode.

The design has two clean halves:

- **The extension (read-only capability)** — the skills, scripts, and schemas in this repo. You install it into your agent harness; it lives in that harness's plugin/extension store, not in your project.
- **Your workspace (where writes go)** — agent output (`agents/notes/`, `agents/tasks/`, `artifacts/reports/`, `artifacts/data/`) is written under `$NOTES_WORKSPACE`, resolved as: explicit `$NOTES_WORKSPACE` env var → the git top-level of your working repo → the current directory.

So installing gives you the *capabilities*; pointing at a workspace tells them *where to write*.

---

## Install

> Full per-harness install + update steps: [`docs/INSTALL.md`](docs/INSTALL.md).

There is no single cross-harness command — each agent has its own install mechanism — but it is one step per harness, and all of them read the same shared `skills/` directory from this one repo.

| Harness | Manifest in this repo | Install |
|---|---|---|
| **Claude Code** | `.claude-plugin/{plugin.json, marketplace.json}` | `/plugin marketplace add whacked/agent-resources`<br>then `/plugin install ar@agent-resources` |
| **Codex** | `.codex-plugin/plugin.json` (`skills: ./skills/`) + `AGENTS.md` | Add this repo as a Codex plugin (git source) |
| **Gemini** | `gemini-extension.json` + `GEMINI.md` | `gemini extensions install https://github.com/whacked/agent-resources` |
| **OpenCode** | `.opencode/plugins/agent-resources.js` + `.opencode/INSTALL.md` | See [`.opencode/INSTALL.md`](.opencode/INSTALL.md) |

> The Claude Code commands are exact. The Codex / Gemini / OpenCode invocations follow each harness's standard plugin/extension flow — confirm the precise command against that harness's current docs, since they change independently of this repo.

After installing, point the skills at a workspace (only needed if you are not running inside the git repo you want to write into):

```bash
export NOTES_WORKSPACE=/path/to/your/notes-repo
```

Then verify everything resolves:

```bash
# from anywhere; uses the resolved workspace + dependencies.json
bash skills/doctor/scripts/check.sh
```

### Alternative: vendor it as a submodule

If you prefer the skills to live *inside* a specific notes repo (the older layout), add this repo as a git submodule and run the bootstrap, which wires a `.claude/skills` symlink, creates the workspace directories, and appends a write-constraint block to your `CLAUDE.md`:

```bash
git submodule add https://github.com/whacked/agent-resources
bash agent-resources/scripts/bootstrap.sh --notes-vault <your-vault-dir>   # --dry-run to preview
bash agent-resources/skills/doctor/scripts/check.sh
```

Both layouts work; `doctor` detects which one you are in.

---

## Picking and choosing skills

**Per-skill à la carte install is not supported** — installing the extension exposes all of its skills as one namespaced bundle (e.g. `agent-resources:notes`, `agent-resources:synthesize`). This is deliberate, and it is how the "unwanted skills" concern is resolved:

- **Namespacing** — every skill is prefixed with `agent-resources:`, so nothing collides with your other skills or another extension's.
- **On-demand activation** — skills are invoked by the model only when their trigger matches. An installed-but-unused skill is inert at runtime; only its one-line description participates in routing. You pay essentially nothing for skills you don't trigger.
- **Cohesion** — the skills are interdependent (`synthesize` and `doctor` both rely on `notes`; all share `scripts/validate-frontmatter.sh` and the schemas). Splitting them into separate installs would break those references. The bundle is the dependency-closed unit; see [`dependencies.json`](dependencies.json) for the full map.

If you genuinely want a subset, fork the repo and delete the unwanted `skills/<name>/` directories (and their entries in `dependencies.json`) — the remaining skills keep working as long as you don't remove something in another skill's dependency closure.

### Skills in this bundle

| Skill | Use it when… |
|---|---|
| `notes` | creating, validating, or locating agent-authored notes — `new-note.sh`, `new-task.sh`, `validate-note.sh`, and note-vs-report routing |
| `synthesize` | reading accumulated material (journals, meeting notes, tasks) and distilling it into notes/tasks/reports |
| `doctor` | checking, verifying, or repairing the setup — binaries, workspace dirs, schema, sharding |
| `tfq` | searching/reading/linking notes, managing tasks + dependencies, and validating frontmatter — one index-free binary (supersedes `ov`, `taskmd`, `cue`) |
| `ck` | semantic / concept-level / hybrid search across markdown |
| `audit-skills` | auditing or improving skills themselves |

---

## Dependencies

External CLIs the skills shell out to. `doctor` reads [`dependencies.json`](dependencies.json) and reports which are present; required ones must be on `PATH`, optional ones degrade gracefully.

| Tool | Required | Used by |
|---|---|---|
| `tfq` | yes | notes search/read/links, tasks + dependencies, frontmatter validation (`tfq`, `notes`, `synthesize`, `doctor`) — **supersedes `cue`, `taskmd`, `ov`** |
| `rg` (ripgrep) | yes | search; tfq shells out to it (`tfq`, `notes`, `doctor`) |
| `jq` | yes | JSON parsing (`notes`, `doctor`) |
| `cpd` | no | CPD structured data (`synthesize`) |
| `ck` | no | semantic search (`ck`, `notes`) |

Install to `$HOME/.local/bin` or anywhere on `PATH`.

---

## What your workspace looks like

The extension lives in your harness's store. Inside *your* notes repo (the workspace), only the human content and the agent's write targets appear. Humans write anywhere; the agent writes only under `agents/` and `artifacts/`.

```
my-notes-repo/                          # = $NOTES_WORKSPACE (git top-level)
│
├── journals/                           # you write here — daily notes, todos, rough thoughts
│   ├── 2026-05-17.md
│   └── 2026-05-18.md
├── pages/
│   └── bandgap-reference.md            # you write here
│
├── agents/                             # agent writes here only — do not edit by hand
│   ├── notes/                          # synthesized notes (sharded YYYY/MM/)
│   │   └── 2026/05/
│   │       └── 2026-05-18.001-bandgap-synthesis.md
│   └── tasks/                          # tracked tasks (tfq; index-free, no config file)
│       └── 2026/05/
│           └── 001-review-bandgap-sim.md
│
└── artifacts/                          # formal agent records (relocated here from the extension)
    ├── reports/                        # decisions + ADRs (normative reports)
    │   └── 2026/05/18/
    │       └── 2026-05-18.001-adopt-tfq-tooling.md
    └── data/                           # accumulated structured data (CPD files)
        └── benchmarks/sim-runs.cpd.yaml
```

> Why `artifacts/` lives in the workspace, not the extension: a harness's install dir is versioned and replaced on every update, so anything written there would be wiped. All writes therefore resolve under `$NOTES_WORKSPACE`.

### A journal entry → what the agent produces

```markdown
<!-- journals/2026-05-18.md — you wrote this -->
Good session on the bandgap circuit. PTAT current tracking well, but a corner
case at -40°C is unresolved.
TODO: rerun sim with updated model file
#ActionItem write up the design rationale
```

```markdown
<!-- agents/notes/2026/05/18/2026-05-18.001-bandgap-synthesis.md — agent wrote this -->
---
date: 2026-05-18
author: agent
slug: bandgap-synthesis
source_notes:
  - journals/2026-05-18.md
tags: [bandgap, simulation]
---

# bandgap synthesis

PTAT current tracking well. Open issue: -40°C corner with the 1.2V rail assumption.
Action items extracted and tracked as tasks 001–002.
```

---

## Scripts you can run directly

The scripts work for both the agent (auto-detected via `$CLAUDECODE=1`) and you. Paths below are relative to the extension root; when installed, call them from wherever the skill lives, or use the skills directly via your agent.

```bash
# Create a note — lands under $NOTES_WORKSPACE/agents/notes/YYYY/MM/ (agent) or $PWD (human)
bash skills/notes/scripts/new-note.sh my-idea            # --edit to open, --dest-dir to override

# Create a tracked task
bash skills/notes/scripts/new-task.sh "Title of task" --priority high

# Validate a note or the whole tree (filename, sharding, frontmatter)
bash skills/notes/scripts/validate-note.sh agents/notes/

# Health check the setup
bash skills/doctor/scripts/check.sh
```

Task queries:

```bash
tfq --root agents/tasks --next           # what to work on (deps satisfied)
tfq --root agents/tasks --list
tfq --root agents/tasks --done 003       # mark task 003 completed
```

---

## How the system works

The agent reads everything in your workspace freely. It writes only under `agents/` and `artifacts/`. The loop is eventually-consistent:

```
you write a journal entry or note
  → agent reads via tfq / ck / rg
  → agent synthesizes into agents/notes/ with source_notes: linking back to your files
  → tfq --backlinks surfaces the agent note live when querying your original (no index step)
  → you edit your note with new thoughts
  → agent writes a new synthesis with supersedes: pointing at the prior one
  → repeat
```

Agent notes are never edited in place — each synthesis is a new file; old ones remain as an audit trail of what the agent understood at each point in time.

See `CLAUDE.md` for agent routing and invariants, and `docs/agent-guides/` for the detailed workflow guides (reports, CPD data).
