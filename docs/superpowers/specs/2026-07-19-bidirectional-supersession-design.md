# Bidirectional supersession — `superseded_by`, materialized reverse edge, frontmatter mutability carve-out

- **Date:** 2026-07-19
- **Status:** implemented on branch `feat/bidirectional-supersession` (tfq support verified in `20260719.4dd7426`). Decision record: `artifacts/reports/2026/07/2026-07-19.001-bidirectional-supersession.md`.
- **Scope:** agent-resources (this repo + the packaged `ar` install). The `tfq` binary changes are **already shipped** (`20260719.4dd7426`); this spec records the verified verbs and owns the policy that sits above them.
- **Supersedes:** nothing directly. This fills a gap: there is currently no single design record for the supersession policy — it lives as scattered directives (`AGENTS.md:16`, `README.md:197`, `skills/notes/SKILL.md:30`) plus the tfq upstream `superseding-ov-taskmd-cue.md`.

## Problem

`supersedes:` is a single-direction, forward-only edge: the newer file names the older file it replaces. Two consequences make it hard to use:

1. **No cheap reverse traversal.** Reading notes forward in time, you cannot tell whether a note has been obsoleted without scanning every later file for a `supersedes:` pointing back at it. Forward ("what does X supersede?") is a local read; reverse ("has X been superseded?") is a full scan.
2. **Immutability forbids marking the old file.** The repo's append-only bias — "never edit a prior file" — means the obsoleted file carries no local signal of its own obsolescence, even though `reports.cue.template.md` already defines a `status: "superseded"` value that nothing can currently reach.

## Findings (current state)

- **Datatype.** `supersedes?: string` — a single optional scalar in *both* schemas (`schemas/reports.cue.template.md:10`, `skills/notes/schemas/notes.cue.template.md:7`). Never an array. Values are bare slugs.
- **No prior rationale doc.** Single-cardinality was never justified in a design record; it is just the schema declaration. The immutability bias is asserted as directives, with the reasoning living in the tfq repo.
- **A second, dead mechanism.** `skills/synthesize/SKILL.md:218-232` documents a typed `relations: [{type, target}]` array including `type: supersedes`. It is in **no schema** and has **zero real uses** in the vault (`/Users/alexh/cloudsync/main/devsync/agents/`). Effectively dead.
- **tfq edge model.** As of `20260719.4dd7426`, tfq can scope live/index-free traversal to *any* frontmatter field via `--links/--backlinks --relation F`, so `supersedes`/`superseded_by` are first-class traversable edges (verified). (At original investigation time only body `[[wiki-links]]` and `dependencies`/`parent` were edges.)
- **CUE schemas are open.** A note carrying an undeclared `superseded_by` validates OK today, so declaring the field is not required for `--validate` to pass — we declare it to pin the `[...string]` type and document it.
- **Reachable-but-unused enum.** `reports.cue.template.md:3` `status` already includes `"superseded"`; nothing sets it.

## Decisions

1. **Materialize the reverse edge as a derived cache.** The tooling reverse-query need is *already fully met* by the forward edge: `tfq --backlinks <old> --relation supersedes` returns every successor (verified, incl. the fork case). Materialization therefore exists for the one thing the query cannot serve: **a human browsing raw files / Obsidian sees the obsolescence without running a tool**, plus an O(1) local read. `superseded_by` is a *materialized projection of the forward `supersedes` edges*, not an independent source of truth.

2. **Cardinality.** `supersedes?: string` stays scalar (unchanged). `superseded_by?: [...string]` is a **list** — a file can be replaced by multiple successors (fork/split). Values are bare slugs, matching `supersedes`.
   - *Known limitation (deferred):* many-to-one *merges* (one new file superseding several) still cannot be expressed by the scalar `supersedes`. Revisit with a scalar→list bump or the relations map if real merge data appears.

3. **Status.** Reports: set `status: superseded` on the superseded report (enum already exists → now reachable). Notes: add optional `status?: "current" | "superseded"` to the notes schema for parity; the *presence* of `superseded_by` remains the primary machine signal.

4. **Immutability carve-out.** The **body** of a prior note/report remains immutable (append-only audit trail). A bounded frontmatter set — **`superseded_by` and `status`** — MAY be updated post-hoc, solely to maintain the reverse edge. This is the only sanctioned mutation. (`AGENTS.md:16` already scopes its ban to the *body*, so this is a clarification there; `README.md:197` and `skills/notes/SKILL.md:30` need the explicit carve-out.)

