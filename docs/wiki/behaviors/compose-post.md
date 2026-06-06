---
title: Composing Posts
type: behavior
updated: 2026-06-06
sources:
  - docs/superpowers/specs/2026-06-05-yorumimizuku-compose-post-design.md
---

# Composing Posts

The app posts to Bluesky. In addition to body text, it supports RichText posts with URLs (link facets), hashtags (tag facets), and mentions (mention facets), plus image posts (up to 4, each with alt text). Both top-level posts and replies are supported. Facets follow `app.bsky.richtext.facet` and express ranges with **UTF-8 byte offsets**. The detection logic is a Swift reimplementation of tempest's proven algorithm (`lib/tempest/post.rb`) (`2026-06-05-yorumimizuku-compose-post-design.md`).

## Scope

Included: top-level posts (`createRecord` / `app.bsky.feed.post`), replies (carrying the conversation root and parent refs), automatic facet detection (link / tag / mention), image posts (`uploadBlob` → `app.bsky.embed.images`), a 300-grapheme limit with a remaining counter, and submit-state management.

Excluded: external embeds (OGP link cards), quote posts, video, draft saving / scheduling / threads, post editing (atproto has no edit), and a `langs` UI input.

## Module responsibility boundaries

- `FacetDetector` (`BlueskyCore/RichText`, pure): takes a string and returns link / tag as completed facets, and mentions as candidates (the `@handle` byte range + the handle string). Network-independent and unit-tested.
- `PostService` (`BlueskyCore/XRPC`, network): resolves candidate mention handles to DIDs via `getProfile` and converts only the resolved ones into mention facets. Combines with link/tag, sorts by byte start, assembles the record, and sends. If images exist, it `uploadBlob`s first.
- `ComposerViewModel` (`YoruMimizukuKit`, VM): input state, character count, and submit-ability only. It holds no facet detection or networking and delegates to `PostSubmitting`.
- `LiveComposer` (`apps/macos/Compose`, wiring): assembles the sender / metadataResolver via `LiveServiceContext`, calls `PostService`, and persists refreshed tokens.

## Facet detection (key points)

Everything uses UTF-8 byte offsets (`byteStart` / `byteEnd`), symmetric with the display-side `RichText.segments`.

- **link**: a run starting with `https?://` up to whitespace. Trailing punctuation / closing brackets are excluded from the link range (matching the official `@atproto/api`; tempest does no trailing handling, so this improves on it to match official behavior).
- **tag**: accepts both half-width `#` and full-width `＃`. Must follow text start or whitespace. Digits-only (`#123`) is ignored. Trailing punctuation is stripped; a grapheme length over 64 is ignored. The `tag` value drops the leading `#`.
- **mention**: an `@` following text start, whitespace, `(`, or `[`, then a domain-form handle. `FacetDetector` returns candidates only; DID resolution is done by `PostService` via `getProfile`. On resolution failure the text stays plain (no facet added).
- **combination**: link / tag / mention are sorted by ascending `byteStart` into `record.facets`. If empty, the field is omitted.

## Data flow and the common pattern

Submission goes `ComposerViewModel.submit()` → `PostSubmitting.submit(_:)` → `LiveComposer` → `PostService.createPost(...)`. If images exist, each is `uploadBlob`ed (over DPoP) to obtain a `BlobRef`, then facets are assembled and `createRecord` is sent. On `401` (other than a nonce challenge) it refreshes and retries once, persisting the refreshed token. This 401 retry is the same common pattern as [[oauth-flow]].

For replies, before sending, the parent URI is resolved via `getRecord` to fill `reply.root` / `reply.parent`. If the parent is itself a reply, its `reply.root` is inherited; if top-level, the parent becomes the root (matching tempest's `fetch_reply_refs`).

## Image upload

Up to 4. Each image is sent to `uploadBlob` as binary with its image MIME, yielding a `BlobRef` (`{ $type: "blob", ref: { $link: <cid> }, mimeType, size }`). Resizing / re-encoding / the 1 MB cap is handled app-side (downscaling on the macOS side if needed, considering the existing `ImageDownsampler`); the core only receives bytes and MIME.

## UI entry points

The composer is shown as a sheet. On the home view, `n` (no modifier) opens a new post and a post row's reply button opens a reply. On `uploadBlob` failure the whole post is aborted (no partial send); a mention DID-resolution failure is non-fatal and the post continues with plain text.
