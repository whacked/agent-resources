# Design: `ar` — a portable, auto-invoking, cross-harness skills extension

- **Date:** 2026-07-01
- **Status:** Design — ready for implementation plan
- **Supersedes:** `docs/superpowers/specs/2026-06-19-portable-cross-harness-skills-design.md`. Keeps that spec's `$NOTES_WORKSPACE` read/write split as the load-bearing core. Corrects four assumptions in it: (a) à-la-carte is resolved as a single bundled plugin, not deferred; (b) updates use native per-harness commands + a `doctor` staleness check, not manual version discipline alone; (c) Gemini discovers `skills/` natively and uses `GEMINI.md` `@`-includes only for the routing file (not `@./skills/...` for every skill); (d) the "no hooks needed" decision is reversed — a `SessionStart` hook is required for portable auto-invocation.

## Problem

Three problems were documented in `PROBLEM.md`, plus a fourth surfaced during design:

1. **Path breakage in use.** The notes scripts (`new-note.sh`, `new-task.sh`, `validate-note.sh`) resolve write destinations by climbing `$SCRIPT_DIR/../../../..` to a `REPO_ROOT` and writing to `$REPO_ROOT/agents/...`. Installed as a plugin, that root is the versioned, read-only install cache (`~/.claude/plugins/cache/.../ar/<version>/`), so agent output lands in the plugin cache and is wiped on every update. SKILL.md prose also hardcodes `agent-resources/...` paths that only resolve in the legacy submodule layout.
2. **No working install.** `README.md` documents `.claude-plugin/{plugin.json, marketplace.json}` and per-harness manifests, **none of which exist in the repo**. Every documented install path fails.
3. **No update/sync story.** Nothing tells an installed copy how to pull upstream changes.
4. **No reliable auto-invocation.** Skills fire only when their `description` happens to match. There is no portable mechanism (the project `CLAUDE.md` routing only applies when working *inside this repo*, not when the plugin is installed into a consuming workspace) that reliably routes intents like "write a report" to the right skill.

## Decisions (load-bearing)

1. **Distribution unit = the whole repo as one bundled plugin.** Not a multi-plugin marketplace, not à-la-carte skill folders. The skills are interdependent (`synthesize` and `doctor` depend on `notes`; all share `scripts/validate-frontmatter.sh` and the schemas), and Gemini/OpenCode take the whole repo regardless. Best practice for cohesive interdependent skills is one plugin. Unwanted skills are inert until triggered; truly removing one means forking and deleting it.
2. **Namespace = `ar`.** In Claude Code the skill namespace is the plugin's `name`, so the plugin is named `ar` and skills surface as `ar:notes`, `ar:synthesize`, `ar:doctor`, `ar:tfq`, `ar:ck`, `ar:audit-skills`, `ar:using-ar`. The **marketplace** keeps the descriptive name `agent-resources`. Install: `/plugin marketplace add whacked/agent-resources` → `/plugin install ar@agent-resources`.
3. **Harness scope: Claude Code fully implemented and tested; Codex / Gemini / OpenCode get committed, best-effort manifests + an `INSTALL.md`,** marked unverified-against-live-harness. The skill *content* is portable (open SKILL.md / Agent Skills standard); only the thin wrapper differs.
4. **Reads vs writes.**
   - **Reads** (bundled scripts, schemas, guides) resolve by paths relative to the skill/install dir — valid everywhere because the whole tree ships together.
   - **Writes** resolve under `$NOTES_WORKSPACE`, order: explicit `NOTES_WORKSPACE` env var → `git rev-parse --show-toplevel` → `$PWD`. Output subdir defaults to `agents`, overridable via `AGENTS_SUBDIR`.
