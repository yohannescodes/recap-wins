# Contributing to recap-wins

This is a small project run by [@yohannescodes](https://github.com/yohannescodes).
PRs welcome for bugs, doc fixes, and small features. For anything larger —
new commands, new providers, structural changes — please **open an issue
first** so we can talk shape before you write code.

## Quick start

```sh
git clone https://github.com/yohannescodes/recap-wins.git
cd recap-wins
swift build
swift test
```

Requires Swift 6 and a recent macOS. The binary lands at `.build/debug/rw`.

## What's in scope

- `rw` itself: the CLI commands, the deterministic core (`RecapCore`), and
  the semantic layer (`SemanticKit`).
- The skill version (`skill/`) — the same engine, packaged as an agent skill.
- The docs at the repo root: [README.md](README.md), [GUIDE.md](GUIDE.md),
  [RELEASING.md](RELEASING.md), and this file.

## What's not in scope

- **Cross-repo aggregation** (`--all-repos` and the multi-repo digest). That's
  the paid open-core layer (see PRD §11 / §12 in the project docs). Issues and
  PRs are welcome on the **single-repo** tool here; the multi-repo work is
  intentionally held back from the open core.

## House rules

- **Conventional commits.** Subjects use `feat:`, `fix:`, `chore:`, `docs:`,
  `refactor:`, `test:`, etc. The whole codebase reads its own commit history
  through this — non-conventional commits still get inferred buckets, but
  declared types are the authoritative signal.
- **Sync docs with code.** If your PR changes behavior, update
  [README.md](README.md) and [GUIDE.md](GUIDE.md) in the same PR. Doc
  updates are not a follow-up.
- **Tests.** New commands and new flags need tests under
  [`Tests/`](Tests). The semantic layer tests against a mock model client so
  CI needs no API key.
- **The deterministic core stays offline.** `RecapCore` must not depend on
  `SemanticKit`, must not call a model, and must not touch the network. This
  is what lets the "what changed" half stay free and instant.
- **No `--no-verify`.** If a hook fails, fix the cause rather than skip it.

## Filing issues

Bugs: include the command you ran, what you expected, what you got, and
`rw --version` output. If the report involves a specific change set, the
output of `rw --json` is the most useful single attachment — it's the full
report `rw` saw, deterministic and verifiable.

Feature ideas: a short description of the user-facing problem usually beats a
long description of the solution. The PRD lives outside this repo, but the
shape of the project (free single-repo tool, paid cross-repo digest) is set —
work that fits that shape is easiest to land.

## Releases

Maintainers: [RELEASING.md](RELEASING.md) walks through the two-PR release
flow and the `scripts/release.sh` helper.
