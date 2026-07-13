---
title: Authentication (OAuth + DPoP)
type: behavior
updated: 2026-07-13
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/specs/2026-07-13-session-reauth-design.md
  - docs/superpowers/plans/2026-07-13-session-reauth.md
  - docs/superpowers/plans/2026-06-04-yorumimizuku-oauth-discovery.md
  - docs/superpowers/plans/2026-06-04-yorumimizuku-oauth-par-authz-url.md
  - docs/superpowers/plans/2026-06-04-yorumimizuku-oauth-pkce-dpop-sender.md
  - docs/superpowers/plans/2026-06-04-yorumimizuku-oauth-token-exchange.md
  - docs/superpowers/plans/2026-06-04-yorumimizuku-oauth-client-orchestrator.md
  - docs/superpowers/plans/2026-06-04-yorumimizuku-dpop.md
  - docs/superpowers/plans/2026-06-04-yorumimizuku-login-integration.md
  - core/Sources/BlueskyCore/OAuth/RefreshGate.swift
  - core/Sources/BlueskyCore/OAuth/SessionExpiry.swift
  - core/Sources/BlueskyCore/OAuth/SessionRefresher.swift
  - core/Sources/YoruMimizukuKit/SessionReauth.swift
features:
  - name: OAuth login (PKCE + DPoP)
    macos: full
    windows: full
    ios: full
    android: planned
  - name: Browser authorization
    macos: full
    windows: differs
    ios: differs
    android: planned
    note: "macOS and iPadOS both use ASWebAuthenticationSession, but iPadOS anchors presentation to a foreground UIWindowScene; Windows embeds WebView2 ([[ipados]], [[windows]])."
  - name: Token refresh & session recovery
    macos: full
    windows: full
    ios: full
    android: planned
---

# Authentication (OAuth + DPoP)

YoruMimizuku authenticates with Bluesky OAuth (PKCE + DPoP). App passwords are not used. OAuth is a public client (`token_endpoint_auth_method: none`), so there is no client secret. DPoP private keys and OAuth tokens are all stored in the Keychain and must never be written to the repository or logs (`2026-06-04-yorumimizuku-design.md` §5, AGENTS.md "Publishing Policy").

## client-metadata.json

A native OAuth client must publish a single static JSON at an HTTPS `client_id`. YoruMimizuku hosts it on `ason.as` (`https://ason.as/yorumimizuku/client-metadata.json`). The redirect uses the custom scheme `as.ason:/callback`, opened via `ASWebAuthenticationSession`. The v1 scope is `atproto transition:generic` (general read/write); the plan is to narrow it once granular scopes are available (§5.1, §5.4). The public metadata copy lives in the repo at `docs/client-metadata.json`.

## Login flow

1. Identity resolution: input handle → DID (`com.atproto.identity.resolveHandle` or DNS / `.well-known`) → resolve the PDS endpoint from the DID document.
2. Authz server discovery: PDS `/.well-known/oauth-protected-resource` → identify the authorization server → fetch `/.well-known/oauth-authorization-server` metadata.
3. PAR (Pushed Authorization Request): POST the PKCE challenge, scope, and DPoP proof; receive a `request_uri`.
4. Browser authorization: open the authorize endpoint via `ASWebAuthenticationSession`; the user approves in the browser.
5. Token exchange: exchange the authorization code with DPoP binding (including nonce retry). Obtain access / refresh tokens and a DPoP nonce.
6. Storage: store tokens and the DPoP private key per-DID in the Keychain.

(`2026-06-04-yorumimizuku-design.md` §5.2). Each step was built as its own plan: discovery (`oauth-discovery`), PAR + authorize URL (`oauth-par-authz-url`), the PKCE/DPoP sender (`oauth-pkce-dpop-sender`), token exchange (`oauth-token-exchange`), the orchestrator that wires them together (`oauth-client-orchestrator`), the DPoP module (`dpop`), and the app-side login wiring (`login-integration`).

## DPoP essentials

A P-256 key is held in the Keychain (Secure Enclave use is a later decision). Every request carries `Authorization: DPoP <token>` plus a DPoP proof header (`htm` / `htu` / `iat` / `jti` / `ath` = access-token hash / `nonce`). On `401 use_dpop_nonce`, rebuild the proof with the returned `DPoP-Nonce` and retry exactly once. This round trip is centralized in a dedicated wrapper. Refresh is also DPoP-bound (§5.3, the `DPoP` module in §4.3).

This "401 → refresh → retry once" pattern is the common shape reused across XRPC calls; the composer ([[compose-post]]) and the search service ([[filters]]) follow the same convention.

## Token refresh: coalescing and session expiry

