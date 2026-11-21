# AGENTS.md

This file guides AI agents (Claude Code and others) working in this repository. When you start a new session, read this file first before beginning any task.

## Project Overview

YoruMimizuku (夜ミミズク) is a native client for Bluesky (the AT Protocol). It targets macOS first (SwiftUI / Swift 6.0), with iOS and eventually Windows / Android in view. Electron is not used; the goal is a memory-efficient native implementation. The UI follows Yorufukurou: a single column with top tabs to switch between multiple timelines. Authentication uses Bluesky OAuth (PKCE + DPoP).

For the full design, read `docs/adr/0002-overall-design.md`. Design decisions are recorded as ADRs under `docs/adr/`; see "Design documents" below.

## Documentation (LLM-wiki) — read this first

This repository keeps a git-versioned LLM-wiki at `docs/wiki/` that describes how the app behaves and is built. It is the **cross-machine source of context**: because it lives in git, every agent (on macOS or Windows) reconstructs the same picture by pulling the repo.

- Start at `docs/wiki/index.md`, then open only the pages you need. Do not assume the whole wiki is in context.
- `docs/wiki/overview.md` is the high-level map; behaviors are under `docs/wiki/behaviors/`, platform differences under `docs/wiki/platforms/`. Cross-cutting `concept` and `reference` pages (e.g. `architecture.md`, `glossary.md`) live at the top level of `docs/wiki/`. Pages are classified by frontmatter `type` (`overview` / `concept` / `behavior` / `platform` / `reference` / `meta`), defined in `docs/wiki/conventions.md`.
- Code is the source of truth for how the app works. The wiki records behavior contracts and deliberate macOS/Windows differences, and cites the ADRs in `docs/adr/` for why.
- When an ADR is added or changed, or app behavior changes, **update the wiki**: run the `wiki-update` skill, which follows `docs/wiki/conventions.md`.
- macOS and Windows share no core code, so the wiki is where their behavior is kept in step. When you change behavior on one platform, check the other: a difference is either **deliberate** (recorded in the wiki with its reason) or a bug (filed as an issue). See "Platform differences" in `docs/wiki/conventions.md`.
- Bookkeeping is deterministic and tooled: `mise run wiki:lint` validates, `mise run wiki:index` regenerates `docs/wiki/index.md` (never hand-edit it). Install the pre-commit hook once with `mise run wiki:install-hooks`. Lint also warns (non-fatally) about ADRs no page cites and about pages with no inbound `[[link]]` — treat those as a prompt to ingest or cross-link.

## Design documents

- `docs/adr/` — decision records (why something was chosen), numbered `NNNN-slug.md`.
- `docs/plans/` — execution checklists for work in progress only; delete a plan once its work lands.
- `docs/wiki/` — behavior contracts and deliberate macOS/Windows differences.

