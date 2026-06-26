# `recap-wins` — Product Requirements Document

**Owner:** Yohannes Haile (Novarch LLC)
**Status:** Draft v0.1 — internal tool, not for commercialization yet
**Last updated:** 2026-06-26

---

## 1. Summary

`recap-wins` is a local, terminal-first tool that reads the diff between your current branch (or PR) and a base branch, builds a structured picture of what actually changed, and renders that into the artifacts you need to ship: vitals, feature lists, review notes, attribution, and marketing copy.

It is the **inbound** counterpart to a tool like ShipLog. ShipLog runs *after* merge and writes a polished public changelog *for your users*. `recap-wins` runs *before or at* merge and writes for *you, the shipper* — so you can see what you introduced, confirm it's what you meant, and produce the surrounding paperwork without context-switching out of the terminal.

It is language-agnostic. It operates on git, not on Swift or TypeScript, so it works identically across every Novarch repo.

---

## 2. Problem

You ship fast across five products (Ledgerly, HandleMe, Mog War, DOTS, KeepOrBin) under Novarch. The plan lives in Linear, but the *record* of what actually landed on a branch drifts: issue titles don't match what shipped, hotfixes land with no issue, and a finished branch is a wall of commits you have to mentally reassemble before you can review it, write the PR note, or announce it.

You already produce the source of truth — commits and diffs — just by working. `recap-wins` reads that and does the reassembly for you.

---

## 3. Goals / Non-goals

**Goals**
- Turn a branch/PR diff into an at-a-glance **vitals** read in under a second, fully offline.
- Generate the surrounding artifacts (review note, feature list, marketing pack) on demand.
- Work across any git repo regardless of language.
- Ship as both a standalone CLI **and** a universal agent skill — the `SKILL.md` + scripts convention any skill-aware agent can consume — from the same core.

**Non-goals (for now)**
- Not a mobile app. (This is deliberate — first non-mobile build.)
- Not a hosted/public changelog. That's ShipLog's lane; integration is possible later, not in scope.
- Not a CI gate or test runner, despite the working name (see §12).
- Internal-first. The intended path is open-core: the single-repo tool goes open source once it's solid internally, with cross-repo aggregation (§12) as the paid layer. Not a polished commercial product yet.

---

## 4. Users

One primary user: you, solo, across Novarch repos. Design for a single trusted operator, not multi-tenant. Keep config in-repo and human-readable. Don't build auth, dashboards, or accounts.

---

## 5. How it works

Two layers, cleanly separated. This separation is the core design decision — it's what lets the same tool run standalone or as an agent skill.

```
                 ┌─────────────────────────────┐
   git refs ──▶  │  Deterministic core         │  ──▶  change_report.json
 (HEAD vs base)  │  • commits, diffs, blame     │       (structured, offline,
                 │  • branch topology           │        instant, trustworthy)
                 │  • conventional-commit parse │
                 │  • vitals counts             │
                 └─────────────────────────────┘
                              │
                 ┌────────────┴────────────┐
                 ▼                         ▼
        Standalone CLI mode        Agent-skill mode
        (core calls Anthropic      (the host agent is the
         API for semantic cmds)     model and writes prose)
```

The **deterministic core** never needs a model or a network. It produces a `change_report.json`: the classified commits, per-file stats, blame attribution, branch graph, and vitals. Everything countable and verifiable lives here.

The **semantic layer** consumes that JSON to produce prose (feature summaries, review notes, marketing copy). It runs one of two ways:
- **CLI mode:** the binary calls the Anthropic API (Sonnet) directly.
- **Agent-skill mode:** the binary only emits JSON; the host agent (Claude Code, Cowork, or any skill-aware agent) is the model and writes the prose. No API key to manage.

Because the prose commands are "structured git data → text," they map almost perfectly onto an agent skill — the deterministic core is the skill's script, and `SKILL.md` tells the agent how to render each command. Nothing in that contract is vendor-specific.

---

## 6. Commands

All commands operate on a **change set**: the diff between a head ref (default: current branch) and a base ref (default: `main`, configurable). Override with `--base <ref>` / `--head <ref>`.