5. **Updates: native per-harness commands + `doctor` staleness check.** No silent auto-update by default. One source-of-truth version string mirrored into every manifest, guarded by a version-sync test.
6. **Auto-invocation: a consumer-facing routing skill (`ar:using-ar`) injected every session via a `SessionStart` hook,** and routed through each harness's always-on channel. The injected directive is **firm but scoped to the notes domain** — an intent→target table — not a maximalist "invoke at 1% relevance for everything" directive, to avoid competing with other injectors (e.g. superpowers) and over-firing.
7. **Reports and CPD stay guides, not skills, and stay decoupled.** Reports are a prose-markdown artifact; CPD is an append-only structured-data format for ingestion/ETL/accumulation. They are routed (not auto-discovered as skills) via `ar:using-ar`, with CPD's trigger scoped narrowly to data-accumulation use cases and explicitly *not* to report writing. Report sharding is aligned to notes/tasks: `artifacts/reports/`**`YYYY/MM/`** (DD dropped, matching commit `59cdef0`).

## Architecture

### Read/write anchors

New sourced helper `scripts/lib/workspace.sh`, the single source of truth for write resolution:

- `resolve_workspace()` → prints workspace root, order exactly: `${NOTES_WORKSPACE:-}` → `git rev-parse --show-toplevel 2>/dev/null` → `$PWD`.
- `agents_dir()` → prints `<workspace>/${AGENTS_SUBDIR:-agents}`.

`new-note.sh`, `new-task.sh`, `validate-note.sh` source this helper and write under `agents_dir()` instead of the `../../../..` climb. `artifacts/{reports,data}` also relocate under the workspace. Reads of `validate-frontmatter.sh` and schemas are resolved relative to the script's own location (install-relative), with a clear error if the shared validator is missing.

### Reports & CPD (decoupled)

Two separate artifact types with separate guides; **reporting is never shoehorned into CPD shape** (verified — no coupling exists today, so this is a documentation/path fix, not a refactor). The only relationship is the existing invariant that a significant CPD schema change is itself recorded as a prose report.

- **Reports** — prose markdown. Frontmatter validated against the bundled `schemas/reports.cue.template.md`; narrative sections per `docs/agent-guides/reports.md`. Sharded **`$NOTES_WORKSPACE/artifacts/reports/YYYY/MM/`** (DD dropped to match notes/tasks), filename `YYYY-MM-DD.NNN-slug.md`, `NNN` per-day. Hand-authored + validated via the bundled validator (no creation script today; a `new-report.sh` is a possible future convenience, out of scope here).
- **CPD** — append-only structured data at `$NOTES_WORKSPACE/artifacts/data/<scope>/<dataset>.cpd.yaml`, for API-JSONL ingestion / ETL / accumulation per `docs/agent-guides/cpd-data.md`. Niche; routed with a narrow trigger, never the path for writing reports.
- **Reads vs writes apply here too:** the schema, validator, and guide text are **bundled reads** (install-relative / templated to `${CLAUDE_PLUGIN_ROOT}` by the hook); the report / data file is a **write under `$NOTES_WORKSPACE`**. The two guides therefore need the same prose rewrite as the SKILL.md bodies.
- **Migration:** the 3 existing repo reports (`2026-04-23.001`, `2026-04-24.001`, `2026-06-30.002`) move from `artifacts/reports/YYYY/MM/DD/` up to `artifacts/reports/YYYY/MM/` (filenames already date-unique → plain `mv`, no renames, no `NNN` collisions). These remain in-repo as dev history; a consuming workspace creates its own reports under `$NOTES_WORKSPACE`.

### Distribution & namespace

