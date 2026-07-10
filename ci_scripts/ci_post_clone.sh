#!/bin/sh

# Xcode Cloud post-clone hook.
#
# YoruMimizuku.xcodeproj and the per-app Info.plist files are gitignored,
# generated artifacts (see .gitignore and AGENTS.md): XcodeGen produces them from
# project.yml and they are never committed. Xcode Cloud clones only the tracked
# files, so the project does not exist yet at this point. This hook runs right
# after the clone and before Xcode Cloud resolves the scheme and builds, so
# generate the project here.

set -e

# Homebrew is preinstalled on Xcode Cloud runners.
brew install xcodegen

# Generate at the repository root. CI_PRIMARY_REPOSITORY_PATH is the checkout of
# the primary repo; this script's own working directory is ci_scripts/.
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "XcodeGen: generated YoruMimizuku.xcodeproj and Info.plists"
