---
title: Composing Posts
type: behavior
updated: 2026-07-24
sources:
  - docs/superpowers/specs/2026-06-05-yorumimizuku-compose-post-design.md
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/specs/2026-06-25-compose-image-paste-drop-design.md
  - docs/superpowers/specs/2026-06-25-compose-video-upload-design.md
  - docs/superpowers/plans/2026-06-05-yorumimizuku-compose-post.md
  - docs/superpowers/plans/2026-06-08-macos-compose-notification-followups.md
  - docs/superpowers/plans/2026-06-25-compose-image-paste-drop.md
  - docs/superpowers/plans/2026-06-25-compose-video-upload.md
  - docs/superpowers/plans/2026-07-24-apple-hig-remediation.md
  - core/Sources/YoruMimizukuKit/ComposerViewModel.swift
  - core/Sources/BlueskyCore/XRPC/VideoUploadService.swift
  - core/Sources/BlueskyCore/XRPC/PostService.swift
  - apps/macos/Views/ComposerView.swift
  - apps/macos/Views/ComposerTextView.swift
  - apps/macos/Media/ImageEncoder.swift
  - apps/macos/Media/ComposerMediaIntake.swift
  - apps/macos/Media/VideoAttachment.swift
  - apps/ipados/Media/VideoAttachment.swift
  - apps/windows/App/ViewModels/ComposerViewModel.cs
  - apps/windows/App/Views/ComposerDialog.xaml
  - apps/windows/App/Views/ComposerDialog.xaml.cs
features:
  - name: Post / reply / quote (facets, mention resolution)
    macos: full
    windows: full
    ios: full
    android: planned
  - name: Image attachment (up to 4, alt text)
    macos: full
    windows: full
    ios: full
    android: planned
    note: "Windows now exposes a per-image alt-text editor with a remove button and WIC downsampling/JPEG re-encode before upload; iPadOS uses PhotosPicker with alt-text fields and JPEG re-encoding ([[ipados]], [[windows]])."
  - name: Video attachment (one, alt text, exclusive with images)
    macos: full
    windows: planned
    ios: full
    android: planned
    note: "macOS (fileImporter) and iPadOS (PhotosPicker) attach one video with a poster thumbnail and alt text; upload runs getServiceAuth → video service uploadVideo → getJobStatus poll → app.bsky.embed.video. Windows is specced for a follow-up ([[windows]])."
  - name: Draft discard confirmation
    macos: full
    windows: planned
    ios: full
    android: planned
    note: "A draft is unsaved content (non-blank text, images, or video) excluding reply or quote targets; discarding an unsaved draft shows a confirmation dialog. While a post is submitting, the cancel button is disabled and interactive dismissal is blocked ([[ipados]] swipe-down). In-flight post cancellation is not yet implemented; the app waits for submission to complete or fail."
---

# Composing Posts

The app posts to Bluesky. In addition to body text, it supports RichText posts with URLs (link facets), hashtags (tag facets), and mentions (mention facets), plus image posts (up to 4, each with alt text). Both top-level posts and replies are supported, and any post can be **quoted** (a record embed). Facets follow `app.bsky.richtext.facet` and express ranges with **UTF-8 byte offsets**. The detection logic is a Swift reimplementation of tempest's proven algorithm (`lib/tempest/post.rb`) (`2026-06-05-yorumimizuku-compose-post-design.md`).

## Scope

Included: top-level posts (`createRecord` / `app.bsky.feed.post`), replies (carrying the conversation root and parent refs), quote posts (`app.bsky.embed.record`, or `app.bsky.embed.recordWithMedia` when images accompany the quote), automatic facet detection (link / tag / mention), image posts (`uploadBlob` → `app.bsky.embed.images`), **video posts** (one video, exclusive with images, → `app.bsky.embed.video`), a 300-grapheme limit with a remaining counter, and submit-state management.

Excluded: external embeds (OGP link cards) on the *write* side — a posted URL becomes a link facet, not an `app.bsky.embed.external` record (the display side does render link cards; see [[timeline-streaming]]) — plus client-side video transcoding (the original bytes are sent as-is) and strict client-side video limit checks (`getUploadLimits`), video captions, draft saving / scheduling / threads, post editing (atproto has no edit), and a `langs` UI input.

