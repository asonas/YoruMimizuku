---
title: Accounts (Multi-Account Persistence)
type: behavior
updated: 2026-06-08
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
  - docs/superpowers/specs/2026-06-08-yorumimizuku-ipados-design.md
  - docs/superpowers/plans/2026-06-04-yorumimizuku-account-persistence.md
features:
  - name: Multi-account persistence & switching
    macos: full
    windows: full
    ios: full
    android: planned
---

# Accounts (Multi-Account Persistence)

YoruMimizuku is multi-account. Once you have logged in (see [[oauth-flow]]), the result is persisted securely per DID, several accounts can coexist, and switching between them is instant. This page covers how accounts are stored and selected; how a login is obtained is in [[oauth-flow]].

## What is persisted, and where

A logged-in account is stored as a `PersistedAccount`: DID, handle, PDS URL, authorization-server issuer, access/refresh tokens, scope, and the DPoP private key. Secrets — tokens and the DPoP key — live only in the Keychain, keyed per DID; nothing sensitive is written to the repository or logs (`2026-06-04-yorumimizuku-design.md` §5.2 step 6, §10).

The account layer is deliberately free of CryptoKit: `PersistedAccount` carries the DPoP key as raw bytes (`Data`), and the Apple wiring layer restores it into a P-256 key. That keeps the layer cross-platform, in line with the ports approach in [[architecture]] (`2026-06-04-yorumimizuku-account-persistence.md`).

## Storage layers

Three pieces, from low to high level (`2026-06-04-yorumimizuku-account-persistence.md`):

- **`SecureStorage`** — the secure key/value port (opaque string keys, raw `Data` values). The Apple implementation `KeychainStorage` is a `SecItem` generic-password store namespaced by service (the app bundle id, `as.ason.YoruMimizuku`); tests inject an in-memory fake. This is one of the OS-touchpoint protocols described in [[architecture]].
- **`AccountStore`** — pure logic over `SecureStorage`. Writes one `account.<did>` entry per account plus a single `accounts.index` (`AccountsIndex`: the DID list + the current DID). `save` adds the DID without duplicates; `setCurrent` rejects an unknown DID (`AccountError.unknownAccount`); `remove` deletes the account, drops the index entry, and clears `currentDID` if it pointed there.
- **`AccountManager`** — the high-level surface: `add` (persist a fresh login and make it current), `current`, `allDIDs`, `switchTo`, `remove`. Token refresh and its scheduling are **not** in this layer — they belong to the OAuth client (see [[oauth-flow]]).

`KeychainStorage` is not unit-tested (headless `swift test` can fail on signing requirements); it is verified by building, while all account logic is tested against the in-memory fake.

## Per-window active account

The account model is per-window, not global. A window holds one active account, and its tabs operate under that account; the top-right switcher changes the window's account. Opening a second window with a different account lets you read two accounts side by side. Because every account's session is already cached in the Keychain, switching is immediate (`2026-06-04-yorumimizuku-design.md` §8). The window/tab frame that surfaces the switcher is in [[app-shell]]. The design follows tempest's per-DID / accounts-index approach.

On [[ipados]], the same rule is applied per scene: each iPad scene owns its active
account and `WorkspaceModel`, while the secure account store and shared
`RefreshGate` remain below that scene boundary (`2026-06-08-yorumimizuku-ipados-design.md` §5).
