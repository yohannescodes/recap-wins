# recap-wins

> See what your branch introduced — offline, instant, and trustworthy.

`recap-wins` (binary: `rw`) is a local, terminal-first tool that reads the diff
between your current branch and a base ref, reassembles what actually changed,
and renders it into the artifacts you need to ship. It's the *inbound*
counterpart to a public changelog: it runs **before or at** merge and writes for
*you, the shipper*.

It's language-agnostic — it operates on `git`, not on any one language — so it
works identically across every repo.

See [`docs/recap-wins-PRD.md`](docs/recap-wins-PRD.md) for the full product spec.

## Status

**Phase 0 — the deterministic core.** Offline, no LLM, no network. This is the
trustworthy foundation: everything countable and verifiable. The semantic layer
(`new`, `notes`, `market`) lands in later phases.

## Install

Requires Swift 6 and a recent macOS.

```sh
swift build -c release
# the binary is at .build/release/rw
```

## Commands

All commands operate on a **change set**: the diff between a head ref (default:
current branch) and a base ref (default: `main`).

| Command | What it does |
|---|---|
| `rw` *(default)* | The **vitals** dashboard — a one-screen health read of the change set |
| `rw many` | Count features / fixes / chores introduced (conventional-commit parse) |
| `rw blame` | Attribute who changed what across the change set |
| `rw branch` | Show which branches contributed commits to this change set |

Shared flags: `--base <ref>`, `--head <ref>`, `--repo <path>`, and `--json`
(emit the raw `change_report.json` instead of the formatted view).

```sh
rw --base main             # vitals for the current branch vs main
rw many --base develop     # feature/fix/chore counts vs develop
rw --json > report.json    # the structured change report
```

## What the vitals show (PRD §7)

- Features / fixes / chores introduced
- Files changed, insertions / deletions
- Contributors and branches involved
- **Hotspots** — the few files with the largest churn
- **Risk flags** (advisory) — large diff, core/shared files touched, source
  changed with no tests alongside. A nudge, never a gate.

## Architecture

Two cleanly separated layers (PRD §5):

- **`RecapCore`** — the deterministic library. Shells out to system `git`,
  classifies commits, and builds the `change_report.json`. No model, no network.
  This same core will back the standalone CLI *and* (Phase 3) a universal agent
  skill.
- **`rw`** — the command-line front end over `RecapCore`.

## Development

```sh
swift build
swift test
```
