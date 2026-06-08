---
title: AT Protocol Glossary
type: reference
updated: 2026-06-08
sources:
  - docs/superpowers/specs/2026-06-04-yorumimizuku-design.md
---

# AT Protocol Glossary

Short definitions of the AT Protocol and OAuth terms used throughout this wiki, as they apply to YoruMimizuku. The authoritative behavior is in the linked pages; this page is a quick reference (`2026-06-04-yorumimizuku-design.md`).

- **AT Protocol (atproto)** — the federated protocol underlying Bluesky. YoruMimizuku is a native client for it ([[overview]]).
- **DID** — Decentralized Identifier, the stable account identity (e.g. `did:plc:...`). Sessions, stored accounts, and Jetstream filters are all keyed by DID ([[accounts]]).
- **Handle** — the human-readable name (e.g. `alice.bsky.social`). Login resolves a handle to its DID; handles can change while the DID is stable ([[oauth-flow]]).
- **PDS** — Personal Data Server, the host that stores a user's repository and serves XRPC. The login flow resolves the PDS from the DID document ([[oauth-flow]]).
- **Lexicon** — the schema language for atproto records and XRPC methods. `Models` decodes the needed subset as Codable types ([[architecture]]).
- **NSID** — Namespaced Identifier for a lexicon method/record (e.g. `app.bsky.feed.post`). XRPC calls hit `/xrpc/<nsid>`.
- **XRPC** — the HTTP transport for atproto methods (`GET`/`POST` to `/xrpc/<nsid>`); non-2xx responses map to `XRPCError` (`error` / `message`) ([[architecture]]).
- **OAuth (atproto profile)** — how YoruMimizuku authenticates: a public client whose `client_id` is a published `client-metadata.json`, with no client secret. App passwords are not used ([[oauth-flow]]).
- **PKCE** — Proof Key for Code Exchange; binds the authorization request to the token exchange so an intercepted code is useless ([[oauth-flow]]).
- **PAR** — Pushed Authorization Request; the client POSTs the authorization parameters (with PKCE challenge and a DPoP proof) and gets back a `request_uri` ([[oauth-flow]]).
- **DPoP** — Demonstrating Proof-of-Possession; binds tokens to a P-256 key via a per-request proof JWT, with a one-shot `use_dpop_nonce` retry. Refresh is DPoP-bound too ([[oauth-flow]]).
- **Facet** — a rich-text annotation (mention / link / hashtag) over a byte range of post text. Indices are **UTF-8 byte offsets**, a common source of bugs ([[compose-post]], [[architecture]]).
- **Jetstream** — Bluesky's lightweight JSON firehose. Home and lists subscribe to it (filtered by `wantedDids` + `app.bsky.feed.post`) for live updates, with a stall watchdog that forces reconnection ([[timeline-streaming]]).
- **Cursor** — the pagination / stream-position token. It is persisted so the app can backfill on resume and continue infinite scroll ([[timeline-streaming]]).
- **Custom feed / feed generator** — a server-computed feed addressed by a generator record. It is polled rather than streamed ([[timeline-streaming]]).
- **Blob** — an uploaded binary (e.g. an image) referenced by a `BlobRef`. Images are uploaded via `uploadBlob` before being embedded in a post ([[compose-post]]).
- **Quote post** — a post that embeds another post as a `record` (or `recordWithMedia`) embed ([[compose-post]]).
