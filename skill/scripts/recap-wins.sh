#!/usr/bin/env bash
# recap-wins skill runner.
#
# Locates (or builds) the `rw` binary and runs a recap-wins command, always in
# skill mode (`--provider skill`) so the output is a JSON envelope the host agent
# completes — no API key, no network call from rw.
#
# Usage:
#   recap-wins.sh <command> [rw-args...]
#
#   command : new | notes | vitals | many | blame | branch
#
# Examples:
#   recap-wins.sh new --repo ~/code/ledgerly
#   recap-wins.sh notes --pr --repo ~/code/ledgerly
#   recap-wins.sh notes --asc-update --product ledgerly --repo ~/code/ledgerly
#   recap-wins.sh vitals --repo ~/code/ledgerly        # deterministic JSON
#
# Resolution order for the binary:
#   1. $RW_BIN if set and executable
#   2. `rw` on PATH
#   3. .build/release/rw or .build/debug/rw under the repo root
#   4. build it with `swift build -c release` (requires Swift)

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: recap-wins.sh <new|notes|vitals|many|blame|branch> [rw-args...]" >&2
  exit 2
fi

command="$1"
shift

# The skill directory is scripts/..; the package root is one level above that if
# the skill lives inside the repo, else unknown.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$script_dir/.." && pwd)"
# When the skill is bundled inside the recap-wins repo, the package root is the
# parent of the skill dir. When installed standalone, this may not be a repo.
pkg_root="$(cd "$skill_root/.." 2>/dev/null && pwd || echo "")"

find_binary() {
  # 1. Explicit override.
  if [[ -n "${RW_BIN:-}" && -x "${RW_BIN}" ]]; then
    echo "$RW_BIN"; return 0
  fi
  # 2. On PATH.
  if command -v rw >/dev/null 2>&1; then
    command -v rw; return 0
  fi
  # 3. Built binary under the package root.
  for candidate in "$pkg_root/.build/release/rw" "$pkg_root/.build/debug/rw"; do
    if [[ -x "$candidate" ]]; then echo "$candidate"; return 0; fi
  done
  return 1
}

bin="$(find_binary || true)"

# 4. Build it if we couldn't find it and we're inside the package.
if [[ -z "$bin" ]]; then
  if [[ -f "$pkg_root/Package.swift" ]] && command -v swift >/dev/null 2>&1; then
    echo "rw binary not found; building (swift build -c release)…" >&2
    ( cd "$pkg_root" && swift build -c release >&2 )
    bin="$pkg_root/.build/release/rw"
  fi
fi

if [[ -z "$bin" || ! -x "$bin" ]]; then
  cat >&2 <<EOF
Could not find or build the rw binary.
Set RW_BIN to its path, put rw on PATH, or run from inside the recap-wins repo
with Swift installed. See the recap-wins README for install steps.
EOF
  exit 1
fi

# Deterministic commands emit the change report directly (--json); semantic
# commands emit the skill envelope (--provider skill). Both are JSON the agent
# can read without an API key.
case "$command" in
  new|notes)
    exec "$bin" "$command" --provider skill "$@"
    ;;
  vitals)
    exec "$bin" --json "$@"
    ;;
  many|blame|branch)
    exec "$bin" "$command" --json "$@"
    ;;
  *)
    echo "unknown command: $command (use new|notes|vitals|many|blame|branch)" >&2
    exit 2
    ;;
esac
