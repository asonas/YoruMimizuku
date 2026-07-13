# Session Expiry Re-authentication Design

- Date: 2026-07-13
- Status: Draft for implementation
- Target: `apps/macos` and `apps/ipados` (UX wiring); `BlueskyCore` / `YoruMimizukuKit` unchanged in behavior
- Builds on: `2026-06-04-yorumimizuku-design.md` (OAuth + session model), `2026-06-08-yorumimizuku-ipados-design.md` (iPad shell)

## 1. Overview

When a signed-in account's OAuth session can no longer be refreshed — the server
answers a `refresh_token` grant with `invalid_grant` — the app currently **deletes the
account** (`AccountManager.removeAndAdvance`, which clears its Keychain item) and drops
to the login screen. The user must then re-add the account from scratch: type the
handle, run the whole OAuth browser flow, as if it were a brand-new account.

This happens in normal use because atproto refresh tokens are single-use and have a
limited server-side lifetime, and macOS **suspends polling while asleep**. If the machine
sleeps (or the app sits idle with the machine asleep) longer than the refresh token's
lifetime, the proactive wake refresh legitimately fails with `invalid_grant` and the
account is dropped. Confirmed empirically: a `Session` unified-log entry `"Session expired
while asleep; dropping the account"` correlates with wake-from-sleep.

This is not a client bug — the refresh machinery (a single shared `RefreshGate` that
coalesces every refresh, rotation persistence in every loader, the proactive wake
refresh) is sound, and the client cannot extend the server's token lifetime. The problem
is purely **UX**: a recoverable "your session expired, sign in again" situation is treated
as "delete everything and start over."

This spec changes the expiry handling so the account is **kept** and the user is offered a
one-step re-authentication of the same account, plus adds observability so every expiry
(not just the wake path) leaves a log entry.

## 2. Goals

- On session expiry, **do not delete the account**. Keep its DID, handle, and DPoP key in
  secure storage; only its tokens are dead.
- **Stay on the expired account** (no auto-switch to another account) and **auto-present a
  login sheet pre-filled with the expired account's handle**, so re-authentication is one
  flow, not a re-add.
- On successful re-auth of the same DID, replace that account's tokens + DPoP key in place
  and return to the authenticated timeline.
- If the user cancels the sheet, keep the account and offer a persistent "再ログイン"
  affordance to re-open it — never silently delete.
- Add a single observability log at the expiry-notification handler so **both** the
  reactive (polling) path and the wake path are logged. Never log token material.
- Apply on **both macOS and iPadOS**, sharing the (unchanged) core expiry signal.

## 3. Non-goals

- No change to the refresh/rotation machinery, `RefreshGate`, or `SessionExpiry`'s
  detection rule (`invalid_grant` only) — those are correct.
- No persisted "needs re-auth" flag on `PersistedAccount` (see §7, Approach A). On restart,
  a single failed refresh re-derives the prompt.
- No account-switcher badge for expired accounts (would require the persisted flag; YAGNI
  for the primary pain point).
- No attempt to extend or renegotiate the server-side token lifetime — impossible from a
  public OAuth client.
- No change to **user-initiated logout**, which still deletes the account via
  `removeAndAdvance`.

## 4. Current behavior (what changes)

Both apps observe `SessionExpiry.notification` and call a handler that does
`removeAndAdvance(did)`:

- macOS: `apps/macos/Views/RootView.swift` `handleSessionExpired()` →
  `accountManager.removeAndAdvance(did)`; `currentDID` becomes the next account or `nil`.
- iPad: `apps/ipados/Views/RootView.swift` the equivalent `onReceive` handler →
  `removeAndAdvance`.

The notification is posted by `SessionExpiry.reportIfExpired(_:)` from every reactive
refresh site (the view models: `TimelineViewModel`, `NotificationsViewModel`,
`ThreadViewModel`, `ComposerViewModel`) and from the macOS wake handler
`refreshSessionOnWake()`. Only the wake handler logs; the reactive path is silent.

## 5. New behavior

### 5.1 Expiry → re-auth intent (both apps)

Replace the delete handler with:

1. Read the current account's DID and handle. If there is no current account, no-op.
2. If a re-auth is **already** pending (idempotency guard), no-op — this stops repeated
   poll-driven `invalid_grant` notifications from re-presenting the sheet.
3. Log one line at `category: "Session"`: e.g. `"Session expired; prompting re-auth for
   <did>"` (DID only, never tokens). This is the single point that covers both the reactive
   and wake paths.
4. Set in-memory re-auth state: `reauthHandle = <expired account's handle>` (and remember
   the expected DID). Do **not** touch the store; the account and its Keychain item remain.

### 5.2 Re-auth presentation (Option C: auto-sheet)

- Presenting the re-auth state auto-shows the existing `LoginView` in a sheet, bound to a
  dedicated re-auth `LoginViewModel` whose `handle` is pre-filled with `reauthHandle`.
  Using a distinct view model (not the "add account" one) keeps the two flows independent.
