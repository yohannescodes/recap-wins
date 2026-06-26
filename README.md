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

**Phase 0 — the deterministic core** (done). Offline, no LLM, no network: the
trustworthy foundation, everything countable and verifiable.

**Phase 1 — the semantic layer** (in progress). Adds model-backed commands that
turn the change report into prose via the Anthropic API: `rw new` (list new
features) and `rw notes --pr` (PR description). The core stays offline — only
these commands reach the network. Store-update targets of `notes`
(`--asc-update`, `--gp-update`, `--what-new`, `--asc-reviewer`) and the
`limits.json` cap manifest follow in the next pass; `market` is Phase 2.

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
| `rw` *(default)* | The **vitals** dashboard — a one-screen health read of the change set | offline |
| `rw new` | List the new *features* you introduced, filtering out chores/refactors | semantic |
| `rw notes --pr` | Write a PR description for the change set | semantic |
| `rw many` | Count features / fixes / chores introduced (conventional-commit parse) | offline |
| `rw blame` | Attribute who changed what across the change set | offline |
| `rw branch` | Show which branches contributed commits to this change set | offline |

Shared flags: `--base <ref>`, `--head <ref>`, `--repo <path>`, and `--json`
(emit the raw `change_report.json` instead of the formatted view).

```sh
rw --base main             # vitals for the current branch vs main
rw many --base develop     # feature/fix/chore counts vs develop
rw --json > report.json    # the structured change report
rw new                     # semantic: list the new features (needs an API key)
rw notes --pr              # semantic: a PR description
```

### Semantic commands (Phase 1)

`rw new` and `rw notes` call the Anthropic API. Provide a key via the
`ANTHROPIC_API_KEY` environment variable (preferred) or `api_key` in
`testthese.toml` — the env var wins. Copy [`testthese.toml.example`](testthese.toml.example)
to `testthese.toml` to configure the base ref, model, and product profiles.

```sh
export ANTHROPIC_API_KEY=sk-ant-...
rw new --base main
rw notes --pr --base main
```

The deterministic commands (and `--json` on any command) never need a key and
never touch the network.

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
- **`SemanticKit`** — the semantic layer (Phase 1). Consumes a `ChangeReport`
  and calls the Anthropic API (hand-rolled `URLSession`, zero deps) to write
  prose. Depends on `RecapCore`, never the reverse — the core stays offline. The
  model call sits behind a `ModelClient` protocol so tests inject a mock and CI
  needs no key.
- **`rw`** — the command-line front end over `RecapCore` + `SemanticKit`.

## Development

```sh
swift build
swift test
```
