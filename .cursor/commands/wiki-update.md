# /wiki-update

Maintain the git-versioned LLM-wiki at `docs/wiki/` — the cross-machine knowledge layer shared by Claude and Cursor on macOS and the build agent on Windows.

This command mirrors the Claude Code skill `.claude/skills/wiki-update/SKILL.md`. Both point at the same canonical procedure so the workflow is identical in either tool.

**Read `docs/wiki/conventions.md` first, then follow it.** Summary:

1. Read the changed raw source(s) under `docs/superpowers/specs/` or `plans/`.
2. Update or create the affected page(s) under `docs/wiki/` (`overview.md`, `behaviors/`, `platforms/`): accurate prose, inline citations, `sources` + `updated` frontmatter, basename wikilinks like `[[oauth-flow]]`.
3. Update cross-references on related pages and append one line to `docs/wiki/log.md`.
4. Run the deterministic bookkeeping and fix what it reports:

   ```bash
   mise run wiki:lint
   mise run wiki:index
   ```

Never hand-edit `docs/wiki/index.md` — it is generated. To answer a question, read `docs/wiki/index.md`, open only the relevant pages, and cite sources.
