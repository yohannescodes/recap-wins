#!/usr/bin/env bash
# Render a release-page changelog through the live HTMLRender, producing
# docs/changelogs/v<version>.html — AND prepend a matching section to the
# root CHANGELOG.md so the cumulative index stays in lockstep with the
# per-release HTML pages. One prose input, two artifacts, one source of
# truth.
#
# Usage:
#   scripts/render-changelog.sh <version> < changelog.md
#   echo "## Added\n- thing." | scripts/render-changelog.sh 0.2.0
#
# Pre-flight: scripts/release.sh <version> usually runs first to bump the
# version and tag the release. Both outputs go into PR 1 of the release
# (alongside the version bump), so the tag and its release artifacts land
# together. See RELEASING.md.

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

out_html="docs/changelogs/${version}.html"
out_md="CHANGELOG.md"
mkdir -p "$(dirname "$out_html")"

# Pipe stdin to a temp file so both the Swift test and the markdown step
# can read it without re-prompting.
prose_file="$(mktemp -t rw-changelog)"
trap 'rm -f "$prose_file"' EXIT
cat > "$prose_file"

# --- 1. Render the HTML page through the live renderer. ---
# Drives the same code path the binary uses for `rw notes --changelog`,
# with the prose substituted for the model call. The test reads
# RW_CHANGELOG_OUT, RW_CHANGELOG_PROSE_FILE, and RW_CHANGELOG_VERSION;
# it's a no-op when those aren't set.
RW_CHANGELOG_OUT="$repo_root/$out_html" \
RW_CHANGELOG_PROSE_FILE="$prose_file" \
RW_CHANGELOG_VERSION="$version" \
  swift test --filter "ChangelogTargetTests" >/dev/null

echo "Wrote $out_html" >&2

# --- 2. Prepend a new section to CHANGELOG.md. ---
# The model's prose uses "## Added / ## Changed / ## Fixed". For the
# cumulative markdown index we want each version to live under its own
# anchor heading, with those bumped one level down to "### Added" etc.
# We also link the version header to the rendered HTML page.

if [[ ! -f "$out_md" ]]; then
  echo "warning: $out_md not found; skipping markdown prepend." >&2
  echo "(create $out_md first — see the existing one for the expected shape.)" >&2
  exit 0
fi

# Skip the markdown prepend if this version is already in CHANGELOG.md.
# Idempotent: re-running the script on the same version regenerates the
# HTML but doesn't double up the markdown entry.
if grep -qE "^## \[?${version}\]?" "$out_md"; then
  echo "note: $version already in $out_md; HTML re-rendered, markdown left alone." >&2
  exit 0
fi

today="$(date +%Y-%m-%d)"
new_section="$(mktemp -t rw-changelog-section)"
trap 'rm -f "$prose_file" "$new_section"' EXIT
{
  echo "## [${version}](docs/changelogs/${version}.html) — ${today}"
  echo
  # Demote "## " → "### " so the version header stays the section root.
  sed 's/^## /### /' "$prose_file"
  echo
  echo "---"
  echo
} > "$new_section"

# Insert the new section immediately after the "---\n\n" that follows the
# CHANGELOG.md header preamble. That separator is the marker for "first
# version starts here" and stays stable across releases.
awk -v section_file="$new_section" '
  BEGIN { inserted = 0 }
  # Match the first "---" after we have seen "# Changelog".
  /^---$/ && !inserted && seen_header {
    print
    print ""
    while ((getline line < section_file) > 0) print line
    close(section_file)
    inserted = 1
    next
  }
  /^# Changelog/ { seen_header = 1 }
  { print }
' "$out_md" > "${out_md}.tmp" && mv "${out_md}.tmp" "$out_md"

# Collapse the doubled blank line we created at the join point.
awk 'NR==1 || !(prev=="" && $0=="") { print } { prev = $0 }' "$out_md" > "${out_md}.tmp" \
  && mv "${out_md}.tmp" "$out_md"

echo "Prepended $version section to $out_md" >&2
