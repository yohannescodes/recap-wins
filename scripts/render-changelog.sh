#!/usr/bin/env bash
# Render a release-page changelog through the live HTMLRender, producing
# docs/changelogs/v<version>.html. Used in skill mode: you (or your agent)
# author the markdown prose; this script wraps it in the canonical HTML page.
#
# Usage:
#   scripts/render-changelog.sh <version> < changelog.md
#   echo "## Added\n- thing." | scripts/render-changelog.sh 0.2.0
#
# Pre-flight: scripts/release.sh <version> usually runs first to bump the
# version and tag the release. The HTML goes into the PR alongside the
# version bump, or into a follow-up PR before the formula bump.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/render-changelog.sh <version>   (e.g. 0.2.0)" >&2
  echo "       reads markdown prose from stdin." >&2
  exit 2
fi

version="$1"
[[ "$version" =~ ^v ]] || version="v${version}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

out="docs/changelogs/${version}.html"
mkdir -p "$(dirname "$out")"

# Pipe stdin to a temp file so the Swift test can read it via env.
prose_file="$(mktemp -t rw-changelog)"
trap 'rm -f "$prose_file"' EXIT
cat > "$prose_file"

# Drive the renderer through the test harness — same code path the binary
# uses for `rw notes --changelog`, with the prose substituted for the model
# call. The test reads RW_CHANGELOG_OUT, RW_CHANGELOG_PROSE_FILE, and
# RW_CHANGELOG_VERSION; it's a no-op when those aren't set.
RW_CHANGELOG_OUT="$repo_root/$out" \
RW_CHANGELOG_PROSE_FILE="$prose_file" \
RW_CHANGELOG_VERSION="$version" \
  swift test --filter "ChangelogTargetTests" >/dev/null

echo "Wrote $out" >&2
