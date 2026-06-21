# Design: agent-resources as a portable, versioned, cross-harness skills extension

- **Date:** 2026-06-19
- **Status:** Design — awaiting implementation plan
- **Scope:** Restructure `agent-resources` so its skills install with one command from a personal GitHub repo and run unmodified across Claude Code, Codex, Gemini, and OpenCode — resolving shared-resource path breakage, lack of versioning, and hardcoded write destinations.

## Problem

Skills currently break when distributed because the de-facto distribution unit is a **single skill folder** copied a la carte. The dependency audit shows most skills reach outside their own folder:

- **notes** → repo `scripts/validate-frontmatter.sh` (via `$SCRIPT_DIR/../../../scripts/` climb in `validate-note.sh`); `taskmd` CLI (via `new-task.sh`); its own `schemas/notes.cue.template.md`; plus `agent-resources/...` paths hardcoded in prose.
- **synthesize** → **notes** skill scripts (`new-note.sh`, `new-task.sh`, `validate-note.sh`); repo `scripts/validate-frontmatter.sh`; `cpd` CLI + `docs/agent-guides/cpd-data.md`; `docs/agent-guides/reports.md` + `schemas/reports.cue.template.md`. Most coupled skill in the repo.
- **doctor** → **notes** scripts + notes schema (via `../../notes/...`); repo root `CLAUDE.md`; hardcodes `/workspace/skills/doctor/...`.
- **taskmd / ck / ov / audit-skills** → roughly leaf; `ck` references `bootstrap.sh` + `.ckignore`.

Two schema homes exist: repo-level `schemas/` (reports) and `skills/notes/schemas/` (notes). The reports schema is not inside any skill, yet synthesize's reports pathway needs it.

Three distinct problems result:
1. **Path breakage** — anything climbing out of a skill folder, or naming `agent-resources/...`, dies when only that folder is copied.
2. **No versioning** — a copied skill folder carries no version, so downstream copies silently go stale.
3. **Hardcoded write destinations** — skills write outputs to repo-layout paths (`agent-resources/artifacts/reports/`, `artifacts/data/`, `agents/notes/`) that assume a specific consuming-repo layout.

## Key decisions

These were settled during brainstorming and are load-bearing:

1. **Personal repo, no public marketplace.** Distribution is a GitHub repo synced for personal use; no third-party marketplace publishing.
2. **Cross-harness is a hard requirement:** Claude Code (primary), Codex, Gemini, OpenCode.
3. **Distribution unit = the whole repo as ONE extension** — *not* a multi-plugin marketplace and *not* individual skill folders. Rationale: Codex (`"skills": "./skills/"`), Gemini (`@./skills/...` context includes), and OpenCode all expect a single root `skills/` and install the repo as one extension. Multi-plugin a-la-carte install is a Claude-Code-only feature and would not satisfy the other three. Therefore the only structure giving "one simple install per agent, all skills work" is a single extension. This **reverses** an earlier (now obsolete) multi-plugin-marketplace direction that was premised on third-party marketplace distribution.
4. **Cohesion grouping is retained as internal organization + the dependency manifest, not as separate installables.**
5. **Write-destination portability is in scope** (not just read-side resource resolution).

## Architecture

Two cleanly separated anchors:

- **Repo root (read-only capability)** — the installed extension tree: `skills/`, `scripts/`, `schemas/`, `docs/agent-guides/`. On every harness the install dir is a versioned, effectively read-only location (Claude Code caches under `~/.claude/plugins/cache/<mp>/<plugin>/<version>/`; Codex/Gemini/OpenCode use their own extension dirs). Skills read bundled resources by **relative path**, which is valid on every harness because the whole tree always ships together.
- **`$NOTES_WORKSPACE` (all writes)** — resolution order: explicit `NOTES_WORKSPACE` env var → `git rev-parse --show-toplevel` → CWD. Under it: `agents/{notes,tasks,archive}/` and the relocated `artifacts/{reports,data}/`. `bootstrap.sh` creates these and exports the var; `doctor` verifies them.