| Command | What it does | Layer | Output |
|---|---|---|---|
| `recap-wins` *(default)* | The **vitals** dashboard — one-screen health read of the change set | Deterministic | Summary block (see §7) |
| `recap-wins new` | Lists the new *features* you introduced, filtering out chores/refactors | Semantic | Bulleted feature list |
| `recap-wins many` | Counts distinct features / fixes / chores introduced (deduped across commits) | Deterministic (+ optional semantic dedup) | Counts + breakdown |
| `recap-wins notes` | Writes a release/review note for a chosen **target** (PR, App Review, test build, or store update), each in its own format and length | Semantic | Target-shaped note (see §6.1) |
| `recap-wins market` | Generates a text content pack for new features, in a product's voice | Semantic + product profile | App Store "What's New", short post, tweet, etc. |
| `recap-wins blame` | Attributes who changed what across the change set | Deterministic | Attribution by file/area |
| `recap-wins branch` | Shows which branches contributed commits to this change set | Deterministic | Branch list + topology |

Flags shared across commands: `--base`, `--head`, `--json` (raw report), `--product <id>` (for `recap-wins market`). `recap-wins notes` additionally takes a required target flag and an optional `--limit <n>` override (see §6.1).

**Notes on the tricky ones**

- `recap-wins many` is mostly deterministic via conventional-commit parsing, but multiple commits often add up to one feature. An optional semantic dedup pass collapses "5 commits → 2 features" so the count reflects user-facing units, not commit count.
- `recap-wins market` needs a **product profile** (which of the five apps, its voice and links). For a solo operator across five products with distinct tones, this is the difference between usable copy and generic filler. Profiles live in config (§8).
- `recap-wins blame` is mostly you today, but it still earns its place: it separates *your* authored changes from merged tooling/dependency commits and vendored code, so the "who" view answers "what did *I* introduce" cleanly.
- `recap-wins branch` answers provenance: when a branch absorbed other branches before you got to review, this shows what fed into "the thing meant to be new and tested."

### 6.1 `recap-wins notes` targets

"Review note" isn't one thing — it's the same change set rendered for different audiences, each with its own tone and length. One required target flag picks the destination:

| Flag | Destination | Audience | Tone / contents | Cap |
|---|---|---|---|---|
| `--pr` | Pull request description | You / a reviewer | Technical: what changed, why, areas to check | none |
| `--asc-reviewer` | App Store Connect → App Review notes | Apple's review team (private) | Demo steps, test credentials, why a feature behaves as it does | no published cap; keep tight |
| `--what-new` *(iOS)* | TestFlight "What to Test" | Your beta testers | What changed in this build + what to exercise | ~4,000 (unpublished) |
| `--what-new` *(Android)* | Play internal/closed testing release notes | Your beta testers | Same | 500 per language |
| `--asc-update` | App Store "What's New in This Version" | Public iOS users | User-facing release notes, product voice | 4,000 |
| `--gp-update` | Google Play "What's new" release notes | Public Android users | User-facing release notes, product voice | 500 per language |

Sources: App Store "What's New" 4,000 and Promotional Text 170 (App Store Connect Help); Google Play release notes 500 per language (Play Console Help). The two Apple internal fields — App Review notes and TestFlight "What to Test" — have no officially published character limit; the ~4,000 figure for "What to Test" is widely reported but unconfirmed by Apple, so treat both as effectively uncapped in the tool and let the App Store Connect form be the final authority.

