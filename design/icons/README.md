# YoruMimizuku icons

The icons used by the macOS app (and meant to be shared with Windows), one SVG
per icon with a JSON metadata file beside it.

## Origin and license

- **From Lucide, unchanged (51 icons).** Every icon Lucide has is Lucide's own SVG,
  copied unchanged from revision
  [`d79f705`](https://github.com/lucide-icons/lucide/tree/d79f7054831776702c2f0e6b795069750f0a4f28/icons),
  with its metadata (only `$schema` is changed to the pinned schema URL). They
  are under Lucide's ISC license, and those Lucide marks as derived from
  Feather are also under Feather's MIT license; both notices are in
  [`LICENSE-lucide.txt`](LICENSE-lucide.txt), which must stay with the files.
- **Built on Lucide (1 icon).** `video-plus` is Lucide's `video` with a plus
  added inside the body, so it is a modified Lucide icon under the same
  licenses. Its metadata lists Lucide's contributors to `video` and `asonas`.
- **Drawn for YoruMimizuku (1 icon).** `message-quote` is a round speech
  bubble with quote marks. Lucide has the square `message-square-quote` but no
  round one, so it was drawn here on Lucide's conventions; its metadata lists
  `asonas`, and it shares the repository's license.

All icons come from one Lucide revision. To move to another, copy every Lucide
icon's SVG and JSON from it at once (and rebuild `video-plus` from its
`video`), set `$schema` in every JSON to the new revision's schema, and update
the revision here and in `tools/icons/lint.py`.

## Rules

- **Drawing.** Lucide's conventions
  (<https://lucide.dev/contribute/icons/>): a 24×24 canvas, 2-unit stroke,
  round caps and joins, at least 1 unit of padding, at least 2 units between
  elements, and only `path`, `line`, `polyline`, `polygon`, `circle`, `ellipse`
  and `rect` with position and size attributes. The root `<svg>` attributes
  follow Lucide's order.
- **Names.** Lucide's names. An icon of our own is named in the same way:
  lowercase kebab-case, after what is drawn rather than what it is used for,
  in `<group>-<variant>` order.
- **Metadata.** Each `<name>.json` has `$schema`, `contributors`, `tags`,
  `categories` (from Lucide's `icon.schema.json` list, or `$extends:<icon>`)
  and `use-cases`.
- **States.** There are no filled variants: a liked or reposted post shows the
  same outline in its reaction color.
- **Checking.** `mise run icons:lint` checks what can be checked mechanically:
  root attributes, elements and attributes, the safe zone for simple shapes,
  names and metadata.

The app bundles this folder as `icons` and loads each SVG as a template image
(`apps/macos/Views/AppIcon.swift`). Window-control icons for Windows are not
chosen yet.
