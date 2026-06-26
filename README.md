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
| **Agent-skill packaging** — `SKILL.md` so any skill-aware agent can run the core | 🔜 next |
| **Marketing** — `market` + the five product profiles | ⏳ planned |
| **Gemini provider** — second API backend | ⏳ reserved |
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
| `rw many` | Count features / fixes / chores introduced (conventional-commit parse) | offline |
| `rw blame` | Attribute who changed what across the change set | offline |
| `rw branch` | Show which branches contributed commits to this change set | offline |

Shared flags: `--base <ref>`, `--head <ref>`, `--repo <path>`, and `--json`
(emit the raw `change_report.json` instead of the formatted view).

### Analyzing a repo (offline)

A **change set** is the diff between a **head** ref and a **base** ref, in some
**repo** — three independent knobs:

| Knob | Flag | Default | Meaning |
|---|---|---|---|
| Repo | `--repo <path>` | current directory | which git repo to read |
| Base | `--base <ref>` | `main` | what you compare *against* |
| Head | `--head <ref>` | `HEAD` (current branch) | what you compare |

So `rw many --base develop` means: *in the repo I'm in, count what my current
branch added on top of `develop`.*

The offline commands (`rw`, `many`, `blame`, `branch`, and `--json` on anything)
need **no API key and never touch the network** — they read your local git only.

```sh
# Point at a repo and compare against a base branch
cd ~/code/ledgerly
rw                                  # vitals: current branch vs main
rw many --base develop              # feature/fix/chore counts vs develop
rw branch --base develop            # which branches contributed
rw blame                            # who authored what
rw --json > report.json             # the raw change_report.json

# …or target any repo from anywhere, no `cd`
rw many --repo ~/code/ledgerly --base develop
rw      --repo ~/code/mogwar --base release/2.0 --head feature/onboarding

# base/head take ANY ref — branch, tag, or SHA
rw --base v1.2.0 --head v1.3.0      # what shipped between two tags
rw --base main   --head a1b9f3c     # main vs a specific commit
rw many --base origin/main          # vs the remote's main (local data; no fetch)
```

> `rw many` counts via conventional-commit prefixes (`feat:`, `fix:`, `chore:`…).
> Commits that don't follow that convention bucket as chores. `rw` never fetches
> for you, so `origin/*` refs reflect your last `git fetch`.

The semantic commands add prose on top of the same change set:

```sh
rw new                     # list the new features (provider: anthropic or skill)
rw notes --pr              # a PR description
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

1. **Agent-skill packaging** — a `SKILL.md` + the core binary, droppable into any
   skill-aware agent (Claude Code, Cowork). Skill *mode* already works; this is
   the packaging that lets an agent invoke it as a first-class skill.
2. **`rw market`** — a marketing content pack (App Store "What's New", short post,
   tweet) in a product's voice, plus the five Novarch product profiles.
3. **Gemini provider** — a second API backend behind the existing provider seam,
   so you can switch models/providers from config.
4. **Localization** — per-locale variants of the user-facing outputs, with
   per-language store caps re-checked (translations routinely overflow a limit
   the English version cleared).
5. **Multi-repo** — an `--all-repos` digest ("what did I touch across every repo
   this week"). Held back as the paid open-core layer.

## Development

```sh
swift build
swift test
```
