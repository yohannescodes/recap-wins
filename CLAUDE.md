# CLAUDE.md

Guidance for working in this repo.

## What this is

`recap-wins` (binary `rw`) — a local, offline, terminal-first tool that diffs a
branch vs a base ref and reassembles "what shipped" into vitals, feature lists,
review notes, and marketing copy. Full spec: `docs/recap-wins-PRD.md`. Read it
before making product decisions.

## Stack

- **Swift 6** (SwiftPM). Decided in the PRD — chosen for genuine ownership and a
  Mac-heavy audience.
- `swift-argument-parser` for the CLI, `Codable` for the JSON contract.
- **Shell out to system `git`** — no libgit2, no isomorphic-git. Zero deps.

## Layout

- `Sources/RecapCore/` — the deterministic, offline **library**. No CLI, model,
  or network dependencies. This is the engine the CLI and (Phase 3) the agent
  skill both consume. Keep it that way: nothing in `RecapCore` should import
  ArgumentParser or make network calls.
- `Sources/rw/` — the `rw` command-line front end over `RecapCore`.
- `Tests/RecapCoreTests/` — Swift Testing, exercising the core against real git
  fixtures (`GitFixture` builds throwaway repos in temp dirs).

## The contract

`ChangeReport` (`Sources/RecapCore/Models.swift`) is the `change_report.json`
contract from PRD §5 — the structured, verifiable picture of a change set. It
has a `schemaVersion`; bump it on breaking changes. Everything countable lives
here; the semantic layer consumes it.

## Phasing (PRD §11)

- **Phase 0 (done):** deterministic core — `rw` vitals (default), `many`,
  `blame`, `branch`. Offline, no LLM.
- Phase 1: `new`, `notes` via Anthropic API.
- Phase 2: `market` + product profiles.
- Phase 3: package the core as a universal agent skill.
- Phase 4: localization. Phase 5: multi-repo (paid open-core line).

## Conventions

- The vitals path **must stay deterministic** — no model, no network (PRD §7).
- Risk flags are **advisory, never gates** (PRD §7).
- A ticket reference is *detected if present*, never *required* (PRD §12).

## Commands

```sh
swift build
swift test
.build/debug/rw --base main          # vitals for current branch
.build/debug/rw --json                # raw change_report.json
```
