---
name: ov
description: Use this skill when reading, searching, creating, or appending notes in an Obsidian vault using the ov CLI — including ov search, ov read, ov list, ov create, ov append, ov tags, ov links, ov backlinks, ov graph, or ov index commands.
version: 1.0.0
---

# ov — Obsidian Vault CLI Skill

`ov` is a high-performance CLI for Obsidian vaults. It implements a Zettelkasten philosophy: atomic notes, wiki-links over folders, designed for retrieval not storage.

## Vault Setup

```bash
export OV_VAULT=/path/to/vault    # or pass --vault on every command
ov index build                    # required for `ov search` (Tantivy index)
ov stats                          # sanity check: note count, word count, tags
```

## Index Management

The search index lives **outside the vault** at `~/.local/share/ov/vaults/<hash>/tantivy/`. It is never updated automatically — no watcher, no daemon.

```bash
ov index build --vault /path      # incremental: only re-indexes changed files (fast)
ov index status --vault /path     # check doc count + last build timestamp
ov index clear --vault /path      # wipe index; next build does full rebuild
```

**Rule: run `ov index build` after any session that creates or edits notes, before running `ov search`.** Re-runs are cheap — the tool hashes files and skips unchanged ones.

## Discovering Vaults in This Project

```bash
find . -maxdepth 3 -name ".obsidian" -type d | sed 's|/.obsidian$||'
```

Paths are relative to the repo root. Always run ov from the repo root, or use absolute paths. Always pass `--vault` or set `OV_VAULT` — `ov` will error without it.

## Reading Notes

```bash
ov read "note title" --vault /path   # fuzzy match by title
ov read "partial name" --raw         # body text only, no metadata
ov read "note" --format json         # full metadata + body as JSON
```

## Searching

Requires `ov index build` first.

```bash
ov search "keywords"                          # full-text
ov search "tag:#troubleshooting" --snippet    # by tag with context
ov search "in:Clippings docker"               # scoped to directory
ov search "title:장애" --format json           # title-only search
ov search "type:troubleshooting"              # frontmatter type filter
ov search "date:2024-08"                      # date filter (YYYY, YYYY-MM, or YYYY-MM-DD)
```

Prefixes can be combined: `"tag:#k8s in:Zettelkasten pod"`

## Listing Notes

```bash
ov list                                     # recent notes (human table)
ov list --tag "#meeting" --limit 20         # filter by tag
ov list --date this-week --format json      # recent activity as JSON
ov list --dir Clippings                     # filter by directory
```

## Creating Notes

```bash
# Simple note
ov create "My Note" --tags "idea,k8s" --vault /path

# Structured note with frontmatter + sections
ov create "Redis Connection Pool Exhaustion" \
  --frontmatter '{"type":"troubleshooting","service":"redis","severity":"P1"}' \
  --tags "troubleshooting,redis" \
  --sections "Problem,Root Cause,Fix,Lessons Learned" \
  --vault /path

# Scoped to a directory
ov create "Person Name" --dir People --vault /path

# Using a template
ov create "Person Name" --dir People --template "_person_template" --vault /path
```

## Appending to Notes

```bash
ov append "Note Title" --content "New content" --vault /path
ov append "Note Title" --section "Timeline" --content "14:30 event" --vault /path
ov append "Note Title" --section "Log" --date --content "Entry" --vault /path
```

## Exploring the Link Graph

```bash
ov links "Note Title"                          # outgoing [[wiki-links]]
ov backlinks "Note Title"                      # notes that link here
ov graph --center "Note Title" --depth 2 --format json   # neighborhood
ov graph --format json                         # full graph (check "orphans" field)
```

Orphan notes (0 links) are lost knowledge — check periodically.

## Tags

```bash
ov tags --sort count --format json    # all tags with occurrence counts
```

Before creating a new tag, check existing ones. A tag used only once is noise.

## Output Formats

| Flag | Use |
|------|-----|
| `--format human` | Default table output |
| `--format json` | Wrapped JSON (machine-readable) |
| `--format jsonl` | Streaming JSONL (for large result sets) |
| `--raw` | Body text only (on `read` command) |
| `--fields title,tags,path` | Select specific output fields |

## Directory Conventions

| Directory | Purpose |
|-----------|---------|
| `Zettelkasten/` | Default — troubleshooting, study, ideas |
| `Clippings/` | External sources (articles, talks) |
| `People/` | Person profiles with interaction history |
| `Templates/` | Blueprints — never edit directly |

When unsure, use `Zettelkasten/`. Use tags and `[[links]]` for categorization, not folders.

## Note Type Patterns

### Troubleshooting
```bash
ov create "Service X Outage" \
  --frontmatter '{"type":"troubleshooting","service":"x","severity":"P1"}' \
  --tags "troubleshooting,service-x" \
  --sections "Problem,Root Cause,Fix,Lessons Learned"
```

### Meeting Notes
```bash
ov create "2026-05-17 Team Weekly" \
  --frontmatter '{"type":"meeting","team":"infra"}' \
  --tags "meeting" \
  --sections "Agenda,Discussion,Action Items"
```

### Clipping (external source)
```bash
ov create "Article Title" --dir Clippings \
  --frontmatter '{"type":"clipping","source":"https://..."}' \
  --tags "clippings" \
  --sections "Summary,Key Insights,My Thoughts"
```

### Person Profile
```bash
ov create "Person Name" --dir People --template "_person_template"
ov append "Person Name" --section "Interaction Log" --date --content "Discussed X"
```

## Linking

Add `[[Note Title]]` wiki-links in note bodies to connect related notes. Use `ov backlinks` to find notes that should link to a newly created one. Orphan notes (0 links) degrade retrievability — check with `ov graph --format json`.
