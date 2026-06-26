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

| Area | State |
|---|---|
| **Deterministic core** — `change_report.json`, `vitals`, `many`, `blame`, `branch` (offline) | ✅ done |
| **Semantic commands** — `new`, `notes` (all five targets) with product voice + store caps | ✅ done |
| **Provider switching** — `anthropic` (API) and `skill` (key-free) backends | ✅ done |
| **Agent-skill packaging** — `SKILL.md` + runner, droppable into any skill-aware agent | ✅ done |
| **Marketing** — `market` content pack in a product's voice | ✅ done |
| **Gemini provider** — second API backend | 🔜 next |
| **Localization, multi-repo** — per-locale store copy; `--all-repos` digest | ⏳ later |

The deterministic core is fully offline and needs no key. The semantic commands
turn the change report into prose either by calling an API (`anthropic`) or by
emitting JSON for a host agent to complete (`skill` — no key, no network). See
[What's coming next](#whats-coming-next) for the roadmap.

## Install

Requires Swift 6 and a recent macOS.

```sh
git clone https://github.com/yohannescodes/recap-wins.git
cd recap-wins
swift build -c release
# the binary is at .build/release/rw — symlink or alias it to `rw`:
ln -s "$PWD/.build/release/rw" /usr/local/bin/rw
```

## Commands

All commands operate on a **change set**: the diff between a head ref (default:
current branch) and a base ref (default: `main`).

| Command | What it does | Mode |
|---|---|---|
| `rw` *(default)* | The **vitals** dashboard — a one-screen health read of the change set | offline |
| `rw new` | List the new *features* you introduced, filtering out chores/refactors | semantic |
| `rw notes <target>` | Write a review/release note for a target (PR, App Review, TestFlight/Play, store update) | semantic |
| `rw market --product <id>` | Generate a marketing content pack (What's New, promo text, subtitle, post, tweet…) in the product's voice | semantic |
| `rw many` | Count features / fixes / chores introduced (conventional-commit parse) | offline |
| `rw blame` | Attribute who changed what across the change set | offline |
| `rw branch` | Show which branches contributed commits to this change set | offline |
| `rw help [topic]` | The built-in guide — `concepts`, `notes`, `providers`, `skill`, `config` | — |

Shared flags: `--base <ref>`, `--head <ref>`, `--repo <path>`, and `--json`
(emit the raw `change_report.json` instead of the formatted view).

New to `rw`? Run **`rw help`** for the in-terminal guide, or read the full
[**User Guide**](docs/GUIDE.md).

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
rw market --product ledgerly               # a full marketing pack in the product's voice
rw market --product ledgerly --pieces tweet,post   # just the social pieces
```

`rw market` produces a **pack** of marketing pieces for the new features —
What's New, App Store promotional text / subtitle, Google Play short description,
a social post, and a tweet — each in the product's voice and within its store
metadata cap (warns on overflow, never truncates). It's distinct from
`rw notes --asc-update`, which emits the store-native release-note block; `market`
is the broader announcement set. Pick specific pieces with `--pieces`.

Copy [`testthese.toml.example`](testthese.toml.example) to `testthese.toml` to
configure the base ref, model, provider, and product profiles.

`rw notes` takes exactly one target. The user-facing store targets
(`--asc-update`, `--gp-update`, `--what-new`) pull voice and a soft length aim
from the product profile, so pass `--product <id>`. Char caps are hard ceilings:
the tool **warns** if output overflows, it never silently truncates, and
`--limit` only tightens (never loosens past the store ceiling).

The deterministic commands (and `--json` on any command) never need a key and
never touch the network.

## Agent skill (no API key)

`rw` ships as a drop-in **agent skill** ([`skill/`](skill/)): a `SKILL.md` plus a
runner script. Inside a skill-aware agent (Claude Code, Cowork), the agent runs
`rw` for the structured JSON and then writes the prose itself — so the model work
goes through your agent session, with **no API key and no per-call cost**.

```sh
# Install into Claude Code's skills directory
mkdir -p ~/.claude/skills/recap-wins
cp -R skill/ ~/.claude/skills/recap-wins/
```

Then just ask your agent things like *"what did I ship on this branch?"* or
*"write the App Store release notes for this update"* — it invokes the skill,
reads the change report, and writes the answer. The runner finds `rw` on your
PATH (or builds it); set `RW_BIN` to point at a specific binary.

This is the same engine as the CLI — the deterministic core produces the report,
and in skill mode the host agent is the model. See [`skill/SKILL.md`](skill/SKILL.md).

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
  This same core backs the standalone CLI *and* (via skill mode) a host agent.
- **`SemanticKit`** — the semantic layer. Consumes a `ChangeReport` and renders
  prose through a pluggable **provider**: `anthropic` (hand-rolled `URLSession`,
  zero deps), `skill` (emits a JSON envelope for a host agent — no key, no
  network), or `gemini` (reserved). Depends on `RecapCore`, never the reverse —
  the core stays offline. The API call sits behind a `ModelClient` protocol so
  tests inject a mock and CI needs no key.
- **`rw`** — the command-line front end over `RecapCore` + `SemanticKit`.

## What's coming next

Roadmap, in order (full detail in the [PRD](docs/recap-wins-PRD.md) §11):

1. **Gemini provider** — a second API backend behind the existing provider seam,
   so you can switch models/providers from config.
2. **Localization** — per-locale variants of the user-facing outputs, with
   per-language store caps re-checked (translations routinely overflow a limit
   the English version cleared).
3. **Multi-repo** — an `--all-repos` digest ("what did I touch across every repo
   this week"). Held back as the paid open-core layer.

## Development

```sh
swift build
swift test
```