atproto refresh tokens are **single-use and rotated** — each `refresh_token` grant returns a new refresh token and immediately invalidates the previous one. Because several views poll independently (home, notifications, and each filter tab every 30s; see [[timeline-streaming]]), two of them hitting a 401 at the same time would both refresh with the same snapshot token, and atproto would reject all but the first with `invalid_grant`. Worse, a consumed token persisted to the Keychain never self-heals, so every later refresh keeps failing and retrying is futile.

Two pieces address this:

- **`RefreshGate` (coalescing).** A shared actor (`core/Sources/BlueskyCore/OAuth/RefreshGate.swift`) keyed by the refresh-token value. Concurrent renewals for the same token collapse into a single network call, and a straggler still holding the now-consumed token reuses the cached result instead of replaying the dead one. One shared instance lives on `AccountManager.refreshGate` and is threaded through every XRPC service (via `LiveServiceContext`), so all tabs coalesce. Failures are not cached, so a genuinely dead token still surfaces its error. Covered by `RefreshGateTests`.
- **`SessionExpiry` (recovery).** When a refresh fails irrecoverably (`tokenRequestFailed` with `invalid_grant`; see the parsed OAuth error body in `OAuthError`), `SessionExpiry.reportIfExpired` posts a notification. The view models call it from their error paths (load / refresh / scroll / compose). On both macOS and iPad, `RootView` now **keeps** the account instead of dropping it: the pure helper `SessionReauth.onExpiry(currentDID:currentHandle:isPending:)` (`core/Sources/YoruMimizukuKit/SessionReauth.swift`) turns the event into a `ReauthRequest?` (nil if there is no current account, or if a re-auth is already pending — the idempotency guard against repeated poll-driven notifications). `RootView` sets its in-memory re-auth state from that request and auto-presents the existing `LoginView` in a sheet, bound to a dedicated re-auth `LoginViewModel` pre-filled with the expired account's handle, while the stale authenticated UI stays mounted behind the sheet. If the user cancels, the sheet closes but the re-auth state is not cleared, so a persistent `SessionReauthBanner` ("セッションが期限切れです" / "再ログイン") sits above the still-visible timeline as the fallback to re-open the sheet. On success, `AccountManager.add` replaces the same DID's tokens and DPoP key in place, the re-auth state clears, and the authenticated subtree's id (`"\(did)#\(reauthGeneration)"`) changes to force a fresh mount that reloads with the new tokens. Switching accounts or explicit logout also clears the re-auth state; only logout still deletes the account via `removeAndAdvance` (§ [[accounts]]). Retrying a dead session is futile, so the app routes to re-authentication instead of requiring a from-scratch re-add (`2026-07-13-session-reauth-design.md` §5).

### Proactive refresh on wake

Refresh is otherwise purely reactive — it only fires when an XRPC request returns 401. That leaves a gap around sleep: while the Mac is asleep the polling tasks are suspended and nothing renews the token, so on wake the access token has typically expired and several pollers would resume at once and race to refresh. To close it, `RootView` observes `NSWorkspace.didWakeNotification` (posted on the workspace's own notification center, not `NotificationCenter.default`) and proactively renews the current account's session up front via `SessionRefresher` (`core/Sources/BlueskyCore/OAuth/SessionRefresher.swift`), persisting the rotated tokens before the pollers fire. The proactive refresh is routed through the same shared `RefreshGate`, so it coalesces with any concurrent 401-driven refresh on the same single-use token rather than racing it. An `invalid_grant` here (the refresh token died during a long sleep) flows through `SessionExpiry` into the same keep-and-re-auth handling as any other expiry (no longer a drop); transient wake errors (e.g. the network not yet up) are left for the next request's reactive refresh. Wake outcomes are logged under the `Session` category (event-level only — never token material): the wake path logs `"Session expired while asleep; prompting re-auth"` (reworded from the old "...dropping the account", since the account is no longer dropped). The reactive expiry path is now logged too — a single `"Session expired; prompting re-auth"` line in the notification handler covers it, closing the gap where only the wake path used to be traceable.

## Multi-account

A successful login is persisted per-DID and managed by `AccountManager`; each window holds its own active account and switching is instant. How accounts are stored, indexed, and switched is covered in [[accounts]].

## Where it lives in the core

The OAuth state machine, DPoP proof generation, and identity resolution live in `core/Sources/BlueskyCore` (`OAuth/` / `DPoP/`); Apple-only implementations such as the Keychain are separated into `PlatformApple` ([[macos]]). Tests avoid the real network and verify against `URLProtocol` stubs / fakes (§11).

On [[ipados]], login uses the same client metadata and redirect URI, but the
browser adapter lives under `apps/ipados/Auth` so it can return a `UIWindow`
presentation anchor for `ASWebAuthenticationSession`
(`2026-06-08-yorumimizuku-ipados-design.md` §7).