- On success (`LoginViewModel.State.authenticated(did:)`), the login performer has already
  called `AccountManager.add(loginResult:handle:dpopPrivateKeyRaw:)`, which writes
  `account.<did>` (overwriting the same DID's tokens + DPoP key when the re-authed DID
  matches) and sets it current. The app then clears the re-auth state and forces the
  authenticated subtree to rebuild so it reloads immediately with the fresh tokens rather
  than waiting up to a poll interval. The subtree's identity is a composite
  `"\(did)#\(reauthGeneration)"`; setting `currentDID = did` and incrementing
  `reauthGeneration` changes the id in both the different-DID case (new account) and the
  same-DID case (the common re-login), so a fresh set of view models mounts and their
  first `load()` runs against `accountManager.current()`'s replaced tokens. Rebuilding
  resets transient subtree state (scroll position, open filter tabs) — an accepted
  trade-off for a fresh post-re-login session.
- The stale authenticated UI stays mounted **behind** the sheet, so the timeline the user
  was looking at is still there if they cancel.

### 5.3 State model, cancel, and persistent affordance

Each `RootView` holds two pieces of state: `reauth: ReauthRequest?` — the pending fact,
which persists until re-auth succeeds — and `isReauthSheetShown: Bool` — which drives the
sheet. On expiry both are set (`reauth = <request>`, `isReauthSheetShown = true`). The
sheet is presented with `.sheet(isPresented: $isReauthSheetShown)`.

- If the user dismisses the sheet without completing re-auth, `isReauthSheetShown` becomes
  `false` but `reauth` stays set; the sheet is not re-presented automatically (no loop).
- While `reauth != nil`, a slim banner at the top of `RootView.body` (above the
  authenticated subtree, so the stale timeline stays visible below it) shows
  "セッションが期限切れです" with a "再ログイン" button that sets `isReauthSheetShown = true`
  again. The account remains fully listed in the switcher. Keeping this affordance in
  `RootView` (not the child account menu) avoids threading the pending state down into
  `MainWindowView` / the iPad `accountMenu`.
- On success, both `reauth` and `isReauthSheetShown` are cleared (see §5.2).

### 5.4 Edge cases

- **Re-auth returns a different DID** (the user signed in as another account): this is the
  normal `add()` path — the new account becomes current and its subtree is built. The old
  expired account remains in the store; if the user switches back to it, a failed refresh
  re-triggers the re-auth prompt for it. No special handling.
- **Explicit logout** (user taps Logout): unchanged — `removeAndAdvance` deletes the
  account and advances, exactly as today.
- **No current account** at expiry time: no-op.

## 6. Observability

The one log line in §5.1.3 is emitted from the notification handler, which every expiry
funnels through, so the previously silent reactive path is now traceable. The macOS wake
handler keeps its existing, more specific `"Session expired while asleep; dropping the
account"` line (reworded to drop the "dropping the account" clause, since the account is no
longer dropped — e.g. `"Session expired while asleep; prompting re-auth"`). No token,
refresh token, code, or key is ever interpolated into a log string (`WebURL` /
`[[architecture]]` untrusted-content and secrets policy).

## 7. Approach and rationale

**Approach A — in-memory app state (chosen).** The re-auth state lives in the two
`RootView`s as ordinary SwiftUI `@State`. No core change, no `PersistedAccount` schema
change. The account keeps its dead tokens in the store; on app restart while expired, the
first poll's refresh fails with `invalid_grant`, which re-posts the notification and
re-derives the prompt. Cost: one wasted refresh round-trip on a cold start into an expired
account — negligible.

**Approach B — persist a `needsReauth` flag on `PersistedAccount` (rejected).** Would let
the switcher badge an expired account and avoid the cold-start round-trip, but adds
persisted schema surface for no gain against the primary pain point. YAGNI.

## 8. Testing and verification

- Reuse the already-tested `LoginViewModel` and login performer; the new code is thin view
  wiring plus one pure decision (the idempotency guard).
- Extract the "expiry event → re-auth intent" decision (compute the next state given the
  current account and whether a re-auth is already pending) into a small, pure helper so it
  is unit-testable without SwiftUI: assert that a first expiry sets the re-auth state for
  the current DID/handle, a second expiry while pending is a no-op, and no current account
  is a no-op.
- Add a render test (mirroring `SettingsRenderTests`) that presents the re-auth sheet with
  its environment objects, catching env-object crashes on both apps.
- Build both apps (`YoruMimizuku`, `YoruMimizukuPad`) green.
- Manual verification: simulate expiry (e.g. corrupt the stored refresh token or force a
  refresh failure) and confirm the account is preserved, the pre-filled sheet appears,
  re-auth restores the timeline, and cancel leaves a working "再ログイン" affordance.

## 9. Current Status

Design drafted 2026-07-13. Not yet implemented. Next: implementation plan via
`writing-plans`, then TDD implementation on `feature/session-reauth`.
