# AGENTS.md

This file guides AI agents (Cursor, Claude Code, and others) working in this repository. When you start a new session, read this file first before beginning any task.

## Project Overview

YoruMimizuku (夜ミミズク) is a native client for Bluesky (the AT Protocol). It targets macOS first (SwiftUI / Swift 6.0), with iOS and eventually Windows / Android in view. Electron is not used; the goal is a memory-efficient native implementation. The UI follows Yorufukurou: a single column with top tabs to switch between multiple timelines. Authentication uses Bluesky OAuth (PKCE + DPoP).

For the full design, read `docs/superpowers/specs/2026-06-04-yorumimizuku-design.md`. Implementation plans live under `docs/superpowers/plans/`.

## Documentation (LLM-wiki) — read this first

This repository keeps a git-versioned LLM-wiki at `docs/wiki/` that describes how the app behaves and is built. It is the **cross-machine source of context**: because it lives in git, every agent (Claude / Cursor on macOS, the build agent on Windows) reconstructs the same picture by pulling the repo.

- Start at `docs/wiki/index.md`, then open only the pages you need. Do not assume the whole wiki is in context.
- `docs/wiki/overview.md` is the high-level map; behaviors are under `docs/wiki/behaviors/`, platform differences under `docs/wiki/platforms/`. Cross-cutting `concept` and `reference` pages (e.g. `architecture.md`, `glossary.md`) live at the top level of `docs/wiki/`. Pages are classified by frontmatter `type` (`overview` / `concept` / `behavior` / `platform` / `reference` / `meta`), defined in `docs/wiki/conventions.md`.
- The ground truth is `docs/superpowers/specs/` and `plans/`; the wiki is a derived layer that cites them.
- When specs/plans change, or app behavior changes, **update the wiki**: run the `wiki-update` skill (Claude) or `/wiki-update` command (Cursor) — both follow `docs/wiki/conventions.md`.
- Bookkeeping is deterministic and tooled: `mise run wiki:lint` validates, `mise run wiki:index` regenerates `docs/wiki/index.md` (never hand-edit it). Install the pre-commit hook once with `mise run wiki:install-hooks`. Lint also warns (non-fatally) about specs/plans no page cites and about pages with no inbound `[[link]]` — treat those as a prompt to ingest or cross-link.

## Publishing Policy (Important)