Notes:
- **`--what-new` is not one cap.** TestFlight is generous; Play testing notes use the same 500-per-language limit as a public release. So `--what-new` keys off the product's target platform (from the profile, §8) — generate long for iOS, tight for Android, never assume one length.
- The two store-update targets (`--asc-update`, `--gp-update`) and `recap-wins market` both produce user-facing copy, but they're distinct: these emit the **store-native release-note block** within a hard char cap; `recap-wins market` emits a broader announcement pack (post, tweet, etc.). Keep them separate so neither overloads the other.
- The user-facing targets pull voice from the product profile (§8), same as `recap-wins market`, so a Ledgerly update doesn't sound like a DOTS update. Pass `--product <id>` alongside.
- Caps are **platform-enforced ceilings, not preferences.** The tool should treat them as hard limits — generate within the cap, and warn (don't silently truncate) if output would overflow. `--limit <n>` only tightens, never loosens past the store ceiling.
- Store rules drift, so caps aren't hardcoded. They come from a maintained `limits.json` manifest the tool fetches and **caches with a TTL**, falling back to the baked-in values (§8) when offline or stale; `--refresh-limits` forces a fetch. This keeps the deterministic core offline-capable while letting the published caps stay current. Once the project is open source, the manifest is community-maintained — the right place for a store-policy change to land as a one-line update rather than a code change.

---

## 7. Vitals (the default view)

`recap-wins` with no subcommand prints the vitals. Keep it deterministic, instant, and trustworthy — no model in this path. Proposed contents:

- Features / fixes / chores introduced (from conventional-commit parse)
- Files changed, insertions / deletions
- Contributors
- Branches involved
- Hotspots: the few files with the largest churn
- Risk flags (heuristic): unusually large diff, core/shared files touched, no test files added alongside source changes

Risk flags are advisory, not gates. They're a nudge, not a CI failure.

---

## 8. Configuration

Per-repo, human-readable (`.testtheserc` / `testthese.toml`). No global state, no accounts.

```toml
base = "main"
model = "claude-sonnet-4-6"

[limits_manifest]              # caps are fetched + cached, not hardcoded (see §6.1)
url   = "https://<project>/limits.json"   # maintained manifest; community-updated once OSS
ttl   = "30d"                  # refetch after this; --refresh-limits forces it now
# The values below are the OFFLINE FALLBACK, used when the manifest is unreachable or stale.

[review_notes.limits]      # chars; ceilings, not preferences. --limit only tightens.
pr               = 0       # 0 = no cap
asc_reviewer     = 0       # Apple publishes no cap; 0 = uncapped, form is the authority
what_new_ios     = 0       # TestFlight "What to Test": no published cap (~4,000 reported)
what_new_android = 500     # Play testing release notes, per language
asc_update       = 4000    # App Store "What's New" (App Store Connect Help)
gp_update        = 500     # Google Play release notes, per language (Play Console Help)

# Marketing-field ceilings, for recap-wins market when it targets store metadata.
# Verify in-console before a release; stores adjust these.
[market.limits]
asc_promotional_text = 170   # App Store promotional text
asc_subtitle         = 30    # App Store subtitle
gp_short_description  = 80   # Google Play short description

[[product]]
id = "ledgerly"
name = "Ledgerly"
voice = "clear, trustworthy, private-by-default; money without anxiety"
links = ["https://novarch.lol/ledgerly"]
locales = ["en", "am"]   # target locales for localized release notes / marketing (Phase 4)
# Soft house targets (chars) the model AIMS for, per target. Editorial, not platform.
# Must be <= the hard ceilings in [review_notes.limits]; the ceiling still hard-stops.
targets = { asc_update = 300, gp_update = 250, what_new = 350 }

[[product]]
id = "dots"
name = "DOTS"
voice = "calm, reflective; your life in weeks, screen time you can feel"
locales = ["en"]
targets = { asc_update = 220, gp_update = 200, what_new = 300 }   # DOTS runs leaner than Ledgerly
# ...handleme, mogwar, keeporbin
```

`recap-wins market --product ledgerly` pulls the matching profile. Profiles for all five Novarch apps ship as a starter config.

Two tiers of limit, don't conflate them: the **ceilings** in `[review_notes.limits]` / `[market.limits]` are hard platform caps (never exceeded, tool warns). The per-product **`targets`** are soft editorial aims — the length the model actually shoots for so a 4,000-char ceiling doesn't produce a 4,000-char wall nobody reads. Targets are per-product because a Ledgerly note and a DOTS note shouldn't be the same length. The numbers above are starting defaults to tune once you've seen real output; if a product omits `targets`, fall back to a global default (not the ceiling).

---

## 9. Tech stack

**Decided: Swift.** Chosen for genuine ownership — you can read, write, debug, and maintain it fluently, which is what lets you stand behind an open-source project rather than depend on AI to maintain your own repo — and because recap-wins' audience is iOS/mobile shippers, almost all on macOS, so Swift's one real weakness (Windows) barely applies. The honest cost is a heavier Linux-CI / cross-platform distribution story if that ever becomes a need. The comparison below is kept as the rationale of record.

| Concern | Recommendation | Why |
|---|---|---|
| Language | **Swift** (decided) | Genuine ownership + a Mac-heavy audience. Reach comparison kept below as rationale of record. |
| Git access | Shell out to system `git` | Zero deps, behaves exactly like the commands you'd run by hand. Skip libgit2/isomorphic-git for MVP. |
| Model | Anthropic API (Sonnet) in CLI mode; none in skill mode | Sonnet is the right speed/cost point for summarization. |

**On Swift specifically.** Yes — this builds cleanly in Swift, and for an internal tool you run on your own Macs it's arguably the best fit. `swift-argument-parser` maps directly onto the `recap-wins` subcommand layout, `Codable` is close to ideal for emitting `change_report.json`, and it compiles to a single native binary on your M4 — a clean agent-skill artifact with no runtime to ship alongside it. It also satisfies the "not a mobile app" goal in the most direct way: your strongest language, a new domain.

Two real costs, both small for your case: there's no official Anthropic Swift SDK (the official SDKs cover Python, TS, C#, Go, Java, PHP, Ruby), so CLI-mode calls go through a community package like SwiftAnthropic or a hand-rolled `URLSession` POST — and in agent-skill mode there's no call at all. And Swift's cross-platform / CI distribution story is heavier than `npx` or a Rust static binary if you ever want it running on Linux.

**Which runs everywhere?** Ranked purely on reach: **Rust** is the literal answer — one static binary (musl), every OS and CPU arch, no runtime to install. **TypeScript/Node** is nearly as broad since Node runs everywhere, but it carries a runtime dependency by default (close that gap by compiling with Bun, Deno, or Node SEA). **Swift** is strongest on Apple platforms, workable on Linux via the Swift 6 static SDK, and weakest of the three on Windows. So Rust > Node > Swift on universality — but "everywhere" for this tool is your Macs plus, at most, a Linux CI runner. All three clear that; Swift's only real gap is Windows, which isn't in your world. Reach only argues against Swift if Windows or zero-friction static Linux distribution actually shows up.

So the deciding question is **deployment surface**:

| If the tool… | Pick | Because |
|---|---|---|
| Stays local on your Macs | **Swift** | Strongest-language velocity, clean native binary, no real downside. |
| Needs to run in CI / on Linux / be shared cross-platform | **TypeScript** | First-class Anthropic SDK, trivial npm distribution. |
| Wants a single static binary above all | **Rust** | Fast, dependency-free binary; pairs with git-cliff. |

Either way, the deterministic core (Phase 0) needs no model, so the bulk of the tool is pure git + JSON — comfortable territory in any of the three, Swift included.

---

## 10. Distribution & packaging

1. **CLI:** depends on language — `swift build` + a Homebrew tap (Swift), `npx recap-wins` or a global install (TypeScript), or a single static binary (Rust). The package/canonical name is `recap-wins`; the installed binary is `rw`, so day-to-day you type `rw notes --pr`. For a personal tool, a Homebrew tap or a shell alias is enough; no need to publish.
2. **Agent skill:** a `SKILL.md` plus the core binary, droppable into the skills directory of any skill-aware agent (Claude Code, Cowork, etc.). The skill invokes the core for JSON, then the host agent writes the prose — same engine, no key management.

---

## 11. MVP & phasing

Build deterministic first; it's the trustworthy foundation and it ships value with no model and no network.

- **Phase 0 — Core (offline, no LLM):** change-report builder, `recap-wins` vitals, `recap-wins many`, `recap-wins blame`, `recap-wins branch`. Usable on day one.
- **Phase 1 — Semantic:** `recap-wins new`, `recap-wins notes` via Anthropic API.
- **Phase 2 — Marketing:** `recap-wins market` + the five product profiles.
- **Phase 3 — Skill:** package the same core as a universal agent skill (`SKILL.md` + scripts), verified against at least one non-Anthropic agent harness.
- **Phase 4 — Localization:** emit per-locale variants of the user-facing outputs (`--asc-update`, `--gp-update`, `--what-new`, and `recap-wins market` packs), driven by a `locales` list on each product profile. Two things make this more than "run it through translate": store caps are **per-language** (a 500-char Play note must fit in *each* locale, and translations routinely run ~30% longer than English — German, Amharic, Russian all overflow a limit the English version cleared), so the cap is re-checked per locale, not assumed from the source. And generating **native per locale** — asking the model for cap-aware copy directly in the target language — beats translate-then-truncate, which mangles the ending. Output should match each store's import shape (App Store Connect API per-locale fields; Google Play's per-language release-notes blocks).
- **Phase 5 — Multi-repo (paid layer):** the `--all-repos` cross-repo digest — "what did I touch across every Novarch repo this week," vitals and shipped-feature rollups across products. Held back from the open-source core as the open-core monetization line (§3, §12). Everything before this ships free and public; this is the upsell.