```
agent-resources/                      # marketplace name: agent-resources; plugin name: ar
├── .claude-plugin/
│   ├── marketplace.json              # one plugin entry: name "ar", source "./", version
│   └── plugin.json                   # name "ar", version, hooks pointer
├── hooks/
│   ├── hooks.json                    # Claude Code SessionStart → run-hook.cmd session-start
│   ├── hooks-codex.json              # Codex SessionStart (uses ${PLUGIN_ROOT})
│   ├── run-hook.cmd                  # cross-platform polyglot wrapper (Unix + Windows)
│   ├── session-start                 # cats skills/using-ar/SKILL.md → additionalContext JSON
│   └── session-start-codex
├── skills/
│   ├── using-ar/SKILL.md             # NEW: routing index (the injected directive)
│   ├── notes/ synthesize/ doctor/ tfq/ ck/ audit-skills/
├── scripts/ (incl. lib/workspace.sh) schemas/ docs/
├── .codex-plugin/plugin.json         # "skills": "./skills/"
├── gemini-extension.json             # name, version; contextFileName GEMINI.md
├── GEMINI.md                         # @./skills/using-ar/SKILL.md
├── AGENTS.md                         # repo contributor directives (current file) + ref to using-ar
├── .agents/skills -> ../skills       # symlink: OpenCode + standalone Codex discovery
├── dependencies.json                 # external-CLI manifest + cohesion map
└── docs/INSTALL.md                   # per-harness install + update instructions
```

### Auto-invocation layer

Modeled verbatim on the verified superpowers wiring.

- **`skills/using-ar/SKILL.md`** — the routing index. Contains a scoped intent→target table (targets are skills **or** guides):
  - create / find / validate a note or task → `ar:notes`
  - synthesize accumulated material, weekly digest, fragment merge → `ar:synthesize`
  - **record a decision / architectural or schema change / write a formal report or ADR** → read the bundled `docs/agent-guides/reports.md`; write to `$NOTES_WORKSPACE/artifacts/reports/YYYY/MM/`; validate with the bundled schema (prose markdown — not a skill, not CPD-formatted)
  - **accumulate append-only structured records (API JSONL ingestion, ETL, data generation)** → read the bundled `docs/agent-guides/cpd-data.md`; write to `$NOTES_WORKSPACE/artifacts/data/<scope>/<dataset>.cpd.yaml` (niche; *not* the path for reports)
  - keyword / structured / task-graph search over markdown → `ar:tfq`
  - semantic / concept / hybrid search → `ar:ck`
  - check / verify / repair the setup, dependency preflight → `ar:doctor`
  - audit / review skills → `ar:audit-skills`
- **`hooks/hooks.json`** — `SessionStart` (matcher `startup|clear|compact`) runs `"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd" session-start`.
- **`hooks/session-start`** — `cat`s `skills/using-ar/SKILL.md`, **substitutes `${CLAUDE_PLUGIN_ROOT}` into the bundled-read paths it references** (the two guides, `schemas/reports.cue.template.md`, `scripts/validate-frontmatter.sh`) so the agent gets resolvable install-dir paths, JSON-escapes the result, and emits `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<scoped routing directive + resolved using-ar body>"}}`. Workspace writes still resolve via `$NOTES_WORKSPACE` at run time.
- **Codex** — `hooks/hooks-codex.json` + `hooks/session-start-codex` (uses `${PLUGIN_ROOT}`); `AGENTS.md` references the routing.
- **Gemini** — `GEMINI.md` contains `@./skills/using-ar/SKILL.md` (always-loaded context).
- **Distinction preserved:** the repo's `AGENTS.md`/`CLAUDE.md` are *contributor* directives for working on this repo; `using-ar` is the *consumer* routing index for a workspace that installed the plugin. `${CLAUDE_PLUGIN_ROOT}` / `${PLUGIN_ROOT}` appear only in hook manifests, never in skill bodies.

### Update / staleness

- `docs/INSTALL.md` documents native commands: Claude Code `/plugin marketplace update agent-resources`; Codex `codex plugin marketplace upgrade`; Gemini `gemini extensions update ar`. Auto-update stays off by default (third-party); the doc shows how to opt in.
- **`doctor` staleness check:** compares the installed version / local git HEAD against upstream via `git ls-remote` (or `git rev-list --count` when the install dir is a git clone) and prints the exact per-harness update command when behind. Never pulls silently.
- **Versioning:** one source-of-truth version string (start `1.0.0`) mirrored into `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json`, `gemini-extension.json`. A version-sync guard test fails if any drift. Git SHA is the fallback so an unversioned install is never silently stale.

### Doctor / dependencies

