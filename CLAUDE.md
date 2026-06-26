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
- `Sources/SemanticKit/` — the **semantic layer**. Consumes a `ChangeReport` and
  renders prose through a pluggable **provider** (`Provider`): `anthropic` (API),
  `skill` (emits a `SkillEnvelope` JSON for a host agent — no key, no network),
  `gemini` (reserved — add its client in `ModelConfig.makeClient(for:)`, the one
  plug-in point). Selected by the `provider` config key or `--provider` flag.
  Depends on `RecapCore`; **never** the reverse. The API call is behind the
  `ModelClient` protocol — `AnthropicClient` is hand-rolled `URLSession` (zero
  deps); tests inject a mock so CI stays offline and keyless. API key from
  `ANTHROPIC_API_KEY` (env wins) or `api_key` in config.
- `Sources/rw/` — the `rw` command-line front end over `RecapCore` +
  `SemanticKit`.
- `Tests/RecapCoreTests/` — Swift Testing against real git fixtures (`GitFixture`
  builds throwaway repos in temp dirs). `Tests/SemanticKitTests/` — config
  parsing, prompt building, and engine logic via a `MockModelClient`.

## The contract

`ChangeReport` (`Sources/RecapCore/Models.swift`) is the `change_report.json`
contract from PRD §5 — the structured, verifiable picture of a change set. It
has a `schemaVersion`; bump it on breaking changes. Everything countable lives
here; the semantic layer consumes it.

## Phasing (PRD §11)

- **Phase 0 (done):** deterministic core — `rw` vitals (default), `many`,
  `blame`, `branch`. Offline, no LLM.
- **Phase 1 (done):** semantic layer — `rw new` and `rw notes` (all targets:
  `--pr`, `--asc-reviewer`, `--what-new`, `--asc-update`, `--gp-update`), with
  product-voice rendering and a TTL-cached `limits.json` cap manifest (offline
  fallback baked in; `--refresh-limits`, `--limit`).
- **Phase 3 (done):** pluggable providers — `anthropic` (API), `skill` (key-free,
  emits JSON for a host agent), `gemini` (reserved), selected by `provider`
  config / `--provider`; **and** the agent-skill package in `skill/` (`SKILL.md`
  + `scripts/recap-wins.sh`). The runner calls `rw` in skill mode and the host
  agent writes the prose. Install: copy `skill/` → `~/.claude/skills/recap-wins/`.
- **Phase 2 (done):** `rw market` — a marketing content pack (What's New, promo
  text, subtitle, GP short description, post, tweet) in a product's voice, each
  within its `[market.limits]` cap. Distinct from store-update `notes`; works in
  every provider mode incl. skill (emits one envelope per piece).
- Phase 4: localization. Phase 5: multi-repo (paid open-core line). Gemini
  provider (fill the reserved slot) is the next net-new.

## Conventions

- `rw help [topic]` is a hand-written guide (`Sources/rw/HelpCommand.swift`),
  separate from argument-parser's auto `--help`. Keep it and `docs/GUIDE.md` in
  sync when commands/flags change.
- The vitals path **must stay deterministic** — no model, no network (PRD §7).
- Classification: conventional-commit prefixes are authoritative. For `.other`
  commits, `CommitClassifier` *infers* a bucket (subject verbs + new-file
  evidence) into `Commit.inferredBucket` — the parsed `type` is never overwritten,
  and inferred counts are surfaced (`Vitals.inferredCount`) so the UI can flag
  declared-vs-guessed. Keep it transparent and predictable, no model.
- Risk flags are **advisory, never gates** (PRD §7).
- A ticket reference is *detected if present*, never *required* (PRD §12).
- Notes caps are **hard ceilings**: warn on overflow, never silently truncate;
  `--limit` only tightens, never loosens past the store ceiling (PRD §6.1).
- Two tiers of limit, don't conflate: hard platform **ceilings** vs soft
  per-product **targets** the model aims for (PRD §8).

## Commands

```sh
swift build
swift test
.build/debug/rw --base main          # vitals for current branch
.build/debug/rw --json                # raw change_report.json
```
