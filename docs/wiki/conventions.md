---
title: Wiki Conventions
type: meta
updated: 2026-06-06
sources:
  - https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f
---

# Wiki Conventions

This is the single source of truth for how `docs/wiki/` is maintained. The `wiki-update` skill (`.claude/skills/wiki-update/`) is a thin pointer to this file. Read this before editing the wiki.

The model is karpathy's "LLM wiki": an LLM-maintained, git-versioned knowledge layer. Because it lives in git, every agent, on macOS or Windows, reconstructs the same context by pulling the repo. That cross-machine sync is the whole reason this wiki exists.

## Three layers

1. **Raw sources** — the code, which is the source of truth for how the app works, and the decision records in `docs/adr/`, which say why something was chosen. The wiki does not restate code structure; it cites the ADR (or the code) a behavior comes from.
2. **The wiki** — `docs/wiki/`. Markdown the agent fully owns: `overview.md`, per-behavior pages under `behaviors/`, per-platform pages under `platforms/`, plus the generated `index.md` and the append-only `log.md`.
3. **The schema** — this file, plus `AGENTS.md` / `CLAUDE.md`, which tell agents the conventions and when to run the workflow.

## Design documents

Each kind of document has one home, and none restates the code:

- **`docs/adr/NNNN-slug.md`** — decision records: what was chosen, why, and the alternatives worth remembering. Numbered in order; take the highest number and add one. Optional `status:` frontmatter (`accepted`, `superseded by NNNN`). Format: the `domain-modeling` skill's ADR format (`docs/agents/domain.md`). ADRs written before 2026-11-21 are former design specs moved as they were; distill one into a short ADR when you next touch it.
- **`docs/plans/`** — execution checklists for work in progress. Delete a plan when its work lands; git history keeps it. Record any lasting reason in an ADR or the wiki first.
- **`docs/wiki/`** — behavior contracts and deliberate macOS/Windows differences, citing ADRs (or code) as `sources`.

## Page format

Every page (except `index.md` / `log.md`) starts with frontmatter:

```yaml
---
title: Human-readable title
type: overview | concept | behavior | platform | matrix | reference | meta
updated: YYYY-MM-DD
sources:
  - docs/adr/NNNN-....md   # repo-relative path (an ADR or code), or a URL
---
```

- `sources` is mandatory for `overview` / `concept` / `behavior` / `platform` pages and must point at the raw sources the page is derived from. A source must not be under `docs/plans/`: plans are deleted once they land, so lint rejects them. Cite sources inline in the prose too (e.g. "(`0002-overall-design.md` §5)"). `reference` and `meta` pages may omit `sources`.
- Links between pages use **basename wikilinks**: `[[oauth-flow]]`, `[[macos]]` — never a path. Each basename must resolve to exactly one file under `docs/wiki/`. Keep basenames unique.
- Write in **English** (the repo is published publicly; AGENTS.md and the wiki are the agent-facing English layer, even though many ADRs are Japanese).

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
    note: "Windows feed polls every 30s; no Jetstream subscription yet ([[windows]])."
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

## Platform differences

macOS (Swift core, `core/`) and Windows (C# core, `apps/windows/Core`) share no code. The wiki is where the two are held to one behavior, so it records each difference between them and says whether it is **deliberate**. Code structure is not recorded here; read it from the code.

- A **deliberate** difference is a choice: an OS convention, a platform API, or a decided trade-off. Mark the platform `differs` (or `limited` / `none`) and make the `note` say why, citing what decided it: a spec, an issue, or the code that implements the convention.
- A difference with no such reason is a **bug** in one core. Open an issue for it, and write the note as `bug: <issue link>` so the matrix shows it as a defect to fix, not a design.
- When a fix lands in one core, check the other core: if it now behaves the same, set the platform back to `full` and drop the note.

## Workflow

### Ingest (agent task — not automatable)

When a raw source is added or changed, or behavior changes land:
1. Read the changed ADR(s) in `docs/adr/` and the code whose behavior changed.
2. Update or create the affected wiki page(s): summarize, keep prose accurate, add inline citations, set `sources` and `updated`. On a `behavior` page, also update its `features:` platform status (and `note`) whenever the change affects what works on which platform — that is what keeps the support matrix honest.
3. Update cross-references (`[[links]]`) on related pages.
4. Check platform differences (see "Platform differences"): every `differs` / `limited` / `none` you touched, and every macOS/Windows contrast in the prose you changed, is either deliberate with a cited reason or a `bug:` note with an issue link.
5. Add an entry to the **top** of `log.md`: a `## YYYY-MM-DD <op>` heading followed by a short bullet body (`sources` / `updated` / `created` / `note`).
6. Run lint + rebuild (below) and fix anything it reports.

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

`wiki:lint` hard-fails on structural errors (duplicate basenames, missing frontmatter fields, a sourced type with no `sources`, a missing source path, a source under `docs/plans/`, an unresolved `[[link]]`). It additionally prints **non-fatal warnings** for two coverage gaps: an ADR under `docs/adr/` that no page cites (un-ingested), and a page with no inbound `[[link]]` (an orphan; `overview` is exempt as the entry point). Warnings do not fail the build — they flag work to do, so adding an ADR in one commit and ingesting it in the next is allowed.

The pre-commit hook runs lint and regenerates `support-matrix.md` and `index.md` automatically when any `docs/wiki/**` file is staged (see `scripts/hooks/pre-commit`; install with `mise run wiki:install-hooks`). Ingest (writing prose, choosing platform status) is never done by the hook — only an agent does that.

## Division of labor

The tedious part of a knowledge base is bookkeeping (resolving links, regenerating the index, checking citations), and that is exactly what the deterministic tool and the hook handle. The agent does the reading, thinking, and writing. Keep that boundary: never put prose generation in the hook, and never hand-edit `index.md`.
