---
name: wiki-update
description: Maintain the LLM-wiki under docs/wiki (ingest specs/plans into wiki pages, then lint and rebuild the index). Use when docs/superpowers specs or plans change, when app behavior changes, or when asked to update or query the project wiki.
---

# wiki-update

Maintain the git-versioned LLM-wiki at `docs/wiki/`. This is the cross-machine knowledge layer: it lives in git so Claude / Cursor on macOS and the build agent on Windows all see the same context.

**The canonical procedure and schema live in `docs/wiki/conventions.md`. Read it first, then follow it.** This skill is a thin entry point so the same workflow is invoked identically from Claude and Cursor (Cursor uses `.cursor/commands/wiki-update.md`, which points to the same file).

## Ingest (write prose — your job)

1. Read `docs/wiki/conventions.md` for the page format and rules.
2. Read the changed raw source(s) under `docs/superpowers/specs/` or `plans/`.
3. Update or create the affected page(s) under `docs/wiki/` (`overview.md`, `behaviors/`, `platforms/`). Keep prose accurate, add inline citations, set `sources` and `updated`, and use basename wikilinks like `[[oauth-flow]]`. On a `behavior` page, update its `features:` platform status (and `note`) when the change affects what works on which platform — this feeds the generated support matrix (see the "Platform support matrix" section in conventions).
4. Update cross-references on related pages.
5. Append a one-line entry to `docs/wiki/log.md`.

## Lint + rebuild (deterministic — run the tool)

After editing, run:

```bash
mise run wiki:lint     # validate frontmatter, [[links]], source paths, feature blocks
mise run wiki:matrix   # regenerate docs/wiki/support-matrix.md
mise run wiki:index    # regenerate docs/wiki/index.md
```

Fix anything lint reports. Never hand-edit `index.md` or `support-matrix.md`. The pre-commit hook (`mise run wiki:install-hooks`) runs these automatically when `docs/wiki/**` is staged, but run them yourself so problems surface before commit.

## Query

To answer a question about the app: read `docs/wiki/index.md` first, open only the relevant pages, answer with citations. Persist a durable answer as a new page if it will be reused.
