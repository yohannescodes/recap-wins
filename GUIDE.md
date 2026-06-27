# recap-wins — User Guide

A complete walkthrough of `rw`: install, the mental model, every command, the
provider modes, configuration, and recipes for common tasks.

For a quick reference in the terminal, run **`rw help`** (or `rw help <topic>`).
This document is the long-form version of the same material.

---

## Contents

1. [Install](#1-install)
2. [The mental model](#2-the-mental-model)
3. [Your first run](#3-your-first-run)
4. [Commands](#4-commands)
5. [Writing prose: `new` and `notes`](#5-writing-prose-new-and-notes)
6. [HTML output](#6-html-output)
7. [Providers — who writes the prose](#7-providers--who-writes-the-prose)
8. [Skill mode — no API key](#8-skill-mode--no-api-key)
9. [Configuration](#9-configuration)
10. [Recipes](#10-recipes)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Install

### Homebrew (recommended)

The repo is its own tap — one command installs the `rw` binary:

```sh
brew tap yohannescodes/recap-wins https://github.com/yohannescodes/recap-wins
brew install recap-wins
```

Upgrade later with `brew upgrade recap-wins`. The formula builds from source, so
the first install compiles via Swift and takes a minute. Then skip to §2 — `rw`
is already on your PATH.

### From source

Requires Swift 6 and a recent macOS.

```sh
git clone https://github.com/yohannescodes/recap-wins.git
cd recap-wins
swift build -c release
```

The binary is at `.build/release/rw`. Put it on your PATH so you can run `rw`
from any repo. Pick one:

```sh
# A. symlink into a system bin (may need sudo)
sudo ln -sf "$PWD/.build/release/rw" /usr/local/bin/rw

# B. symlink into a personal bin (no sudo, if ~/bin is on PATH)
mkdir -p ~/bin && ln -sf "$PWD/.build/release/rw" ~/bin/rw

# C. a shell alias
echo "alias rw=\"$PWD/.build/release/rw\"" >> ~/.zshrc && source ~/.zshrc
```

Verify:

```sh
which rw      # → the path you linked
rw --version  # → 0.2.0
```

> All three point at `.build/release/rw` inside the repo. Rebuilding keeps them
> working; moving or deleting the repo breaks them. A Homebrew tap is a later
> nicety — for a personal tool this is enough.

---

## 2. The mental model

Every `rw` command analyzes a **change set**: the diff between a **head** ref and
a **base** ref, in a **repo**. Three independent knobs:

| Knob | Flag | Default | Meaning |
|---|---|---|---|
| Repo | `--repo <path>` | current directory | which git repo to read |
| Base | `--base <ref>` | `main` | what you compare *against* |
| Head | `--head <ref>` | `HEAD` (current branch) | what you compare |

So `rw many --base develop` means: *in the repo I'm in, count what my current
branch added on top of `develop`.*

`--base` and `--head` accept **any git ref** — a branch, tag, or SHA:

```sh
rw --base v1.2.0 --head v1.3.0   # what shipped between two tags
rw --base main   --head a1b9f3c  # main vs a specific commit
rw many --base origin/main       # vs the remote's main (uses local data)
```

**Offline and read-only.** The deterministic commands never write to the repo,
never fetch, and never call a model. `origin/*` refs reflect your last
`git fetch` — `rw` won't fetch for you.

**Classification.** Counts come first from
[conventional-commit](https://www.conventionalcommits.org) prefixes (`feat:`,
`fix:`, `chore:`, …) — the authoritative signal, never overridden. For commits
with **no** recognized prefix, `rw` *infers* a bucket from the subject verbs
(add/ship/implement → feature; fix/resolve → fix; bump/refactor/rename → chore)
and the diff (a change set that adds new source files leans feature). Inferred
counts are flagged in the output — e.g. `(2 inferred from message/diff — not
conventional commits)` — so you can always tell a declared count from a guessed
one. The parsed type is never overwritten; `--json` shows both `type` and
`inferredBucket`. For the richest read on non-conventional history, `rw new`
(semantic) reads the full diff and recovers features even more precisely.

---

## 3. Your first run

```sh
cd ~/path/to/any/repo
rw
```

You get the **vitals dashboard**: feature/fix/chore counts, files changed with
insertions/deletions, contributors, branches involved, the highest-churn files
(**hotspots**), and any advisory **risk flags** (large diff, core files touched,
source changed with no tests alongside). Risk flags are a nudge, never a gate.

Everything here is deterministic and instant — no key, no network.

```sh
rw --base develop     # compare against develop instead of main
rw --json             # the same data as raw change_report.json
```

---

## 4. Commands

| Command | What it does | Mode |
|---|---|---|
| `rw` *(default)* | vitals dashboard | offline |
| `rw many` | count features / fixes / chores + breakdown | offline |
| `rw blame` | attribution by contributor | offline |
| `rw branch` | which branches contributed | offline |
| `rw new` | list the new user-facing features | semantic |
| `rw notes <target>` | write a review/release note | semantic |
| `rw market --product <id>` | a marketing content pack in the product's voice | semantic |
| `rw help [topic]` | the built-in guide | — |

Global flags on every command: `--repo`, `--base`, `--head`, `--json` (emit the
raw `change_report.json` instead of the formatted view — works offline on any
command, including the semantic ones), and `--html` (render the same view to a
single self-contained, offline HTML file — see §6).

---

## 5. Writing prose: `new` and `notes`

These two turn the change set into text. They need a **provider** (see §7) —
either an API key, or skill mode with no key.

### `rw new`

Lists the genuinely new, user-facing features, folding out chores and refactors.

```sh
rw new
rw new --base develop --provider skill
```

### `rw notes <target>`

Writes a note for exactly **one** target. Each has its own audience, tone, and
character ceiling:

| Flag | Destination | Voice? | Cap | Output |
|---|---|---|---|---|
| `--pr` | PR description (technical) | no | none | text |
| `--asc-reviewer` | App Store Connect → App Review (private) | no | none | text |
| `--what-new` | TestFlight / Play testing notes | yes | platform | text |
| `--asc-update` | App Store "What's New" | yes | 4000 | text |
| `--gp-update` | Google Play release notes | yes | 500/lang | text |
| `--changelog` | Release-page changelog (committed artifact) | optional | none | **HTML only** |

```sh
rw notes --pr
rw notes --asc-update --product ledgerly
rw notes --gp-update  --product ledgerly --limit 300
rw notes --changelog --version-label v0.2.0 --base v0.1.1 --head HEAD
```

**`--changelog` is HTML-only.** It always renders a self-contained release
page, defaults its output under `docs/changelogs/v<version>.html`, and is the
canonical "what changed" artifact you commit per release. See [RELEASING.md](RELEASING.md)
for the workflow. Pass `--version-label v<version>` for the page title.

**Product voice.** The user-facing store targets read voice + a soft length aim
from the product profile, so pass `--product <id>` (configure profiles in
`testthese.toml`, §9).

**Character caps are hard ceilings.** `rw` *warns* if output would overflow — it
never silently truncates. `--limit <n>` only **tightens**; it can't raise the
ceiling past the store limit. Ceilings come from a TTL-cached `limits.json`
manifest with a baked-in offline fallback; `--refresh-limits` forces a refetch.

**Platform.** `--what-new` keys off the product's platform: generous on iOS
(TestFlight), tight on Android (Play, 500/lang).

---

## 6. HTML output

Every command takes `--html`, which renders the same report to a **single
self-contained HTML file** — inline CSS/JS, no CDN, no server, no extra model
calls beyond what the command already made. The aesthetic is deliberately
minimal — Verdana, narrow column, navy links, no chrome — readable and
copy-friendly, not a dashboard.

```sh
rw --html                                    # vitals as an HTML page
rw market --product ledgerly --html --open   # store-listing proof sheet in your browser
rw notes --asc-update --product ledgerly --html
```

| Flag | Meaning |
|---|---|
| `--html` | Render to HTML. Writes to `.rw/<command>-<range>.html` by default. |
| `--html-out <path>` | Override the output path (absolute, or relative to the repo). |
| `--open` | Launch the file in your default browser after writing. |

**Why a file, not a server.** A `localhost` server can't actually be shared and
adds a port + lifecycle dependency for a view that's static anyway. The file
is shareable, commit-able, re-openable offline, and needs no running process.

**Per-command views.**

- **`rw --html`** — the vitals dashboard: counts, hotspots, risk flags.
- **`rw many --html`** — counts + by-declared-type breakdown.
- **`rw blame --html`** — attribution by commit share.
- **`rw branch --html`** — branches that contributed to the change set.
- **`rw new --html`** — the feature list as plain prose.
- **`rw notes <target> --html`** — the note rendered *in context* with a live
  char meter against the store cap (plain → amber as it nears → red on
  overflow) plus a copy button.
- **`rw market --html`** — the **store-listing proof sheet**: each piece in
  its own block with its own cap meter and copy button. The preview you'd
  want before pasting into App Store Connect or Play Console.

**Skill mode.** `--html` doesn't apply with `--provider skill` — in skill mode
the host agent is the renderer, not `rw`. Passing both raises a clean error.

**`.rw/` is ignored by git** in this repo's `.gitignore`. Add the same line to
your own `.gitignore` so generated HTML doesn't get committed by accident.

---

## 7. Providers — who writes the prose

The semantic commands run through a **provider**, chosen by the `provider` key in
`testthese.toml` or the `--provider` flag (the flag wins):

| Provider | Needs a key? | What it does |
|---|---|---|
| `anthropic` *(default)* | yes | Calls the Anthropic API and prints the prose |
| `gemini` | yes | Calls the Google Gemini API and prints the prose |
| `skill` | **no** | Emits JSON for a host agent to complete (see §8) |

**API key** (`anthropic` / `gemini`): set the provider's env var —
`ANTHROPIC_API_KEY` or `GEMINI_API_KEY` (preferred) — or `api_key` in
`testthese.toml`. The environment variable wins. With `gemini` selected and the
`model` left at the Anthropic default, `rw` automatically uses a Gemini default
model. If no key is set, the semantic commands exit with a clear message — not a
crash.

> A Claude **Max/Pro plan** covers claude.ai and Claude Code, **not** the
> pay-as-you-go Anthropic API. If you don't have API credits, use skill mode (§8)
> — it routes the model work through your agent session at no extra cost.

---

## 8. Skill mode — no API key

In skill mode, `rw` does all the deterministic work and emits a JSON **envelope**;
a host agent (Claude Code, Cowork) reads it and writes the prose. No key, no
network call from `rw` — the agent you already pay for is the model.

### From the CLI

```sh
rw new --provider skill          # prints the envelope; hand it to your agent
rw notes --pr --provider skill
```

### As an installed skill (recommended)

`rw` ships a drop-in skill in the `skill/` directory. Install it once:

```sh
mkdir -p ~/.claude/skills/recap-wins
cp -R skill/ ~/.claude/skills/recap-wins/
```

Then, in a skill-aware agent, just ask in plain language:

> *"What did I ship on this branch?"*
> *"Write a PR description for this branch."*
> *"Write the App Store release notes for this update."*

The agent runs `rw`, reads the change report, and writes the answer — grounded in
your real commits and diff, within any character caps.

> Skills load at session start. After installing, start a fresh agent session so
> it's picked up.

### The envelope

The JSON `new`/`notes` emit in skill mode contains:

- `system` — the prompt (tone, audience, structure) the agent follows
- `user` — the grounded change set; facts to write from, never to invent
- `softTargetChars` / `ceilingChars` — the length aim and the hard limit (`0` = uncapped)
- `report` — the full deterministic `change_report.json`

---

## 9. Configuration

Per-repo, human-readable. Drop a `testthese.toml` in the repo root. Every key is
optional — `rw` works with no config. Copy `testthese.toml.example` to start.

```toml
base     = "main"
model    = "claude-sonnet-4-6"
provider = "anthropic"        # or "skill"
# api_key = "sk-ant-..."      # prefer the ANTHROPIC_API_KEY env var instead

[limits_manifest]             # store caps: fetched + cached with a TTL
# url = "https://.../limits.json"
ttl = "30d"

[review_notes.limits]         # offline fallback ceilings (chars; 0 = uncapped)
pr               = 0
asc_update       = 4000
gp_update        = 500
what_new_android = 500

[[product]]
id       = "ledgerly"
name     = "Ledgerly"
voice    = "clear, trustworthy, private-by-default; money without anxiety"
links    = ["https://novarch.lol/ledgerly"]
platform = "iOS"              # drives the --what-new cap
# soft editorial aims (chars); must be <= the hard ceilings above
targets  = { asc_update = 300, gp_update = 250, what_new = 350 }
```

Two tiers of limit, kept distinct:

- **Ceilings** (`[review_notes.limits]`) — hard platform caps. Never exceeded;
  `rw` warns on overflow.
- **Targets** (per-product) — soft editorial aims the model shoots for, so a
  4000-char ceiling doesn't yield a 4000-char wall.

> The real `testthese.toml` is gitignored so an `api_key` can't be committed. The
> tracked file is `testthese.toml.example`.

---

## 10. Recipes

**See what a branch introduced, offline:**
```sh
rw --base main
rw many --base main      # just the counts
```

**Write a PR description without leaving the terminal (with an API key):**
```sh
export ANTHROPIC_API_KEY=sk-ant-...
rw notes --pr
```

**Same, but key-free via your agent:**
```sh
rw notes --pr --provider skill | pbcopy   # then paste into Claude Code
# …or just ask the installed skill: "write a PR description for this branch"
```

**App Store release notes in a product's voice, within the cap:**
```sh
rw notes --asc-update --product ledgerly
```

**Recap a repo you're not in:**
```sh
rw --repo ~/code/mogwar --base release/2.0 --head feature/onboarding
```

**Feed the structured report to another tool:**
```sh
rw --json > report.json
```

**Preview the marketing pack as a store-listing proof sheet, in your browser:**
```sh
rw market --product ledgerly --html --open
```

**Render the App Store note with a live char meter against the 4000-char cap:**
```sh
rw notes --asc-update --product ledgerly --html --open
```

**Generate the per-release changelog page (the canonical artifact you commit):**
```sh
rw notes --changelog --version-label v0.2.0 --base v0.1.1 --head HEAD
# → docs/changelogs/v0.2.0.html
```

---

## 11. Troubleshooting

**`zsh: command not found: rw`** — the binary isn't on your PATH. Re-do the
symlink/alias step in §1, then `which rw`.

**`Not a git repository`** — you're not inside (or `--repo` doesn't point at) a
git work tree.

**`rw many` says "0 features" but I clearly shipped features** — your commits
don't use conventional-commit prefixes, so they bucket as chores. Use `rw new`
(semantic), which reads the diff and recovers the real features.

**`No Anthropic API key` / `No Gemini API key`** — set the provider's env var
(`ANTHROPIC_API_KEY` or `GEMINI_API_KEY`), or use `--provider skill` for the
key-free path (§8).

**Output overflows a store cap** — `rw` warns but doesn't truncate. Tighten with
`--limit <n>`, or regenerate; the store form is the final authority.

**`origin/main` looks stale** — `rw` never fetches. Run `git fetch` first.
