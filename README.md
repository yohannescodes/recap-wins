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

**Phase 1 — the semantic layer** (done). Model-backed commands that turn the
change report into prose via the Anthropic API: `rw new` (list new features) and
`rw notes` for every target (`--pr`, `--asc-reviewer`, `--what-new`,
`--asc-update`, `--gp-update`), in the product's voice, within store char caps.
Caps come from a TTL-cached `limits.json` manifest with a baked-in offline
fallback; `--refresh-limits` forces a fetch and `--limit` only tightens.

**Provider switching** (from Phase 3, pulled forward). The prose commands run
through a pluggable provider — `anthropic` (API), `skill` (key-free, emits JSON
for a host agent), or `gemini` (reserved). Pick with `--provider` or the
`provider` config key. Skill mode is the no-key path. `market` is Phase 2.

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
| `rw notes <target>` | Write a review/release note for a target (PR, App Review, TestFlight/Play, store update) | semantic |
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

### Semantic commands (`new`, `notes`)

These turn the change report into prose. They run through a **provider**, chosen
by `provider` in `testthese.toml` or the `--provider` flag (flag wins):

| Provider | Needs a key? | What it does |
|---|---|---|
| `anthropic` *(default)* | yes | Calls the Anthropic API directly and prints the prose |
| `skill` | **no** | Emits a JSON envelope for a host agent (Claude Code, Cowork) to complete — the host agent is the model |
| `gemini` | — | Reserved; not yet implemented |

**Skill mode — no API key, no network.** `rw` does the deterministic work and
hands the agent a prompt + the grounded change report to write the prose. If you
already pay for Claude through a plan, this routes the model work through your
agent session at no extra cost:

```sh
rw new   --provider skill            # emits a JSON envelope for the host agent
rw notes --asc-update --product ledgerly --provider skill
```

**API mode.** Provide a key via the `ANTHROPIC_API_KEY` environment variable
(preferred) or `api_key` in `testthese.toml` — the env var wins.

```sh
export ANTHROPIC_API_KEY=sk-ant-...
rw new --base main
rw notes --pr                              # technical PR description, uncapped
rw notes --asc-update --product ledgerly   # App Store "What's New", in voice, ≤4000
rw notes --gp-update  --product ledgerly --limit 300   # tighter Play note
```

Copy [`testthese.toml.example`](testthese.toml.example) to `testthese.toml` to
configure the base ref, model, provider, and product profiles.

`rw notes` takes exactly one target. The user-facing store targets
(`--asc-update`, `--gp-update`, `--what-new`) pull voice and a soft length aim
from the product profile, so pass `--product <id>`. Char caps are hard ceilings:
the tool **warns** if output overflows, it never silently truncates, and
`--limit` only tightens (never loosens past the store ceiling).

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
- **`SemanticKit`** — the semantic layer. Consumes a `ChangeReport` and renders
  prose through a pluggable **provider**: `anthropic` (hand-rolled `URLSession`,
  zero deps), `skill` (emits a JSON envelope for a host agent — no key, no
  network), or `gemini` (reserved). Depends on `RecapCore`, never the reverse —
  the core stays offline. The API call sits behind a `ModelClient` protocol so
  tests inject a mock and CI needs no key.
- **`rw`** — the command-line front end over `RecapCore` + `SemanticKit`.

## Development

```sh
swift build
swift test
```