This repository will be **published publicly on [tangled.org](https://tangled.org/)**. Before committing or adding files, always verify the following.

- Never commit secrets such as API keys, tokens, passwords, or private keys.
- OAuth is a public client (`token_endpoint_auth_method: none`, PKCE + DPoP); there is no client secret. DPoP private keys and OAuth tokens are all stored in the Keychain — never write them to the repository or logs.
- The values in `client-metadata.json` (`docs/client-metadata.json`) are public metadata intended to be published.
- `DEVELOPMENT_TEAM` in `project.yml` is an Apple Team ID, not a secret, but anyone forking the project must replace it with their own Team ID.

## Project Structure

```
yorumimizuku/
├── project.yml                 # XcodeGen project definition (the single source of truth)
├── core/                       # single SPM package (platform-independent core + adapters)
│   ├── Package.swift
│   └── Sources/
│       ├── BlueskyCore/        #   OAuth(PKCE+DPoP) / DPoP / XRPC / Models / Account / RichText
│       │   └── Ports/          #     protocols for side effects (SecureStorage, HTTPClient, ...)
│       ├── YoruMimizukuKit/     #   View models and display logic (depends on BlueskyCore)
│       ├── PlatformApple/      #   Apple-only impls (Keychain / os logger, #if os(macOS))
│       ├── PlatformWindows/    #   Windows-only impls (DPAPI / BCryptGenRandom, #if canImport(WinSDK))
│       └── YoruMimizukuBridge/ #   C ABI (@_cdecl) DLL surface for the WinUI app
├── apps/
│   ├── macos/                  # macOS app (SwiftUI): Auth / Workspace / Compose / Views / Timeline ...
│   └── windows/                # Windows app (WinUI 3 / C#): Interop (P/Invoke) + MVVM + XAML
├── tools/wiki/                 # SPM CLI that lints and rebuilds the docs/wiki index
├── docs/
│   ├── client-metadata.json    #   OAuth client metadata (public)
│   ├── superpowers/            #   Design specs and implementation plans (ground truth)
│   └── wiki/                   #   LLM-wiki: derived, git-versioned knowledge layer
└── design/app-icon/            # App icon sources (SVG / generation script)
```

> Windows support has landed. The Windows targets (`PlatformWindows`, `YoruMimizukuBridge`, `apps/windows`) are implemented and the WinUI 3 app runs. For the architecture (Swift core + C ABI bridge DLL + WinUI 3 frontend) and the build steps, see `docs/wiki/platforms/windows.md` and `apps/windows/README.md`.

### Module Split

- `BlueskyCore` (SPM library): platform-independent logic — networking, OAuth, XRPC, token refresh. Shared across macOS and Windows.
- `YoruMimizukuKit` (SPM library): view models and display logic. Depends on `BlueskyCore`.
- `PlatformApple` (SPM library): Apple-framework concrete implementations of the core ports (Keychain, logger), gated `#if os(macOS)`.
- `PlatformWindows` (SPM library): Windows concrete implementations of the core ports (DPAPI secure storage, `BCryptGenRandom`), gated `#if os(Windows)`.
- `YoruMimizukuBridge` (SPM dynamic library): C ABI (`@_cdecl`) surface built into `YoruMimizukuBridge.dll`, called from the Windows app via P/Invoke with UTF-8 JSON.
- `apps/macos` (macOS app target): SwiftUI views and the wiring of Apple-specific pieces such as ASWebAuthenticationSession.
- `apps/windows` (WinUI 3 / C# / .NET 8 app): calls the Swift core through the bridge DLL; OAuth runs in WebView2.

## Setup and Build

This project uses **XcodeGen** to generate the project file. `YoruMimizuku.xcodeproj` and `app/YoruMimizuku/Info.plist` are **generated artifacts and are gitignored**. They do not exist right after cloning, so always generate them first.

```bash
# 1. Install XcodeGen (if not already installed)
brew install xcodegen

# 2. Generate the Xcode project and Info.plist from project.yml
xcodegen generate

# 3. Open in Xcode (or build via the CLI below)
open YoruMimizuku.xcodeproj
```

After editing `project.yml`, always re-run `xcodegen generate` to apply changes. Never edit `.xcodeproj` directly — it is overwritten on the next generation.

### Build and Test

```bash
# Test the core package (fast — run this most of the time)
cd core && swift test

# Build including the app
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj

# Test including the app
xcodebuild test -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS'
```

Test targets: `BlueskyCoreTests` and `YoruMimizukuKitTests` (both under `core/Tests/`).

## Workflow

- **Always use `/git-worktree-workflow` when starting new work (feature, bugfix, experiment).** Create a worktree with `git wt feature/xxx`; do not commit directly on the main branch.
- **Always use the `/commit` skill to create commits.** Do not run `git commit` directly. The commit command is `git ai-commit`.
- Write commit messages in English. Do not use Conventional Commits; capitalize the first letter.
- Develop with TDD (Red → Green → Refactor). Do not write many tests at once; advance one step at a time.
- **After merging into `main`, always run `xcodegen generate`.** `YoruMimizuku.xcodeproj` and the `Info.plist`s are generated, gitignored artifacts; a merge that adds or removes sources or changes `project.yml` leaves the local project stale, so regenerate it before building, testing, or releasing from `main`.
- **After merging a feature branch into `main`, delete its now-unneeded worktree.** Run `git wt remove <path>` (or `git worktree remove <path>`) for the merged worktree so stale worktrees do not accumulate. Do this as part of the same merge step.

## Coding Conventions

- Swift 6.0 / strict concurrency. Be mindful of `MainActor` isolation and `Sendable`.
- Abstract side effects (networking, Keychain, browser launch) behind protocols, and inject fakes in tests. Keep the `BlueskyCore` core logic free of direct Apple-framework dependencies.
- The reference implementation is the same author's Ruby terminal client `tempest` (`/Users/asonas/ghq/github.com/asonas/tempest`), whose proven logic serves as the blueprint. This is a high-quality Swift reimplementation, not a port.
