---
title: Wiki Conventions
type: meta
updated: 2026-06-06
sources:
  - https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f
---

# Wiki Conventions

This is the single source of truth for how `docs/wiki/` is maintained. The Claude Code skill (`.claude/skills/wiki-update/`) and the Cursor command (`.cursor/commands/wiki-update.md`) are thin pointers to this file, so both agents follow the exact same procedure. Read this before editing the wiki.

The model is karpathy's "LLM wiki": an LLM-maintained, git-versioned knowledge layer. Because it lives in git, every agent — Claude / Cursor on macOS, the build agent on Windows — reconstructs the same context by pulling the repo. That cross-machine sync is the whole reason this wiki exists.

## Three layers

1. **Raw sources** — `docs/superpowers/specs/` and `docs/superpowers/plans/`. The ground truth. The wiki never modifies them; it only reads and cites them.
2. **The wiki** — `docs/wiki/`. Markdown the agent fully owns: `overview.md`, per-behavior pages under `behaviors/`, per-platform pages under `platforms/`, plus the generated `index.md` and the append-only `log.md`.
3. **The schema** — this file, plus `AGENTS.md` / `CLAUDE.md`, which tell agents the conventions and when to run the workflow.

## Page format

Every page (except `index.md` / `log.md`) starts with frontmatter:

```yaml
---
title: Human-readable title
type: overview | concept | behavior | platform | matrix | reference | meta
updated: YYYY-MM-DD
sources:
  - docs/superpowers/specs/....md   # repo-relative path, or a URL
---
```

- `sources` is mandatory for `overview` / `concept` / `behavior` / `platform` pages and must point at the raw sources the page is derived from. Cite sources inline in the prose too (e.g. "(`...design.md` §5)"). `reference` and `meta` pages may omit `sources`.
- Links between pages use **basename wikilinks**: `[[oauth-flow]]`, `[[macos]]` — never a path. Each basename must resolve to exactly one file under `docs/wiki/`. Keep basenames unique.
- Write in **English** (the repo is published publicly; AGENTS.md and the wiki are the agent-facing English layer, even though the specs are Japanese).

## Platform support matrix

`support-matrix.md` (`type: matrix`) is a generated star-chart of which feature works on which platform. Like `index.md` it is **never hand-edited** — `mise run wiki:matrix` regenerates it from a `features:` block in each behavior page's frontmatter. This keeps the matrix from drifting: you change a behavior page (the thing you were editing anyway) and the matrix follows, and lint refuses a behavior page that does not declare its platform status.

Every `behavior` page must carry a `features:` list. Each entry is one matrix row:

```yaml
features:
  - name: Jetstream live updates (home / list)   # the row label
    macos: full
    windows: none
    ios: planned
    android: planned
    note: "Windows feed polls every 30s; no Jetstream subscription over the bridge yet ([[windows]])."
```

- **Platforms** (all four required per feature): `macos`, `windows`, `ios`, `android`.
- **Status values** → matrix marks:
  - `full` → ○ — supported, same behavior as the reference platform
  - `differs` → △ — supported but behaves differently per OS (mechanism/UX differs)
  - `limited` → △ — partial implementation or limited UX
  - `none` → × — not supported / not implemented
  - `planned` → − — planned or out of scope for now
  - `unknown` → ? — not yet verified against that platform's app
- **`note` is mandatory** whenever any platform is `differs` / `limited` / `none` / `unknown`. This is where the *why* lives — keep it to one line and link the relevant page (e.g. `[[windows]]`); the full reasoning stays in the page prose. `full` / `planned`-only features need no note.
- The matrix groups rows under one section per behavior page (the heading links back to the source page), and collects every note into a closing **Notes** section.

## Workflow

### Ingest (agent task — not automatable)

When a raw source is added or changed, or behavior changes land:
1. Read the changed source(s) in `docs/superpowers/`.
2. Update or create the affected wiki page(s): summarize, keep prose accurate, add inline citations, set `sources` and `updated`. On a `behavior` page, also update its `features:` platform status (and `note`) whenever the change affects what works on which platform — that is what keeps the support matrix honest.
3. Update cross-references (`[[links]]`) on related pages.
4. Add an entry to the **top** of `log.md`: a `## YYYY-MM-DD <op>` heading followed by a short bullet body (`sources` / `updated` / `created` / `note`).
5. Run lint + rebuild (below) and fix anything it reports.

A single source change typically touches 1–3 wiki pages plus `support-matrix.md` and `index.md`, and `log.md`.

### Query (agent task)

When answering a question about the app: read `index.md` first, open only the relevant pages (do not load the whole wiki), answer with citations. If the answer is durable and reusable, consider persisting it as a new page.

### Lint + rebuild-index (deterministic — tooling)

These are mechanical and run as a Swift CLI, identically on macOS and Windows:

```bash
mise run wiki:lint     # validate frontmatter, [[links]], source paths, and feature blocks
mise run wiki:matrix   # regenerate support-matrix.md from behavior `features:` blocks
mise run wiki:index    # regenerate index.md from page frontmatter
mise run wiki:check    # lint + verify support-matrix.md and index.md are up to date (CI / pre-commit)
```

The pre-commit hook runs lint and regenerates `support-matrix.md` and `index.md` automatically when any `docs/wiki/**` file is staged (see `scripts/hooks/pre-commit`; install with `mise run wiki:install-hooks`). Ingest (writing prose, choosing platform status) is never done by the hook — only an agent does that.

## Division of labor

The tedious part of a knowledge base is bookkeeping (resolving links, regenerating the index, checking citations), and that is exactly what the deterministic tool and the hook handle. The agent does the reading, thinking, and writing. Keep that boundary: never put prose generation in the hook, and never hand-edit `index.md`.
