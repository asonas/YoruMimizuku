---
title: Authentication (OAuth + DPoP)
type: behavior
updated: 2026-06-06
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - core/Sources/BlueskyCore/OAuth/RefreshGate.swift
  - core/Sources/BlueskyCore/OAuth/SessionExpiry.swift
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

(`2026-06-04-yorumimizuku-design.md` §5.2)

## DPoP essentials

A P-256 key is held in the Keychain (Secure Enclave use is a later decision). Every request carries `Authorization: DPoP <token>` plus a DPoP proof header (`htm` / `htu` / `iat` / `jti` / `ath` = access-token hash / `nonce`). On `401 use_dpop_nonce`, rebuild the proof with the returned `DPoP-Nonce` and retry exactly once. This round trip is centralized in a dedicated wrapper. Refresh is also DPoP-bound (§5.3, the `DPoP` module in §4.3).

This "401 → refresh → retry once" pattern is the common shape reused across XRPC calls; the composer ([[compose-post]]) and the search service ([[filters]]) follow the same convention.

## Token refresh: coalescing and session expiry

atproto refresh tokens are **single-use and rotated** — each `refresh_token` grant returns a new refresh token and immediately invalidates the previous one. Because several views poll independently (home, notifications, and each filter tab every 30s; see [[timeline-streaming]]), two of them hitting a 401 at the same time would both refresh with the same snapshot token, and atproto would reject all but the first with `invalid_grant`. Worse, a consumed token persisted to the Keychain never self-heals, so every later refresh keeps failing and retrying is futile.

Two pieces address this:

- **`RefreshGate` (coalescing).** A shared actor (`core/Sources/BlueskyCore/OAuth/RefreshGate.swift`) keyed by the refresh-token value. Concurrent renewals for the same token collapse into a single network call, and a straggler still holding the now-consumed token reuses the cached result instead of replaying the dead one. One shared instance lives on `AccountManager.refreshGate` and is threaded through every XRPC service (via `LiveServiceContext`), so all tabs coalesce. Failures are not cached, so a genuinely dead token still surfaces its error. Covered by `RefreshGateTests`.
- **`SessionExpiry` (recovery).** When a refresh fails irrecoverably (`tokenRequestFailed` with `invalid_grant`; see the parsed OAuth error body in `OAuthError`), `SessionExpiry.reportIfExpired` posts a notification. The view models call it from their error paths (load / refresh / scroll / compose), and `RootView` responds by dropping the dead account and returning to the login screen (switching to another stored account if one exists). Retrying a dead session is futile, so the app routes to re-authentication instead.

## Multi-account

Each window holds its own active account. All account sessions are cached in the Keychain, so switching is instant. `AccountManager` manages the current account and token refresh (modeled after tempest's per-DID / accounts index; §8).

## Where it lives in the core

The OAuth state machine, DPoP proof generation, and identity resolution live in `core/Sources/BlueskyCore` (`OAuth/` / `DPoP/`); Apple-only implementations such as the Keychain are separated into `PlatformApple` ([[macos]]). Tests avoid the real network and verify against `URLProtocol` stubs / fakes (§11).
