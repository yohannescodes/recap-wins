---
name: recap-wins
description: "Summarize what a git branch introduced — feature lists, PR descriptions, and store release notes — from the diff against a base ref. Use when the user asks 'what did I ship/change/introduce on this branch', wants a PR description written, needs App Store / Google Play / TestFlight release notes, or wants a recap of a change set. Works offline; the agent writes the prose, no API key needed."
version: 0.1.0
---

# recap-wins

`recap-wins` (binary `rw`) reads the diff between a branch and a base ref and
reassembles **what actually shipped** into the artifacts you need: vitals,
feature lists, PR descriptions, and store release notes.

This skill runs `rw` in **skill mode**: `rw` does all the deterministic git work
(classifying commits, counting churn, building a verified change report) and
emits **JSON**. **You, the agent, write the prose** from that JSON. No API key,
no network call from `rw` — you are the model.

## When to use

- "What did I ship / change / introduce on this branch?"
- "Write a PR description for this branch."
- "Write the App Store / Google Play / TestFlight release notes."
- "Recap this change set / summarize what's new."

## How it works

Run the script with a command. It returns JSON to stdout, which you read and act
on. The script finds the `rw` binary automatically (PATH, a local build, or it
builds from source if run inside the repo with Swift).

```bash
./scripts/recap-wins.sh <command> [--repo <path>] [--base <ref>] [--head <ref>] [args…]
```

`--repo` selects the git repo (default: current dir), `--base` the ref to compare
against (default `main`), `--head` the ref to compare (default current branch).

### Commands

| Command | What you produce from the JSON |
|---|---|
| `new` | A bulleted list of the **new user-facing features** |
| `notes --pr` | A **PR description** (technical, for a reviewer) |
| `notes --asc-update --product <id>` | App Store "What's New" (≤ cap, product voice) |
| `notes --gp-update --product <id>` | Google Play release notes (≤ cap, product voice) |
| `notes --what-new --product <id>` | TestFlight / Play testing notes |
| `notes --asc-reviewer` | App Store Connect App Review notes (private) |
| `vitals`, `many`, `blame`, `branch` | Raw `change_report.json` — facts, not prose |

## Writing prose from the JSON (semantic commands)

`new` and `notes` return a **skill envelope** with these fields:

- `instruction` — a one-line description of what to produce.
- `system` — the full system prompt describing the tone, audience, and structure.
  **Follow it as your instructions.**
- `user` — the grounded change-set context (commits, counts, hotspots). Treat its
  facts as ground truth; do not invent changes not present here.
- `softTargetChars` — the length to aim for (if set).
- `ceilingChars` — a HARD character limit. `0` means uncapped. When > 0, your
  output **must not exceed it** — store platforms reject overflowing copy.
- `report` — the full deterministic change report, for any extra grounding.

**Your job:** read `system` + `user`, then write exactly what `instruction` asks
— and nothing else (no preamble like "Here's your PR description"). Respect
`ceilingChars` strictly; if you can't fit, tighten, don't truncate mid-sentence.

### Example

```bash
./scripts/recap-wins.sh new --repo ~/code/ledgerly
```

Returns an envelope whose `system` says to list only genuine new features and
fold out chores/refactors, and whose `user` lists the branch's commits and
most-changed files. You then output the feature bullets that follow those rules.

```bash
./scripts/recap-wins.sh notes --asc-update --product ledgerly --repo ~/code/ledgerly
```

Returns an envelope with the product's voice in `system` and `ceilingChars`
(e.g. 4000). You write App Store "What's New" copy in that voice, within the cap.

## Deterministic commands

`vitals`, `many`, `blame`, `branch` return the raw `change_report.json` — already
final, structured facts. Present them as-is or render a short summary; there is
no prose to write and no model judgment required. Use these when the user wants
the numbers (counts, contributors, hotspots, risk flags), not a narrative.

## Notes

- A target for `notes` is required and exactly one (`--pr`, `--asc-update`, etc.).
  The user-facing store targets need `--product <id>` for voice; if the user
  hasn't configured products, `--pr` still works without one.
- Everything is offline and read-only. `rw` never writes to the repo, never
  fetches, and never calls a model — so `origin/*` refs reflect the last fetch.
