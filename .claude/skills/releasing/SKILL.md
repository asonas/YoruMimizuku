---
name: releasing
description: Use when releasing a YoruMimizuku version (dev prerelease or stable), bumping the version, tagging a release, publishing to GitHub Releases, updating the Sparkle appcast, or when the in-app update check does not find a version that was supposedly released.
---

# releasing

A release has four moving parts that must stay in sync: the version in `project.yml`, a git tag on **both remotes** (`origin` = Tangled, `github`), a GitHub Release carrying the Sparkle ZIP, and the appcast served by GitHub Pages from `gh-pages`. The mise tasks build artifacts; the git/verify steps below are manual and are where past releases went wrong.

## Dev-channel procedure

1. On a clean, pushed `main`: `mise run bump 1.0.0-dev.N`, then commit `project.yml` with the `commit` skill (`git ai-commit`).
2. Tag and push **before** publishing, to both remotes:
   ```bash
   git tag v1.0.0-dev.N
   git push origin main v1.0.0-dev.N
   git push github main v1.0.0-dev.N
   ```
   If the tag is not on `github` first, `gh release create` invents one from the remote default-branch HEAD, which may not be the commit you built.
3. `mise run release:dev` — builds, notarizes, produces `build/YoruMimizuku-<v>.zip` and `build/appcast-dev.xml`.
4. Write `build/release-notes-<v>.md` (see `git log v<prev>..HEAD --oneline`); `publish:dev` fails without it.
5. `mise run publish:dev` — creates the GitHub prerelease with the ZIP.
6. Publish the appcast from a temporary worktree (gh-pages exists only on `github`, not Tangled):
   ```bash
   git worktree add ../YoruMimizuku-gh-pages gh-pages
   cp build/appcast-dev.xml ../YoruMimizuku-gh-pages/appcast-dev.xml
   ```
   Commit with the `commit` skill (`git ai-commit`, never raw `git commit`), message
   `Update development appcast to v<v>`; then push to `github` and remove the worktree.

## Verify the release actually reached users

Curling the appcast and waiting is not verification: if the Pages build errored, the served file stays stale forever (this happened with v1.0.0-dev.13).

```bash
ghro api repos/asonas/YoruMimizuku/pages/builds/latest --jq '{status, error: .error.message}'
# status must be "built". If "errored", request a rebuild and re-check:
gh api -X POST repos/asonas/YoruMimizuku/pages/builds
curl -fsSL https://asonas.github.io/YoruMimizuku/appcast-dev.xml | grep shortVersionString
```

Finally confirm in the app: 設定 → アップデート → channel 開発版 → 今すぐ確認 shows the new version.

## Stable channel

Same shape: `mise run release` (stable artifacts + `appcast.xml`), `mise run publish:stable`, copy `appcast.xml` to gh-pages, same verification against `appcast.xml`.

## Common mistakes

| Mistake | Reality |
|---|---|
| Checking tags with `git tag \| tail` | Lexical sort puts `dev.10` before `dev.4`. Use `git tag --list 'v*' --sort=version:refname`, and `ls-remote` needs `sort -V`. |
| Skipping step 2 because "gh creates the tag" | It creates it on GitHub only, from remote HEAD; Tangled and your local clone end up without it. |
| Polling the appcast URL to "wait for Pages" | Check the build status API instead; an errored build never propagates. |
| Verifying with the wrong channel | The release feed is `appcast.xml`, dev is `appcast-dev.xml`; the app only sees the channel selected in settings. |
