# Changelog

All notable changes to `recap-wins` ship here.

The format is loosely [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Newest releases are at the top.

Each version also has a **rendered release page** under
[`docs/changelogs/`](docs/changelogs/) — written by `rw notes --changelog` and
linked from the GitHub Release for that version. The markdown here and the
HTML there are generated from the same prose at release time
(see [RELEASING.md](RELEASING.md)).

---

## [v0.3.1](docs/changelogs/v0.3.1.html) — 2026-06-28

### Added

- **New commit comparison commands** — `rw draft`, `rw release-notes`, and `rw marketing` generate content from any two commits, not just branch vs base. Perfect for creating PR descriptions after the fact, generating release notes between version tags, or producing marketing copy for specific releases.
- **Flexible commit range syntax** — All comparison commands support both `commit1 commit2` and `commit1..commit2` syntax, working with tags, branches, SHAs, and any git reference.
- **Full provider support** — New commands work with all existing providers (Anthropic, Gemini, skill mode) and output formats (markdown, HTML, JSON).

### Changed

- **Documentation expanded** — README and GUIDE now include comprehensive examples for the new comparison commands, showing use cases from release notes to marketing copy generation.

---

## [v0.3.0](docs/changelogs/v0.3.0.html) — 2026-06-27

### Added

- **`rw vitals`** — explicit subcommand for the vitals dashboard with the full output flag set. Use `rw vitals --json` or `rw vitals --html` when you want JSON or HTML output of the one-screen change-set view; bare `rw` still prints the formatted dashboard exactly as before.

### Changed

- **`--html` and `--json` now work on every subcommand, including `rw align`.** Previously the root `rw` command declared these long-name flags, and swift-argument-parser resolves parent-level names before child ones — so `rw align --html` silently routed to the root and never rendered the parity matrix. The root no longer declares those flags, and each subcommand owns them directly. The HTML matrix you've been reaching for with `rw align --matrix` is now `rw align --html`, matching every other command in the toolkit.
- **`rw align` legacy flag names kept as deprecated aliases for one release.** `--matrix`, `--matrix-out`, `--open-matrix`, `--page`, and `--emit-json` continue to work, but `--html`, `--html-out`, `--open`, and `--json` are the documented names going forward. The legacy aliases will be removed in v0.4.
- **Documentation aligned with the new flag surface.** README, GUIDE, and the in-terminal `rw help` text now show `rw align --html --open` and `rw vitals --json` as the canonical examples. The earlier "why `--matrix` instead of `--html`" explainer is gone — the answer is now "it's `--html`."

### Breaking

- **`rw --json` and `rw --html` no longer work on the bare root command.** Use `rw vitals --json` and `rw vitals --html` instead. Plain-text `rw` (no flags) is unchanged. Existing scripts that piped `rw --json > report.json` need `rw vitals --json > report.json`.

---

## [v0.2.1](docs/changelogs/v0.2.1.html) — 2026-06-27

### Added

- **`rw align`** — compare two native ports of the same product (e.g. iOS in Swift and Android in Kotlin), with no shared git history, and surface parity gaps. Builds a feature ledger for each side, runs a semantic matcher that classifies each pairing as `paired` / `equivalent` / `gap_on_a` / `gap_on_b` / `ambiguous` with a confidence score, drafts tracker-agnostic issues for confirmed gaps, and (with `--matrix`) renders a filterable HTML parity matrix you can open in your browser. Ships with a built-in Apple↔Google equivalence table (Apple Pay/Google Pay, StoreKit/Play Billing, Keychain/Keystore, HealthKit/Health Connect, APNs/FCM, iCloud/Drive, WidgetKit/Glance, SwiftUI/Compose, Core Data/Room, Combine/Flow, TestFlight/Play Internal Testing, Sign in with Apple/Google Sign-In). Per-product `[[product.parity.equivalent]]` entries extend the table; `--confirm <match-id>` writes back to it. Configure a port pair in `testthese.toml` (`[product.ports]`) and run `rw align --product <id>` — or pass `--with <path>` / `--a <path> --b <path>` for ad-hoc runs.
- **`rw align --matrix`** — the filterable HTML parity matrix (FRD §9.1). Two-column layout with status chips, confidence pills, filter chips at the top, drafted issues with copy buttons at the bottom. Same PG-blog aesthetic as the rest of `rw`'s `--html` surfaces. `--matrix-out <path>` overrides the default; `--open-matrix` launches the file in your default browser. `--page` is an alias for `--matrix`.
- **`rw align --issues <format>`** — tracker-flavored wrappers around the canonical markdown issue body. `markdown` (default, the source), `linear` (h1 title + `Labels:` line), `github` (`Title:`/`Labels:` prefixes that pipe cleanly into `gh issue create`), `jira` (wiki markup: `h2.`, `*bold*`, `{{code}}`, `*` bullets). Pure formatters — no API calls, no posting.
- **`rw align --confirm <match-id>`** — promote an `equivalent` or `ambiguous` match into the curated parity map by appending a `[[product.parity.equivalent]]` block to `testthese.toml`. Idempotent on the `(a, b)` lowercase tuple. The matcher stops re-flagging confirmed pairs on the next run.
- **`rw align --ledger-only`** — skip the semantic matcher and emit only the per-port ledgers. Deterministic, offline, key-free — useful when you want to see what each side claims without spending a model call.
- **Built-in Apple↔Google equivalence table** with 12 canonical pairs. Merges case-insensitively with per-product curated entries; the product's note wins on duplicates.
- **`rw align --provider skill`** — key-free path. `rw` builds both ledgers, prints the matcher envelope; your host agent (Claude Code, Cowork) returns the match results.
- **`.github/workflows/notify-novarch.yml`** — fires a `repository_dispatch` event at `yohannescodes/novarch.lol` on every `v*` tag push so the site can sync release links automatically. Set `NOVARCH_DISPATCH_TOKEN` in repo secrets to activate; the workflow fails fast with a clear error if the secret isn't set.

### Changed

- **The release flow now also includes the workflow notification** — once `NOVARCH_DISPATCH_TOKEN` is configured, tag pushes automatically trigger the site sync. Manual `workflow_dispatch` lets you re-fire for an existing tag without re-tagging.
- **`rw align`'s HTML and JSON flag names use subcommand-unique spellings** to avoid being shadowed by the root command's `--html` / `--json`: `--matrix` (with `--page` alias) and `--emit-json` respectively. `rw help align` and `GUIDE.md` document the why.

### Fixed

- Skill mode for `rw align` now raises a clean validation error when combined with `--matrix` or `--confirm` (`rw` doesn't see the agent's match results in skill mode, so neither flag can do meaningful work). Previously these would have silently produced empty/incorrect output; now the failure mode is loud and immediate.

---

## [v0.2.0](docs/changelogs/v0.2.0.html) — 2026-06-27

### Added

- **`--html` on every command.** `rw`, `rw many`, `rw blame`, `rw branch`,
  `rw new`, `rw notes`, and `rw market` all accept `--html`, which renders
  the same report to a single self-contained, offline HTML file — inline
  CSS/JS, no CDN, no server, no extra model calls. Companion flags:
  `--html-out <path>` to override the default location and `--open` to
  launch the file in your default browser after writing.
- **`rw notes --changelog`.** A new `notes` target for release-page
  changelogs. Always renders HTML and defaults its output under
  `docs/changelogs/v<version>.html`. Generates a clean
  `Added / Changed / Fixed` page with a "Generated by rw" credit — the
  canonical "what changed" artifact you commit per version.
- **`rw market --html` proof sheet.** The marketing pack renders as an App
  Store / Play Console preview: each piece in its own block with a live
  char meter against its store cap and a copy button — the page you eyeball
  before pasting into a store form.
- **`rw notes --html` with a live cap meter.** Notes render in context with
  their store cap visualized — plain at first, amber as you near the limit,
  red when you exceed it.

### Changed

- **`GUIDE.md` moved to the repo root** alongside `README.md` and `LICENSE`.
  The user guide is a primary doc, not supporting material. Updated the
  README link.
- **New `RELEASING.md` at the root** documenting the two-PR release flow
  (code/version first, formula second) so future releases are repeatable.
  Grounded in `scripts/release.sh`.
- **New `CONTRIBUTING.md` at the root** with build/test commands,
  conventional-commit expectation, and the open-core scope line (cross-repo
  aggregation is the paid layer; single-repo work is welcome).
- **README docs index.** A new "Docs" section links GUIDE / Changelogs /
  CONTRIBUTING / RELEASING.
- **Skill mode + `--html`** raises a clean validation error rather than
  silently doing nothing — in skill mode the host agent is the renderer,
  not `rw`.
- **`.rw/` is gitignored.** The default output directory for `--html` is
  added to `.gitignore` so generated HTML doesn't end up tracked.

---

## [v0.1.1] — 2026-06-26

Initial Homebrew release. Single-repo CLI with the deterministic core
(vitals, many, blame, branch) and the semantic commands (new, notes,
market) via Anthropic / Gemini / skill providers. See the
[`v0.1.1`](https://github.com/yohannescodes/recap-wins/releases/tag/v0.1.1)
tag for the source.

---

## [v0.1.0] — 2026-06-26

First tagged release. See the
[`v0.1.0`](https://github.com/yohannescodes/recap-wins/releases/tag/v0.1.0)
tag for the source.