**Why writes cannot stay in the extension:** the install dir is versioned and replaced on update, so `artifacts/reports/` and `artifacts/data/` would be wiped on every version bump. They must live in the consuming workspace.

**Why no `${CLAUDE_PLUGIN_ROOT}` in skill bodies:** the plugin-root env var differs per harness (`CLAUDE_PLUGIN_ROOT`, Codex `PLUGIN_ROOT`, Cursor relative, etc.) and is only needed by hook *manifests* that require an absolute command path. These skills are task-triggered (normal skill auto-discovery), not session-start-injected, so no hooks are needed and relative paths suffice everywhere. This is the most cross-harness-portable choice and matches how superpowers' own skills reference bundled scripts.

## Repository layout (target)

The repo is already extension-shaped (root `skills/`, `scripts/`, `schemas/`). The reorg mostly adds thin per-harness manifests and fixes write paths.

```
agent-resources/
├── .claude-plugin/
│   ├── plugin.json                 # name, version, description (Claude Code)
│   └── marketplace.json            # one plugin entry, "source": "./"
├── .codex-plugin/
│   └── plugin.json                 # "skills": "./skills/", optional hooks
├── gemini-extension.json           # contextFileName: GEMINI.md
├── GEMINI.md                       # @-includes the entry/context, minimal
├── .opencode/
│   ├── plugins/agent-resources.js
│   └── INSTALL.md
├── AGENTS.md                       # symlink → CLAUDE.md (Codex/OpenCode read this)
├── CLAUDE.md                       # existing routing + invariants
├── dependencies.json               # external-CLI deps + cohesion map (doctor reads)
├── scripts/                        # shared: validate-frontmatter.sh + tests/, bootstrap.sh
├── schemas/                        # shared: reports.cue.template.md
├── skills/                         # single shared skills root — all harnesses read here
│   ├── notes/        {SKILL.md, scripts/, schemas/notes.cue.template.md}
│   ├── synthesize/   SKILL.md
│   ├── doctor/       {SKILL.md, scripts/check.sh}
│   ├── ck/  ov/  taskmd/  audit-skills/  ...
└── docs/                           # repo-dev docs (incl. this spec) + agent-guides/
```

Cohesion closure (documented in `dependencies.json`, not separate installs): `{notes, synthesize, doctor}` + shared `validate-frontmatter.sh` + `schemas/reports.cue.template.md` + `docs/agent-guides/{reports,cpd-data}.md`. Leaf skills `ck`, `ov`, `taskmd`, `audit-skills` have no intra-repo skill dependencies.

## Install commands (per harness, from the GitHub repo)

| Agent | Manifest | Install |
|---|---|---|
| Claude Code | `.claude-plugin/{plugin.json, marketplace.json}` (`"source":"./"`) | `/plugin marketplace add <owner>/agent-resources` then `/plugin install agent-resources@<marketplace-name>` |
| Codex | `.codex-plugin/plugin.json` (`"skills":"./skills/"`) + `AGENTS.md` | add repo as Codex plugin (git source) |
| Gemini | `gemini-extension.json` + `GEMINI.md` | `gemini extensions install <git-url>` |
| OpenCode | `.opencode/plugins/agent-resources.js` + `.opencode/INSTALL.md` | per `INSTALL.md` |

The exact non-Claude install invocations must be confirmed against each harness's current docs during implementation (treated as a verification step, not assumed).

## Components & changes

### Read-side (path resolution)
- `skills/notes/scripts/validate-note.sh` — keep `VALIDATOR="$(... $SCRIPT_DIR/../../.. )/scripts/validate-frontmatter.sh"`; this already resolves correctly once the whole repo ships together. Add an existence guard with a clear error if the shared script is absent.
- `skills/doctor/scripts/check.sh` — replace the `/workspace/skills/doctor/...` hardcode and any absolute assumptions with `$SCRIPT_DIR`-relative resolution.
- SKILL.md prose — replace `agent-resources/scripts/validate-frontmatter.sh` and cross-skill `agent-resources/skills/notes/scripts/...` references with skill-relative phrasing ("from this skill's directory, run `../../scripts/...`" / "`scripts/...`"), consistent with how the helper scripts resolve paths.

