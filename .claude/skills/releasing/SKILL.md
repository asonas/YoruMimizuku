---
name: releasing
description: Use when releasing a YoruMimizuku version (dev prerelease or stable), bumping the version, tagging a release, publishing to GitHub Releases, updating the Sparkle appcast, or when the in-app update check does not find a version that was supposedly released.
---

# releasing

A macOS release has four parts that must stay in sync: the version in `project.yml`, a signed tag `v<version>` on `origin` (GitHub, the only remote), a GitHub Release carrying the Sparkle ZIP, and the appcasts served by GitHub Pages from the `gh-pages` branch: `appcast.xml` for the リリース channel and `appcast-dev.xml` for the 開発版 channel. The mise tasks in `mise.toml` build and publish the artifacts; committing, tagging, the appcast push and the verification are done by hand.

## Procedure

1. Bump the version on a worktree branch off an up-to-date `main`, not on `main` itself: `mise run bump <version>` sets the macOS `MARKETING_VERSION`, increments the build number, and leaves the iPadOS version alone. Commit `project.yml` as `Release macOS <version>` (signed, following the user's commit rules), fast-forward `main` to it, and push `main` once the user has approved the release.
2. On that commit, create a signed annotated tag `v<version>` with the message `YoruMimizuku <version>` and push it to `origin` before publishing. Without the tag on GitHub, the release step creates one from the remote default branch, which may not be the commit that was built.
3. Build from a checkout whose `HEAD` is the tagged commit and which has no uncommitted changes, since the archive takes the working tree as it is: `mise run release:dev` for a dev version (`x.y.z-dev.N`), `mise run release:stable` for a stable one. They archive, export, notarize (several minutes), and write `build/YoruMimizuku-<version>.zip` plus `build/appcast-dev.xml` or `build/appcast.xml`; the stable build also makes the DMG.
4. Write `build/release-notes-<version>.md`; the publish tasks fail without it. Write it in Japanese for users of the app, in the style of the previous release's notes (readable from that GitHub Release), from the log since the previous release of the same kind: the previous dev or stable tag for a dev release, the previous stable tag for a stable one, so a stable release covers everything its dev releases brought.
5. `mise run publish:dev` (a prerelease with the ZIP) or `mise run publish:stable` (a release with the ZIP and DMG).
6. Update `gh-pages` from a temporary worktree of it, commit (signed), push to `origin`, and remove the worktree.
   - Dev: put `build/appcast-dev.xml` at the root as `appcast-dev.xml`, commit as `Update development appcast to v<version>`.
   - Stable: put `build/appcast.xml` at the root as `appcast.xml`, and also as `appcast-dev.xml` when its `sparkle:version` (the build number, compared as an integer) is higher than that of `appcast-dev.xml` on the latest `origin/gh-pages`, so 開発版 users get the stable release too. Commit as `Publish <version> update feeds`.

## Verify the release reached users

Polling the served appcast is not verification: if the Pages build errored, the served file stays stale. Check the latest Pages build through the GitHub API (`repos/asonas/YoruMimizuku/pages/builds/latest`): its status must be `built` for the `gh-pages` commit just pushed. If it `errored`, request a rebuild (POST to `.../pages/builds`) and check again. Then confirm that every appcast you changed, under `https://asonas.github.io/YoruMimizuku/`, serves the new `shortVersionString`.

Finally ask the user to check in an older build of the app: 設定 → アップデート, select the channel the release went to (リリース or 開発版), then 今すぐ確認 should offer the new version.

## Gotchas

| Situation | What to know |
|---|---|
| Finding the previous tag | Lexical sort puts `dev.10` before `dev.4`, and version sort puts `v1.0.0` before `v1.0.0-dev.1`. Pick the previous dev or stable tag by reading the versions, not by taking the last line of a sorted list. |
| `generate_appcast` not found | `SPARKLE_BIN` points into `$BUILD_DIR/SourcePackages`, which the `archive` task fills by cloning the app's Swift packages there, so the tool matches the Sparkle in the app. Homebrew's `sparkle` cask is disabled and must not be used. |
| `xcodebuild requires Xcode` | The tasks that call `xcodebuild`, `notarytool` or `stapler` set `DEVELOPER_DIR` to `/Applications/Xcode.app`; if they still fail, check that Xcode is installed there. |
| Redoing only the ZIP or the appcast | `sparkle-zip` and the `appcast:*` tasks depend on `notarize-app`, so running them reruns the archive and notarization. To redo only the last step, run that task's commands directly. The appcast carries the ZIP's EdDSA signature and length, so after remaking the ZIP, regenerate the appcast from the ZIP that will be published; otherwise the update is offered but fails to install. |
