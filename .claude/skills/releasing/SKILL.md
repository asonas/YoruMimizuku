---
name: releasing
description: Use when releasing a YoruMimizuku version (dev prerelease or stable), bumping the version, tagging a release, publishing to GitHub Releases, updating the Sparkle appcast, or when the in-app update check does not find a version that was supposedly released.
---

# releasing

A macOS release has four parts that must stay in sync: the version in `project.yml`, a signed tag `v<version>` on `origin` (GitHub, the only remote), a GitHub Release carrying the Sparkle ZIP, and the appcast served by GitHub Pages from the `gh-pages` branch. The mise tasks in `mise.toml` build and publish the artifacts; committing, tagging, the appcast push and the verification are done by hand.

## Dev-channel procedure

1. On a clean `main` that matches `origin/main`, run `mise run bump <x.y.z-dev.N>`. It sets the macOS `MARKETING_VERSION`, increments the build number, and leaves the iPadOS version alone. Commit `project.yml` on `main` as `Release macOS <version>`, and create an annotated tag `v<version>` with the message `YoruMimizuku <version>`. Both are signed, following the user's commit rules.
2. Push `main` and the tag before publishing. Without the tag on GitHub, the release step creates one from the remote default branch, which may not be the commit that was built.
3. `mise run release:dev` archives, exports, notarizes (several minutes), and writes `build/YoruMimizuku-<version>.zip` and `build/appcast-dev.xml`.
4. Write `build/release-notes-<version>.md`; `publish:dev` fails without it. Write it in Japanese for users of the app, in the style of the previous release's notes (readable from that GitHub Release), from `git log v<previous>..v<version>`.
5. `mise run publish:dev` creates the GitHub prerelease with the ZIP.
6. Put `build/appcast-dev.xml` at the root of `gh-pages` as `appcast-dev.xml`, using a temporary worktree of `gh-pages`. Commit it as `Update development appcast to v<version>` (signed), push `gh-pages` to `origin`, and remove the worktree.

## Verify the release reached users

Polling the served appcast is not verification: if the Pages build errored, the served file stays stale. Check the latest Pages build through the GitHub API (`repos/asonas/YoruMimizuku/pages/builds/latest`): its status must be `built` for the `gh-pages` commit just pushed. If it `errored`, request a rebuild (POST to `.../pages/builds`) and check again. Then confirm that `https://asonas.github.io/YoruMimizuku/appcast-dev.xml` (or `appcast.xml`) serves the new `shortVersionString`.

Finally the user confirms in the app: 設定 → アップデート → channel 開発版 → 今すぐ確認 shows the new version. Running that check on the user's machine installs over the app they use, so leave it to them.

## Stable channel

Same shape: `mise run release:stable` (writes `build/appcast.xml`), `mise run publish:stable`, put `appcast.xml` on `gh-pages`, and verify against `appcast.xml`.

## Gotchas

| Situation | What to know |
|---|---|
| Finding the latest tag | Lexical sort puts `dev.10` before `dev.4`. Sort tags by version (`git tag --sort=version:refname`). |
| `generate_appcast` not found | `SPARKLE_BIN` points at `build/SourcePackages`, which the `archive` task fills by cloning the app's Swift packages there, so the tool matches the Sparkle in the app. Homebrew's `sparkle` cask is disabled and must not be used. |
| `xcodebuild requires Xcode` | `mise.toml` sets `DEVELOPER_DIR` for all tasks; if it still fails, check that Xcode is installed at that path. |
| Redoing only the ZIP or the appcast | `sparkle-zip` and the `appcast:*` tasks depend on `notarize-app`, so running them reruns the archive and notarization. To redo only the last step, run that task's commands directly. |
| Verifying with the wrong channel | The stable feed is `appcast.xml` and the dev feed is `appcast-dev.xml`; the app reads only the channel selected in settings. |