> Note: the design spec originally listed quote posts as out of scope (`2026-06-05-yorumimizuku-compose-post-design.md` §"含まないもの"). They have since been implemented in the core and both front ends, so this page documents the shipped behavior; the spec text predates that change.

## Module responsibility boundaries

- `FacetDetector` (`BlueskyCore/RichText`, pure): takes a string and returns link / tag as completed facets, and mentions as candidates (the `@handle` byte range + the handle string). Network-independent and unit-tested.
- `PostService` (`BlueskyCore/XRPC`, network): resolves candidate mention handles to DIDs via `getProfile` and converts only the resolved ones into mention facets. Combines with link/tag, sorts by byte start, assembles the record, and sends. If images exist, it `uploadBlob`s first. A quote target becomes a `StrongRef` (uri + cid) in the record's embed slot: `app.bsky.embed.record` alone, or `app.bsky.embed.recordWithMedia` when images are also attached (`PostWrite.swift` `PostEmbedWrite`).
- `ComposerViewModel` (`YoruMimizukuKit`, VM): input state, character count, and submit-ability only. It holds no facet detection or networking and delegates to `PostSubmitting`. It optionally carries a `quotedPost`; a quote with no body text is still submittable (quoting alone is valid). At submission it trims trailing whitespace and blank lines from the body (interior line breaks are preserved) so a draft ending in stray newlines is never published verbatim (`ComposerViewModel.swift` `trimmingTrailingWhitespace(of:)`).
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

On [[macos]], `ImageEncoder.encodeForUpload` accepts the AT Protocol image formats. PNG, JPEG, GIF, and WebP that already fit under the ~1 MB cap pass through untouched (so an animated GIF keeps its animation and a WebP keeps its encoding); anything larger, or in another format such as HEIC, is downscaled and re-encoded as JPEG. The composer takes attachments four ways, all normalized through the same encoder: the photo button (`fileImporter` for png/jpeg/gif/webp/heic), drag-and-drop onto the sheet outside the editor (`VStack.onDrop`), **drag-and-drop onto the body editor**, and **paste (Cmd+V)**. The body is a custom `AttachingTextView` (an `NSViewRepresentable` wrapping `NSTextView`) rather than `TextEditor`, because `TextEditor`'s own `NSTextView` consumes drops and pastes itself and would insert the file path as text. `AttachingTextView.paste(_:)` / `performDragOperation(_:)` divert image file URLs and raw image data (screenshots, browser copies) to the attach path and fall through to default behavior for plain text; `ComposerMediaIntake` turns a pasteboard snapshot into encoded attachments, preferring file URLs over raw data so a Finder item keeps its original bytes (`apps/macos/Media/ComposerMediaIntake.swift`, `apps/macos/Views/ComposerTextView.swift`, `apps/macos/Views/ComposerView.swift`).

On [[windows]], `ComposerViewModel` mirrors the core image payload (`dataBase64`, `mimeType`, `alt`) and caps attachments at 4. The current `ComposerDialog` uses a `FileOpenPicker` for PNG/JPEG files, shows thumbnails with a per-image alt-text editor, and runs WIC downsampling / JPEG re-encode (`ImageProcessing.PrepareAsync`) before calling `yoru_post_create`. It does **not** yet support paste (Ctrl+V) or drag-and-drop image attach — the `TextBox` has no `AllowDrop` or paste override, so an image paste / file drop simply does nothing (no path is inserted, unlike the old macOS behavior). The implementation plan for adding both is recorded for a Windows-machine follow-up (`2026-06-25-compose-image-paste-drop-design.md` §"Windows", `apps/windows/App/ViewModels/ComposerViewModel.cs`, `apps/windows/App/Views/ComposerDialog.xaml.cs`).

On [[ipados]], compose is a sheet backed by the same `ComposerViewModel` and
`LiveComposer`. `PhotosPicker` loads images from the photo library, the app
compresses them to JPEG before upload, and each attachment has an alt-text field
(`apps/ipados/Views/ComposerView.swift`, `apps/ipados/Media/ImageEncoder.swift`).

## Video upload

A post can carry **one** video, which is **mutually exclusive** with images (atproto
allows a single media kind), enforced in `ComposerViewModel` (`canAddVideo` /
`canAddImage` each require the other to be empty). Unlike an image's single
`uploadBlob`, video upload is a multi-step flow against a *different* host with a
**Bearer** service-auth token (not DPoP), implemented in `VideoUploadService` and
`PostService.getServiceAuth` (core):

