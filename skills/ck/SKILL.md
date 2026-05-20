---
name: ck
description: Use this skill when doing semantic search, concept-level search, or hybrid search across markdown files — including "band gap" finding "bandgap", finding conceptually related notes, or searching when exact keywords are unknown. Also use for ck index management (--index, --status, --clean).
version: 1.0.0
---

# ck — Semantic Search Skill

`ck` is a grep replacement with semantic (embedding-based) search. Use it when keyword search isn't enough — concept matching, alternate phrasings, or "find notes about X" queries.

## Search Modes

```bash
ck --hybrid "term" .              # DEFAULT: regex + semantic combined (use this)
ck "pattern" .                    # regex grep (no index needed)
ck --lex "phrase" .               # BM25 ranked full-text
ck --sem "concept" .              # semantic/embedding search
```

**Always use `--hybrid` by default.** It combines regex and semantic ranking via RRF and is the most reliable mode across mixed corpora.

**Always run from the directory where the index was built.** The index lives in `.ck/` at the CWD.

## Semantic Search

```bash
cd /workspace && ck --sem "energy levels in semiconductors" .
ck --sem "meeting action items" . --limit 5
ck --sem "auth" . --threshold 0.7     # stricter match
ck --sem "auth" . --scores            # show similarity scores
```

**Requires real corpus.** On <20 files semantic scores approach 0 and return nothing. On 50+ substantial files it becomes useful. Check with `ck --status .` first.

## Hybrid Search (default — use for all queries)

```bash
ck --hybrid "bandgap" .
ck --hybrid "TODO simulation" . --limit 10
ck --hybrid "auth" . --threshold 0.02    # filter by RRF score
```

Hybrid combines regex hits and semantic hits via RRF ranking. More reliable than `--sem` alone on mixed corpora. **Never pass `--exclude` flags** — exclusions are handled by `.ckignore` at the vault root (installed by bootstrap).

## Grep-compatible Usage

```bash
ck "TODO" . -n                       # line numbers
ck -i "#actionitem" . -r             # case-insensitive recursive
ck "author: agent" . -l              # filenames only
ck -C 2 "band gap" .                 # 2 lines context
ck --jsonl "bandgap" .               # streaming JSON for agent pipelines
```

## Index Management

```bash
cd /workspace && ck --index .        # build/update index (run from repo root)
ck --status .                        # check: files indexed, model, chunk count
ck --status-verbose .                # detailed stats
ck --clean-orphans .                 # remove deleted files from index
ck --clean .                         # wipe index entirely
```

Index is incremental — only new/changed files are re-embedded on subsequent runs.

## .ckignore

A `.ckignore` is maintained at `skills/ck/.ckignore` in agent-resources and installed to the vault root by `bootstrap.sh`. It excludes:

**Never pass `--exclude` flags on the command line.** Add new patterns to `.ckignore` instead — that way exclusions are permanent and no flags are needed.

```bash
# correct — .ckignore handles it
ck --hybrid "concept" .

# wrong — flags are band-aids, not fixes
ck --hybrid "concept" . --exclude "*.json" --exclude "*.pdf"
```

## Output for Agent Pipelines

```bash
ck --jsonl --sem "concept" .          # streaming JSONL
ck --jsonl "pattern" . --no-snippet  # filenames + line numbers only
ck --json --hybrid "term" .           # single JSON array
```

## When to Use ck vs Other Tools

| Need | Use |
|---|---|
| Exact keyword | `ov search` or `rg` |
| Conceptually similar | `ck --sem` |
| Alternate phrasing ("band gap" → bandgap.md) | `ck --hybrid` |
| TODO/link patterns | `rg` with regex |
| Backlink graph | `ov backlinks` |

## Known Limitation

Semantic scores are near 0 on tiny corpora. If `ck --sem` returns nothing, check `ck --status .` — if chunks < 100, semantic search won't work well. Use `ck --hybrid` or `rg` instead.
