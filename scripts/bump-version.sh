#!/usr/bin/env bash
# Sets MARKETING_VERSION in project.yml to the given x.y.z, increments the build
# number (CURRENT_PROJECT_VERSION), and regenerates the Xcode project so the new
# version takes effect. Run via `mise run bump <x.y.z>`.
set -euo pipefail

version="${1:-}"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "Usage: mise run bump <x.y.z[-pre.N]>  (got: '${version}')" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

# Only the first MARKETING_VERSION / CURRENT_PROJECT_VERSION pair in project.yml
# belongs to the macOS release target; the iPadOS target below it is versioned
# independently and must not be touched.
current_build="$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' project.yml | head -1)"
if [[ -z "$current_build" ]]; then
  echo "Could not find CURRENT_PROJECT_VERSION in project.yml" >&2
  exit 1
fi
next_build="$((current_build + 1))"

awk -v ver="$version" -v build="$next_build" '
  !mv && /MARKETING_VERSION: "/ { sub(/MARKETING_VERSION: "[^"]*"/, "MARKETING_VERSION: \"" ver "\""); mv = 1 }
  !bv && /CURRENT_PROJECT_VERSION: "/ { sub(/CURRENT_PROJECT_VERSION: "[0-9]*"/, "CURRENT_PROJECT_VERSION: \"" build "\""); bv = 1 }
  { print }
' project.yml > project.yml.bump.tmp
mv project.yml.bump.tmp project.yml

xcodegen generate >/dev/null

echo "Bumped to ${version} (build ${next_build})."
echo "Next: commit project.yml, then 'git tag v${version} && git push origin v${version}'."