### Write-side (`$NOTES_WORKSPACE`)
- `new-note.sh`, `new-task.sh` — replace `REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"` with `$NOTES_WORKSPACE` resolution (env → git toplevel → CWD).
- Prose — `agent-resources/artifacts/reports/...`, `artifacts/data/...`, and `agents/...` destinations expressed relative to `$NOTES_WORKSPACE`.
- `scripts/bootstrap.sh` — create `agents/{notes,tasks,archive}` and `artifacts/{reports,data}` under the workspace; export/persist `NOTES_WORKSPACE`; install `.ckignore` to the workspace as today.
- Relocate the reports/data *governance*: the capability (schema, `reports.md`, `cpd-data.md`) ships in the extension; outputs land in `$NOTES_WORKSPACE/artifacts/`. The repo's own historical reports under `artifacts/reports/` stay in place as repo-dev history (see Follow-ups).

### Dependency manifest
- `dependencies.json` at repo root: machine-readable list of external CLIs with check commands, e.g.
  ```json
  {
    "cli": [
      {"name": "cue", "check": "cue version", "required": true, "usedBy": ["notes", "synthesize"]},
      {"name": "taskmd", "check": "taskmd --version", "required": true, "usedBy": ["notes"]},
      {"name": "cpd", "check": "cpd --help", "required": false, "usedBy": ["synthesize"]},
      {"name": "ov", "check": "ov --version", "required": false, "usedBy": ["ov", "notes"]},
      {"name": "rg", "check": "rg --version", "required": true, "usedBy": ["doctor"]}
    ],
    "cohesion": {"knowledge-notes": ["notes", "synthesize", "doctor"]}
  }
  ```
  (Exact CLI names/check commands to be confirmed during implementation.)
- `skills/doctor/scripts/check.sh` — read `dependencies.json` and preflight-report missing/optional tools, in addition to its existing checks.

### Versioning
- A single source-of-truth version string, mirrored into `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, and `gemini-extension.json`. A small bump helper (or documented manual step) keeps them in sync. Git SHA is the fallback so downstream is never un-versioned.

## Error handling

- Missing shared script / schema → skills fail with an explicit message naming the expected relative path, not a silent climb past the repo root.
- Missing `$NOTES_WORKSPACE` writable dirs → `bootstrap.sh` creates them; if a skill runs pre-bootstrap, it errors with the bootstrap command to run.
- Missing external CLIs → `doctor` reports them as actionable warnings/errors per `required`; `validate-note.sh` already degrades gracefully when `cue` is absent (retain).

## Testing

1. `scripts/tests/run-tests.sh` must continue to pass against `validate-frontmatter.sh` at its current location.
2. **Relative-path portability test:** from a temp checkout at a *different* CWD, run `validate-note.sh` and `doctor/check.sh` and assert no path escapes the repo root or the workspace anchor.
3. **Write-anchor test:** with `NOTES_WORKSPACE` set to a temp dir, assert `new-note.sh`/`new-task.sh` write under it and nowhere else.
4. **Install smoke test (Claude Code):** add the local repo as a marketplace, install the plugin, confirm skills resolve and a bundled script runs.
5. **Dependency-manifest test:** `doctor` correctly reports a deliberately-missing CLI.

## Follow-ups (out of scope for this spec)

- File an `intent: normative` report under `artifacts/reports/` once this design is approved/implemented, per the repo's own invariant that architectural/directive changes are recorded. (This reorg is itself such a change.)
- Decide migration of pre-existing historical reports vs. leaving them as repo-dev history.
- Additional harnesses (Cursor, Kimi, pi) can be added later with the same thin-manifest pattern.

## Known risks

- `plugin.json` schemas may reject unknown fields — hence dependencies live in a sidecar `dependencies.json`, never inside a harness manifest.
- Non-Claude install invocations and manifest field names must be verified against each harness's current docs during implementation, not assumed.
- Keeping four version strings in sync requires the bump helper/discipline; drift would mislead downstream staleness signals.