Details are in "Design documents" in `docs/wiki/conventions.md`.

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
├── core/                       # single SPM package: the Swift core for Apple platforms
│   ├── Package.swift
│   └── Sources/
│       ├── BlueskyCore/        #   OAuth(PKCE+DPoP) / DPoP / XRPC / Models / Account / RichText
│       │   └── Ports/          #     protocols for side effects (SecureStorage, HTTPClient, ...)
│       ├── YoruMimizukuKit/     #   View models and display logic (depends on BlueskyCore)
│       └── PlatformApple/      #   Apple-only impls (Keychain / os logger, #if os(macOS))
├── apps/
│   ├── macos/                  # macOS app (SwiftUI): Auth / Workspace / Compose / Views / Timeline ...
│   └── windows/                # Windows app (WinUI 3 / C# / .NET 10)
│       ├── Core/               #   C# port of the core (XRPC, display logic, OAuth, DPAPI accounts)
│       ├── Interop/            #   client interfaces + DTOs the views consume, mapped from Core
│       ├── App/                #   WinUI 3: MVVM + XAML
│       └── Core.Tests/, Interop.Tests/  # xUnit
├── tools/wiki/                 # SPM CLI that lints and rebuilds the docs/wiki index
├── docs/
│   ├── client-metadata.json    #   OAuth client metadata (public)
│   ├── adr/                    #   Decision records: why something was chosen
│   └── wiki/                   #   LLM-wiki: derived, git-versioned knowledge layer
├── design/app-icon/            # App icon sources (SVG / generation script)
└── design/icons/               # UI icons (Lucide SVGs with Lucide's license; `mise run icons:lint`)
```

> The Windows app has its own C# core (`apps/windows/Core`) and does not use the Swift package; the two cores are kept in step through the wiki and ADRs, not shared code (`docs/adr/0027-windows-csharp-core.md`). For the architecture and the build steps, see `docs/wiki/platforms/windows.md` and `apps/windows/README.md`.

### Module Split

- `BlueskyCore` (SPM library): networking, OAuth, XRPC, token refresh, with no direct Apple-framework dependencies.
- `YoruMimizukuKit` (SPM library): view models and display logic. Depends on `BlueskyCore`.
- `PlatformApple` (SPM library): Apple-framework concrete implementations of the core ports (Keychain, logger), gated `#if os(macOS)`.
- `apps/macos` (macOS app target): SwiftUI views and the wiring of Apple-specific pieces such as ASWebAuthenticationSession.
- `apps/windows` (WinUI 3 / C# / .NET 10 app): a C# core (`Core`), the DTO layer the views consume (`Interop`), and the WinUI app (`App`); OAuth runs in WebView2 and accounts are stored with DPAPI.

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
# Test the core package on macOS (fast — run this most of the time). Uses Xcode's
# toolchain (the Command Line Tools have no XCTest) and leaves core/Package.resolved
# as committed. If it stops because a dependency changed, update Package.resolved
# with the dependency change; do not drop the flag. (The Windows app's C# core is
# tested separately, with scripts/windows/test.ps1.)
mise run test:core

# Build including the app
xcodebuild build -scheme YoruMimizuku -project YoruMimizuku.xcodeproj

# Test including the app
xcodebuild test -scheme YoruMimizuku -project YoruMimizuku.xcodeproj -destination 'platform=macOS'
```

Test targets: `BlueskyCoreTests` and `YoruMimizukuKitTests` (both under `core/Tests/`).

## Workflow

- **Always use `/git-worktree-workflow` when starting new work (feature, bugfix, experiment).** Create a worktree with `git wt feature/xxx`; do not commit directly on the main branch.
- Write commit messages in English. Do not use Conventional Commits; capitalize the first letter.
- Develop with TDD (Red → Green → Refactor). Do not write many tests at once; advance one step at a time.
- **After merging into `main`, always run `xcodegen generate`.** `YoruMimizuku.xcodeproj` and the `Info.plist`s are generated, gitignored artifacts; a merge that adds or removes sources or changes `project.yml` leaves the local project stale, so regenerate it before building, testing, or releasing from `main`.
- **After merging a feature branch into `main`, delete its now-unneeded worktree.** Run `git wt remove <path>` (or `git worktree remove <path>`) for the merged worktree so stale worktrees do not accumulate. Do this as part of the same merge step.

## Coding Conventions

- Swift 6.0 / strict concurrency. Be mindful of `MainActor` isolation and `Sendable`.
- Abstract side effects (networking, Keychain, browser launch) behind protocols, and inject fakes in tests. Keep the `BlueskyCore` core logic free of direct Apple-framework dependencies.
- The reference implementation is the same author's Ruby terminal client `tempest` (`/Users/asonas/ghq/github.com/asonas/tempest`), whose proven logic serves as the blueprint. This is a high-quality Swift reimplementation, not a port.
- Layout spacing/radius values shared across platforms live in `DesignMetrics` (`core/Sources/YoruMimizukuKit/DesignMetrics.swift`); see `docs/wiki/design-system.md` for the vocabulary and the design catalog.
