# /wiki-update

Maintain the git-versioned LLM-wiki at `docs/wiki/` — the cross-machine knowledge layer shared by Claude and Cursor on macOS and the build agent on Windows.

This command mirrors the Claude Code skill `.claude/skills/wiki-update/SKILL.md`. Both point at the same canonical procedure so the workflow is identical in either tool.

**Read `docs/wiki/conventions.md` first, then follow it.** Summary:

1. Read the changed raw source(s) under `docs/superpowers/specs/` or `plans/`.
2. Update or create the affected page(s) under `docs/wiki/` (`overview.md`, `behaviors/`, `platforms/`): accurate prose, inline citations, `sources` + `updated` frontmatter, basename wikilinks like `[[oauth-flow]]`. On a `behavior` page, also update its `features:` platform status (and `note`) when the change affects which platforms support it — this feeds the generated support matrix.
3. Check platform differences: every `differs` / `limited` / `none` you touched, and every macOS/Windows contrast in prose you changed, is deliberate with a cited reason or a `bug:` note with an issue link ("Platform differences" in conventions).
4. Update cross-references on related pages and append one line to `docs/wiki/log.md`.
5. Run the deterministic bookkeeping and fix what it reports:

   ```bash
   mise run wiki:lint
   mise run wiki:matrix
   mise run wiki:index
   ```

Never hand-edit `docs/wiki/index.md` or `docs/wiki/support-matrix.md` — they are generated. To answer a question, read `docs/wiki/index.md`, open only the relevant pages, and cite sources.