1. `getServiceAuth` on the user's PDS (DPoP) with `aud = did:web:<PDS host>`,
   `lxm = com.atproto.repo.uploadBlob`, `exp = now + 30m` → a short-lived JWT.
2. `uploadVideo` POSTs the raw bytes to `https://video.bsky.app/xrpc/app.bsky.video.uploadVideo?did=&name=`
   with `Authorization: Bearer <token>` → a job.
3. `pollUntilComplete` polls `app.bsky.video.getJobStatus` until `jobStatus.blob`
   is ready (or the job fails / times out).
4. `createPost` embeds the blob as `app.bsky.embed.video` (`video` + optional
   `aspectRatio` + `alt`), or `app.bsky.embed.recordWithMedia` with the video as
   media when the post also quotes. `LiveComposer` orchestrates steps 1–4 and
   threads refreshed tokens forward (the refresh token is single-use).

The flow is unit-tested with fakes (job-status decode for in-progress / completed /
failed, the polling state machine, the upload request shape, `getServiceAuth` query
building, the `app.bsky.embed.video` encoding); the live upload path is verified
manually with a real account.

On [[macos]] the composer adds a video button (`fileImporter` for `.movie` /
`.mpeg4Movie` / `.quickTimeMovie`); on [[ipados]] a second `PhotosPicker`
(`matching: .videos`). Both use `VideoAttachment` (AVFoundation) to read the pixel
dimensions (for `aspectRatio`) and a poster frame for the thumbnail, and show the
upload/processing phase (`ComposerViewModel.SubmitPhase`) while the post is in
flight (`apps/macos/Media/VideoAttachment.swift`, `apps/ipados/Media/VideoAttachment.swift`,
`core/Sources/BlueskyCore/XRPC/VideoUploadService.swift`). [[windows]] video attach
is specced for a follow-up (`2026-06-25-compose-video-upload-design.md` §"Windows").

## UI entry points

The composer is shown as a sheet. On the home view, `n` (no modifier) opens a new post and a post row's reply button opens a reply. A post row's repost button does not toggle directly: it opens a small menu offering **リポスト** (toggle the repost; "リポストを取り消す" when already reposted) and **引用** (open the composer as a quote of that post). The quote composer shows a read-only preview of the post being quoted. This repost/quote menu is present on both [[macos]] (a popover) and [[windows]] (a `MenuFlyout`). On `uploadBlob` failure the whole post is aborted (no partial send); a mention DID-resolution failure is non-fatal and the post continues with plain text.

## macOS composer follow-ups

The macOS composer shows a compact preview when opened as a reply: avatar, display
name / handle, and the first two lines of the replied-to post. The full parent
`PostDisplay` is held on `ComposerViewModel` for display, while submission still
passes only the parent URI through `PostDraft`. While submitting, the Post button
itself is replaced by a small progress indicator so the sheet does not resize.
`Command-Return` and `Control-Return` submit the draft when `canSubmit` is true
(`2026-06-08-macos-compose-notification-followups.md`, `ComposerViewModel.swift`,
`apps/macos/Views/ComposerView.swift`).

The editor itself (`ComposerTextView` / `AttachingTextView`) uses the app font
family (Hiragino Sans) at a slightly larger fixed size (15pt) instead of the
smaller raw system body face, so the text being typed reads as clearly as the
rest of the UI, and its text container is flush-left with the rest of the sheet.
A `Divider` separates the text-input area (and any reply / quote / image previews)
from the footer controls — the attach button, remaining-character counter, and
Post button (`apps/macos/Views/ComposerView.swift`, `apps/macos/Views/ComposerTextView.swift`).

## Draft discard protection

A draft has unsaved content when it holds non-blank text, images, or a video; reply or quote targets alone do not count as unsaved content since reopening the composer recreates them. `ComposerViewModel.hasUnsavedContent` exposes this distinction. When a user tries to discard an unsaved draft (via the Cancel button on [[macos]] or iPad, or by closing the sheet), a confirmation dialog asks "下書きを破棄しますか？" with "破棄する" (discard) and "編集を続ける" (keep editing) buttons. While a post submission is in flight, the Cancel button is disabled and interactive dismissal (Esc / sheet swipe-down on [[ipados]]) is blocked, forcing the user to wait for the post to complete or fail. In-flight post cancellation is not implemented; this is a known limitation for future enhancement.
