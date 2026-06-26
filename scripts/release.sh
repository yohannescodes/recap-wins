#!/usr/bin/env bash
# Cut a recap-wins release and print the Homebrew formula values.
#
# Usage:
#   scripts/release.sh <version>      e.g. scripts/release.sh 0.2.0
#
# What it does:
#   1. Verifies the version matches Sources/rw/RW.swift and the tree is clean.
#   2. Tags v<version> and pushes the tag.
#   3. Computes the SHA256 of the GitHub source tarball for that tag.
#   4. Prints the `url` + `sha256` lines to paste into Formula/recap-wins.rb.
#
# After running, update Formula/recap-wins.rb with the printed values, commit,
# and push. Users then get the new version via `brew upgrade recap-wins`.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/release.sh <version>   (e.g. 0.2.0)" >&2
  exit 2
fi

version="$1"
tag="v${version}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# 1. Sanity checks.
code_version="$(grep -oE 'version: "[0-9]+\.[0-9]+\.[0-9]+"' Sources/rw/RW.swift | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
if [[ "$code_version" != "$version" ]]; then
  echo "version mismatch: RW.swift says '$code_version', you asked for '$version'." >&2
  echo "Bump the version in Sources/rw/RW.swift first." >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree is not clean; commit or stash first." >&2
  exit 1
fi
if git rev-parse "$tag" >/dev/null 2>&1; then
  echo "tag $tag already exists." >&2
  exit 1
fi

# 2. Tag and push.
echo "Tagging $tag…" >&2
git tag -a "$tag" -m "recap-wins $tag"
git push origin "$tag"

# 3. Compute the tarball SHA256.
slug="$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
url="https://github.com/${slug}/archive/refs/tags/${tag}.tar.gz"
echo "Fetching tarball to hash: $url" >&2
sha="$(curl -fsSL "$url" | shasum -a 256 | awk '{print $1}')"

# 4. Print the formula values.
cat <<EOF

Update Formula/recap-wins.rb with:

  url "${url}"
  sha256 "${sha}"

Then commit and push the formula change.
EOF
