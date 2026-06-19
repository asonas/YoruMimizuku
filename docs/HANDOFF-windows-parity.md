# Windows parity — handoff notes

Status as of 2026-06-20 (branch `feature/windows-v1-parity`): every macOS feature
that was actually implemented up to **1.0.0-dev.8** has been implemented on
Windows. Nothing in that set was impossible on Windows. This file records the few
**Windows-specific deviations and deferrals** where the Windows result differs from
macOS or where a fuller implementation was intentionally postponed.

## Deviations (implemented, but not pixel-identical to macOS)

- **Sensitive-media gating uses a cover, not a blur.** macOS blurs labelled
  adult/graphic media (`.blur(radius: 28)`) behind a tap-to-reveal curtain. WinUI/XAML
  has no cheap way to blur an arbitrary subtree (no built-in `UIBlur`; a real Gaussian
  blur needs a `Microsoft.UI.Composition` backdrop/effect or Win2D, which would add a
  dependency). Windows instead **covers** the media with an opaque rounded curtain
  showing the same 閲覧注意 text + タップで表示, revealing on tap. Privacy outcome is
  equivalent (media hidden until reveal); only the look differs. The support matrix
  marks this row `differs` for Windows. *To close the gap:* render the media into a
  `Microsoft.UI.Composition` visual and apply a `GaussianBlurEffect` (or Win2D
  `CanvasEffect`) gated by the same reveal flag in
  `FeedView.xaml.cs` `PopulateCurtain`.

## Deferrals (carried over, not in this scope)

- **Numeric taskbar badge** for unread notifications needs packaged (MSIX) identity
  (`BadgeNotification`/`BadgeUpdateManager`). The unpackaged app instead shows an OS
  toast (`AppNotificationManager`) + a taskbar attention flash (`FlashWindowEx`); the
  in-app tab badge carries the count. Revisit when the app ships as MSIX.

- **Inline video playback** is post-1.0 on every platform; both macOS and Windows show
  the video poster + open the post in the browser. Not a Windows gap.

- **Quoted-record nesting**: a quote inside a quoted post is dropped (one level), same
  as macOS `QuotedPost`. Not a Windows gap.

## Not implemented on macOS — intentionally skipped

Per the goal, features that are spec/roadmap-only but not implemented on macOS were
**not** built on Windows:

- **Jetstream live updates** — no front end wires a Jetstream WebSocket; macOS and
  Windows both poll + top-merge. Deferred past v1.0.0 (see [[timeline-streaming]]).
- **OS notification banner + Dock badge on macOS** — designed but unimplemented on
  macOS; deferred. (Windows happens to have its own OS toast + flash, ahead of this.)
- **Fuller moderation** (per-user label preferences, subscribed labelers, account-level
  labels, hiding whole posts) — deferred past v1.0.0 on all platforms.

## Version note

The Windows app csproj `Version` is still `0.8.0` while the macOS/core marketing
version is `1.0.0-dev.8`. The Windows version was left as-is (the goal was feature
parity, not a release bump); set it deliberately when cutting the next Windows build.