---

## 12. Decisions & open items

**Decided**

- **Scope — local only (was Q2).** The MVP works on a local branch-vs-base diff. No GitHub/GitLab API enrichment for now; nothing depends on a host being reachable.
- **"New / tested" signal — git-native, universal (was Q3).** The change set is defined by branch-vs-base. "What's meant to be tested" is refined by a configurable branch-name convention plus conventional-commit types — both native to git, no external service. A ticket ID (Linear/JIRA/GitHub) is *detected if present* in the branch or commits but never *required*, so the tool never locks to a PM tool or a host.
- **Limits refresh — cached manifest, not live scraping (was Q4).** Store caps come from a small maintained `limits.json` the tool fetches and caches with a TTL, falling back to the baked-in values (§8) when offline or stale. Scraping forums per run isn't reliable (unstructured, rate-limited); a curated manifest is. Once the project is open source, the manifest is a natural community-maintained surface — caps stay current from the field without the core losing its offline guarantee. Optional `--refresh-limits` forces a fetch.
- **Multi-repo — the open-core line (was Q5).** The cross-repo `--all-repos` digest ("what did I touch across Novarch this week") stays *out* of the open-source core and becomes the premium/monetizable feature. Open-core: single-repo tool is free and public; multi-repo aggregation is the paid layer.
- **Name — `recap-wins` (was Q1).** Chosen over the `test-*` prefix, which read like a test runner. A recap of what shipped — your wins. Commands are now subcommands of the binary: `recap-wins` alone for vitals, then `new`, `many`, `notes`, `market`, `blame`, `branch`. Verified unregistered on npm, crates.io, and GitHub (plain `recap` is taken on npm and crates.io, which is why the compound matters); Homebrew via a personal tap.
- **Short alias — `rw`.** The package/canonical name stays `recap-wins`; the installed binary is `rw` (the `ripgrep` → `rg` pattern), so you type `rw notes --pr`. Registries don't gate a bin alias — only your local `PATH` does, so a quick `which rw` before shipping confirms no collision (there's no standard `rw` system command). This spec keeps using the canonical `recap-wins` in tables for readability; `rw` is just what you type.
- **Language — Swift.** Picked over Rust for genuine ownership (you can maintain and defend it fluently, which is the real credibility signal for OSS — not which language hints at AI use) and because the audience is Mac-heavy, so Swift's Windows gap barely applies (§9). Trade-off: heavier Linux-CI / cross-platform distribution if that ever becomes a need. Implies `swift-argument-parser` for the CLI, `Codable` for `change_report.json`, and a community SDK or hand-rolled `URLSession` for the Phase 1 API call (no official Anthropic Swift SDK).
- **House-style targets — per-product, soft.** Two tiers of limit: the platform **ceilings** (§8) are hard and never exceeded; the per-product **`targets`** (§8) are soft editorial aims the model shoots for, so a 4,000-char ceiling doesn't yield a 4,000-char wall. Targets vary by product — Ledgerly and DOTS shouldn't aim for the same length. Decided as a mechanism; the concrete numbers are starting defaults to tune once real output exists (post-build, not a spec blocker).

**Nothing structural remains open.** What's left is post-build tuning — the actual house-target numbers per product, set once you've seen a few real notes — not a decision the spec needs to make first.

---

## 13. Success criteria

It works if, on any Novarch branch, you can run one command and trust the vitals without re-reading the diff, and produce a review note or a Ledgerly "What's New" without leaving the terminal or hand-reassembling your own commits.
