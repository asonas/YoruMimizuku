#!/usr/bin/env bash
# Sets MARKETING_VERSION in project.yml to the given x.y.z, increments the build
# number (CURRENT_PROJECT_VERSION), and regenerates the Xcode project so the new
# version takes effect. Run via `mise run bump <x.y.z>`.
set -euo pipefail

version="${1:-}"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: mise run bump <x.y.z>  (got: '${version}')" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

current_build="$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' project.yml)"
if [[ -z "$current_build" ]]; then
  echo "Could not find CURRENT_PROJECT_VERSION in project.yml" >&2
  exit 1
fi
next_build="$((current_build + 1))"

sed -i '' \
  -e "s/\(MARKETING_VERSION: \)\"[^\"]*\"/\1\"${version}\"/" \
  -e "s/\(CURRENT_PROJECT_VERSION: \)\"[0-9]*\"/\1\"${next_build}\"/" \
  project.yml

xcodegen generate >/dev/null

echo "Bumped to ${version} (build ${next_build})."
echo "Next: commit project.yml, then 'git tag v${version} && git push origin v${version}'."