- **`dependencies.json`** — `{ cli: [{name, check, required, usedBy}], cohesion: {...} }`. Current real deps: required `tfq`, `rg`, `jq`; optional `ck`, `cpd`. (The retired `ov`, `taskmd`, `cue` binaries are no longer dependencies — `tfq` supersedes them and bundles cuelang.)
- **`doctor/scripts/check.sh`** becomes manifest-driven (iterate `.cli[]`, required→error, optional→warn), resolves the workspace via `workspace.sh`, and is **layout-aware**: it works in plugin-cache layout and in legacy submodule layout, degrading submodule-only checks (project `CLAUDE.md`, `.claude/skills` symlink) from FAIL to INFO when no submodule is present. It also runs the staleness check above.
- **Prose scrub:** remove lingering `ov` / `taskmd` / `cue` references and hardcoded `agent-resources/...` paths from `skills/notes/SKILL.md` and `skills/synthesize/SKILL.md`, replacing them with skill-relative reads and `$NOTES_WORKSPACE` writes.

## Files

**Create:** `scripts/lib/workspace.sh`; `dependencies.json`; `.claude-plugin/{plugin.json,marketplace.json}`; `hooks/{hooks.json,hooks-codex.json,run-hook.cmd,session-start,session-start-codex}`; `skills/using-ar/SKILL.md`; `.codex-plugin/plugin.json`; `gemini-extension.json`; `GEMINI.md`; `.agents/skills` symlink → `../skills`; `docs/INSTALL.md`; test suites `scripts/tests/{test-workspace.sh,test-portability.sh,test-manifests.sh,test-prose.sh}`.

**Modify:** `skills/notes/scripts/{new-note.sh,new-task.sh,validate-note.sh}` (use the resolver); `skills/doctor/scripts/check.sh` (manifest-driven + layout-aware + staleness); `skills/notes/SKILL.md`, `skills/synthesize/SKILL.md` (prose scrub; in synthesize, change the report path `artifacts/reports/YYYY/MM/DD/` → `…/YYYY/MM/`); `docs/agent-guides/reports.md` (drop the `DD/` shard → `artifacts/reports/YYYY/MM/`; read/write split — bundled schema+validator vs `$NOTES_WORKSPACE` write); `docs/agent-guides/cpd-data.md` (read/write split for the `artifacts/data/` paths); `scripts/bootstrap.sh` (set/persist `NOTES_WORKSPACE`, create `artifacts/{reports,data}`, keep symlink wiring as the submodule path); `README.md` (point to `docs/INSTALL.md`, correct the install table); `scripts/tests/run-tests.sh` (aggregate new suites).

**Migrate:** move the 3 existing reports from `artifacts/reports/YYYY/MM/DD/` to `artifacts/reports/YYYY/MM/` (plain `mv`, no renames).

## Testing

- `test-workspace.sh` — resolver honors env → git → cwd; `AGENTS_SUBDIR` override.
- `test-portability.sh` — writes land under the resolved workspace (not the install dir) in both plugin-cache and submodule layouts; bundled reads resolve relative to the script.
- `test-manifests.sh` — all manifest versions match; required JSON fields present and parseable.
- `test-prose.sh` — across skill bodies **and `docs/agent-guides/*.md`**, fails on any `agent-resources/` hardcoded path, retired binary name (`ov`/`taskmd`/`cue`), or a `artifacts/reports/YYYY/MM/DD/` day-sharded report path.

## Out of scope (YAGNI)

- Publishing to the official/public plugin marketplace.
- A custom self-sync daemon (native update commands + `doctor` staleness cover it).
- Splitting skills into multiple plugins for per-plugin à-la-carte install.
- Additional harnesses beyond the four (Cursor, Kimi, pi) — addable later with the same thin-manifest pattern.

## Follow-ups

- File an `intent: normative` report under `artifacts/reports/YYYY/MM/` after implementation, per the repo invariant that architectural/directive changes are recorded.
- Verify the non-Claude install invocations and manifest field names against each harness's live docs during implementation (flagged as best-effort, not deferred work).