5. **Write + consistency — forward edge is authoritative; `superseded_by` is derived.**
   - **Source of truth:** the forward `supersedes` scalar on each (immutable) new file.
   - **Derivation:** a record's complete `superseded_by` set = `tfq --backlinks <ref> --relation supersedes`. Fork-safe and idempotent.
   - **Materialize (layer 1, skill):** after creating a superseding note, recompute and write the old file's back-pointer *from the forward edges* — `tfq --set <old> --field-list superseded_by=<full set>` (+ `--field status=superseded` for reports). **`--field-list` REPLACES the list**, so always write the recomputed *full set*; never blind-append (that would clobber prior successors in the fork case).
   - **Reconcile (layer 2, doctor janitor):** across the collection, recompute each target's `superseded_by` from `--backlinks --relation supersedes` and set it. On any forward/reverse disagreement, **forward wins** (it lives on the immutable file; reverse is a cache).
   - **tfq does not infer the inverse** (verified): writing `supersedes` does not auto-write `superseded_by`. That inference is precisely what layers 1–2 own.

6. **`relations[]` disposition.** Remove the dead `type: supersedes` example from the synthesize skill (supersession is now dedicated fields). Do not formalize a generic container with no data. Record the sanctioned future shape — a **map** `relations: {<type>: [<slug>…]}` (direct lookup by relation type, superior to the list-of-objects form) — here and in the normative report, to be introduced only when real `synthesizes`/`expands-on`/… data exists.

## Field model (result)

**Notes schema** (`skills/notes/schemas/notes.cue.template.md`):
```cue
date:          string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
author:        string
slug:          string & =~"^[a-z0-9-]+$"
source_notes?: [...string]
tags?:         [...string]
supersedes?:   string          // predecessor this file replaces (unchanged)
superseded_by?: [...string]    // successor(s) that replace this file (NEW, derived cache)
status?:       "current" | "superseded"   // NEW, optional
```

**Reports schema** (`schemas/reports.cue.template.md`): add `superseded_by?: [...string]`; `status` unchanged (already has `"superseded"`).

**Semantics:** on the NEW file, `supersedes: <old-slug>` (authoritative). On the OLD file, `superseded_by` = recomputed set from forward backlinks, `status: superseded`.

**Future `relations` shape** (documented, not yet introduced):
```yaml
relations:
  synthesizes: [slugA, slugB]
  expands-on:  [slugC]
  contradicts: [slugD]
```

## tfq capabilities (delivered — `20260719.4dd7426`, verified on a scratch collection)

- **Reverse query:** `tfq --backlinks <ref> --relation supersedes` → all successors (the answer to "has X been superseded, by what?").
- **Write scalar:** `tfq --set <ref> --field supersedes=<slug>`.
- **Write list:** `tfq --set <ref> --field-list superseded_by=<slug>[,<slug>…]` — **replaces** the list; `=` (empty) clears to `[]`. Serializes as a real YAML flow list (`[a, b]`), valid against `[...string]`.
- **Get:** `tfq --frontmatter <ref>`.
- **No inverse inference** — confirmed; each direction is written independently. Bidirectional consistency is owned by agent-resources (skill instruction + doctor janitor).

Not tfq's concern: the immutability policy, `status` semantics, the fork/merge cardinality rules.

## Impacted files

- **Schemas:** `schemas/reports.cue.template.md`, `skills/notes/schemas/notes.cue.template.md`
- **Directives:** `AGENTS.md` (+ `CLAUDE.md` symlink), `README.md`, `docs/agent-guides/reports.md`
- **Skills:** `skills/tfq/SKILL.md` (the verbs above), `skills/notes/SKILL.md` (write-both-ends flow + carve-out), `skills/synthesize/SKILL.md` (remove dead `relations[] type: supersedes`; supersede flow), `skills/doctor/…` (consistency janitor)
- **Tests/fixtures:** `scripts/tests/validate-sample.md`, `scripts/tests/test-prose.sh`
- **Records:** new normative report in `artifacts/reports/2026/07/` (consolidates the policy — the missing design doc); re-package the `ar` install payload and bump `plugin.json` / `marketplace.json` version.

## Non-goals / deferred

- Many-to-one merge supersession via scalar `supersedes` (needs a scalar→list bump or the relations map).
- Introducing the generic `relations` map before real data exists.
- Changing tfq's edge model for `dependencies`/`parent`.

## Deliverables

1. Schema + directive + skill + test edits above.
2. Normative report recording the decision and the consolidated supersession policy.
3. Re-packaged install + version bump.
4. tfq support — verified present in `20260719.4dd7426`; no handoff needed.
