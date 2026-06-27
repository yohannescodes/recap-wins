import ArgumentParser
import Foundation

/// `rw help [topic]` — a hand-written, teaching-oriented guide.
///
/// This is distinct from argument-parser's auto-generated `--help` (which lists
/// flags): it explains the concepts, the command surface, the provider modes,
/// and config, with real examples. `rw help <topic>` drills into one area.
struct Help: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the recap-wins guide. `rw help <topic>` drills into one area."
    )

    @Argument(help: "Optional topic: commands, notes, market, align, providers, skill, config, concepts.")
    var topic: String?

    func run() {
        let page: String
        switch topic?.lowercased() {
        case nil, "", "overview", "guide":
            page = HelpText.overview
        case "concepts", "concept", "model":
            page = HelpText.concepts
        case "commands", "command":
            page = HelpText.commands
        case "notes", "note":
            page = HelpText.notes
        case "market", "marketing":
            page = HelpText.market
        case "align", "parity", "ports":
            page = HelpText.align
        case "providers", "provider", "modes", "mode":
            page = HelpText.providers
        case "skill", "skills", "agent":
            page = HelpText.skill
        case "config", "configuration", "toml":
            page = HelpText.config
        default:
            page = HelpText.unknown(topic ?? "")
        }
        print(page)
    }
}

/// The guide content. Plain helpers from `Style` keep it consistent with the
/// vitals view and respect `NO_COLOR` / non-TTY automatically.
enum HelpText {
    private static func h(_ t: String) -> String { Style.bold(t) }
    private static func dim(_ t: String) -> String { Style.dim(t) }
    private static func cmd(_ t: String) -> String { Style.cyan(t) }

    static var overview: String {
        """
        \(h("recap-wins")) \(dim("— see what your branch introduced, offline and instant."))

        \(h("WHAT IT IS"))
          rw reads the diff between your branch and a base ref and reassembles
          what actually shipped into: vitals, feature lists, PR descriptions,
          and store release notes. It runs on git, so it works in any repo.

        \(h("THE TWO HALVES"))
          \(dim("offline"))   vitals, many, blame, branch — deterministic, no key, no network.
          \(dim("semantic"))  new, notes — turn the change set into prose. Via the
                    Anthropic API (a key) OR a host agent (skill mode, no key).

        \(h("QUICK START"))
          \(cmd("rw"))                      vitals for the current branch vs main
          \(cmd("rw --base develop"))       compare against a different base
          \(cmd("rw new --provider skill")) list new features, key-free (host agent)
          \(cmd("rw notes --pr"))           write a PR description

        \(h("LEARN MORE"))
          \(cmd("rw help concepts"))   the change-set model: repo / base / head
          \(cmd("rw help commands"))   every command, with examples
          \(cmd("rw help notes"))      the notes targets and char caps
          \(cmd("rw help market"))     the marketing content pack
          \(cmd("rw help align"))      cross-port parity \(dim("(slice 1 preview)"))
          \(cmd("rw help providers"))  anthropic vs skill vs gemini
          \(cmd("rw help skill"))      use rw inside an agent with no API key
          \(cmd("rw help config"))     testthese.toml: base, model, products

        \(dim("Tip: every command also takes --help for its raw flag list."))
        """
    }

    static var concepts: String {
        """
        \(h("CONCEPTS — the change set"))

        Every rw command analyzes a \(h("change set")): the diff between a head ref
        and a base ref, in a repo. Three independent knobs:

          \(cmd("--repo <path>"))   which git repo to read   \(dim("(default: current dir)"))
          \(cmd("--base <ref>"))    what you compare against  \(dim("(default: main)"))
          \(cmd("--head <ref>"))    what you compare          \(dim("(default: HEAD)"))

        So \(cmd("rw many --base develop")) means: in the repo I'm in, count what my
        current branch added on top of develop.

        \(h("REFS ARE ANY GIT REF"))
          \(cmd("rw --base v1.2.0 --head v1.3.0"))   what shipped between two tags
          \(cmd("rw --base main --head a1b9f3c"))    main vs a specific commit
          \(cmd("rw many --base origin/main"))       vs remote main (local data)

        \(h("OFFLINE & READ-ONLY"))
          rw never writes to the repo, never fetches, never calls a model on the
          deterministic path. origin/* refs reflect your last `git fetch`.

        \(h("CLASSIFICATION"))
          Counts come first from conventional-commit prefixes (feat:, fix:,
          chore:…) — the authoritative signal. For commits with no recognized
          prefix, rw INFERS a bucket from the subject verbs and the diff (new
          source files lean feature). Inferred counts are flagged in the output
          ("N inferred from message/diff") so you can tell declared from guessed.
          The parsed type is never overwritten; --json shows both.
        """
    }

    static var commands: String {
        """
        \(h("COMMANDS"))

        \(h("rw")) \(dim("(default) — vitals dashboard")) \(dim("· offline"))
          One-screen health read: feature/fix/chore counts, files +/-, contributors,
          branches, hotspots (largest churn), and advisory risk flags.
          \(cmd("rw"))   \(cmd("rw --base develop"))   \(cmd("rw --json"))

        \(h("rw many")) \(dim("— count what was introduced")) \(dim("· offline"))
          Features / fixes / chores, plus a by-type breakdown. Deterministic.
          \(cmd("rw many --base develop"))

        \(h("rw blame")) \(dim("— attribution")) \(dim("· offline"))
          Who authored the change set, by commit share.
          \(cmd("rw blame"))

        \(h("rw branch")) \(dim("— provenance")) \(dim("· offline"))
          Which branches contributed commits to this change set.
          \(cmd("rw branch"))

        \(h("rw new")) \(dim("— list new features")) \(dim("· semantic"))
          The genuinely new, user-facing features, with chores/refactors folded out.
          \(cmd("rw new"))   \(cmd("rw new --provider skill"))

        \(h("rw notes <target>")) \(dim("— write a review/release note")) \(dim("· semantic"))
          One target flag picks the destination. See \(cmd("rw help notes")).
          \(cmd("rw notes --pr"))   \(cmd("rw notes --asc-update --product ledgerly"))

        \(h("rw market --product <id>")) \(dim("— marketing content pack")) \(dim("· semantic"))
          A pack of announcement pieces in the product's voice. See \(cmd("rw help market")).
          \(cmd("rw market --product ledgerly"))   \(cmd("rw market --product ledgerly --pieces tweet,post"))

        \(h("rw align --product <id>")) \(dim("— cross-port parity")) \(dim("· slice 1 preview · offline"))
          Compares two native ports of the same product. Slice 1 ships the
          deterministic ledger half; the matcher arrives in slice 2. See
          \(cmd("rw help align")) for the full story.
          \(cmd("rw align --product ledgerly --emit-json"))

        \(h("GLOBAL"))
          \(cmd("--repo <path>"))  \(cmd("--base <ref>"))  \(cmd("--head <ref>"))  \(cmd("--json"))
          \(cmd("--html"))         render to a self-contained, offline HTML file
          \(cmd("--html-out <p>")) override the output path  \(cmd("--open")) open it after writing
          \(dim("--json emits the raw change_report.json on any command — offline, no key."))
          \(dim("--html composes with every command; no extra model calls beyond the run."))
        """
    }

    static var notes: String {
        """
        \(h("rw notes — targets & caps"))

        \(cmd("rw notes")) takes exactly one target. Each has its own audience, tone,
        and character ceiling:

          \(cmd("--pr"))            PR description \(dim("— technical, for a reviewer. Uncapped."))
          \(cmd("--asc-reviewer"))  App Store Connect → App Review notes \(dim("(private)"))
          \(cmd("--what-new"))      TestFlight / Play testing notes \(dim("(platform-aware)"))
          \(cmd("--asc-update"))    App Store \"What's New\" \(dim("(≤4000, product voice)"))
          \(cmd("--gp-update"))     Google Play release notes \(dim("(≤500/lang, product voice)"))
          \(cmd("--changelog"))     Release-page changelog \(dim("(HTML-only — see CHANGELOG below)"))

        \(h("PRODUCT VOICE"))
          The user-facing store targets read voice + a soft length aim from the
          product profile — pass \(cmd("--product <id>")):
          \(cmd("rw notes --asc-update --product ledgerly"))

        \(h("CHAR CAPS"))
          Caps are HARD platform ceilings. rw \(h("warns")) if output overflows — it
          never silently truncates. \(cmd("--limit <n>")) only tightens, never loosens
          past the store ceiling. Ceilings come from a TTL-cached limits.json
          manifest with a baked-in offline fallback; \(cmd("--refresh-limits")) refetches.
          \(cmd("rw notes --gp-update --product ledgerly --limit 300"))

        \(h("PLATFORM"))
          --what-new keys off the product's platform: generous on iOS (TestFlight),
          tight on Android (Play, 500/lang). Set platform in the product profile.

        \(h("--html"))
          \(cmd("rw notes --asc-update --product ledgerly --html"))
          Renders the note in context with a live char meter against the cap, plus
          a copy button. Writes to \(dim(".rw/notes-<target>-<range>.html")) by default;
          \(cmd("--html-out <path>")) overrides, \(cmd("--open")) launches it in your browser.

        \(h("CHANGELOG"))
          \(cmd("rw notes --changelog --version-label v0.2.0 --base v0.1.1 --head HEAD"))
          The release-page changelog. Always renders HTML (the page IS the artifact,
          not a preview) and defaults its output under \(dim("docs/changelogs/v<version>.html")).
          Generates a clean Added / Changed / Fixed page with a "Generated by rw" credit.
          See RELEASING.md for the workflow — one HTML page per tagged release.
        """
    }

    static var market: String {
        """
        \(h("rw market — marketing content pack"))

        \(cmd("rw market --product <id>")) generates a pack of marketing pieces for the
        new features, in the product's voice. A \(h("product is required")) for voice.

        \(h("PIECES")) \(dim("(--pieces to select; default is all)"))
          \(cmd("whatsNew"))          App Store \"What's New\" announcement \(dim("(uncapped)"))
          \(cmd("promotionalText"))   App Store promotional text \(dim("(≤170)"))
          \(cmd("subtitle"))          App Store subtitle \(dim("(≤30)"))
          \(cmd("shortDescription"))  Google Play short description \(dim("(≤80)"))
          \(cmd("post"))              a short social post \(dim("(uncapped)"))
          \(cmd("tweet"))             a tweet \(dim("(≤280)"))

        \(h("EXAMPLES"))
          \(cmd("rw market --product ledgerly"))                full pack
          \(cmd("rw market --product ledgerly --pieces tweet,post"))   just social
          \(cmd("rw market --product ledgerly --provider skill"))      key-free (host agent)

        \(h("VS notes"))
          market is the broad ANNOUNCEMENT pack (post, tweet, blurbs). The store
          release-note block lives in \(cmd("rw notes --asc-update")) / \(cmd("--gp-update")).
          Caps are hard ceilings — market warns on overflow, never truncates.

        \(h("--html"))
          \(cmd("rw market --product ledgerly --html --open"))
          Renders the pack as a store-listing proof sheet: each piece in its own
          block with a live cap meter and a copy button — what you'd eyeball
          before pasting into App Store Connect / Play Console.
        """
    }

    static var align: String {
        """
        \(h("rw align — cross-port parity")) \(dim("(slice 1 preview)"))

        \(cmd("rw align")) compares two native ports of the same product
        (e.g. Ledgerly iOS in Swift and Ledgerly Android in Kotlin) and
        surfaces parity gaps. Unlike every other rw command, it reads TWO
        repos with no shared git history — there's nothing for git diff to
        compare. It builds a FEATURE LEDGER for each side instead, then
        hands both ledgers to the semantic matcher.

        \(h("CURRENT STATUS"))
          \(dim("slice 1"))  ledger extraction (this release) — both sides build,
                     emit AlignReport JSON. No match yet.
          \(dim("slice 2"))  semantic matcher (paired / equivalent / gap /
                     ambiguous) + tracker-agnostic issue drafts.
          \(dim("slice 3"))  HTML parity matrix view + confirmation loop.

        \(h("USAGE"))
          \(cmd("rw align --product ledgerly"))               configured port pair
          \(cmd("rw align --with ../ledgerly-android"))       current repo is side A
          \(cmd("rw align --a ./ios --b ./android"))          both sides explicit
          \(cmd("rw align --product ledgerly --emit-json"))   the raw AlignReport

        \(h("WHY --emit-json AND NOT --json"))
          The root \(cmd("rw")) command already has a --json flag for the vitals
          report. When subcommand and parent share a long flag name,
          argument-parser resolves the parent's first; --emit-json avoids the
          collision and reads cleanly as \"emit the AlignReport JSON\".

        \(h("CONFIG")) \(dim("(testthese.toml)"))
          [[product]]
          id = \"ledgerly\"

          [product.ports]
          a = { name = \"ios\",     path = \"../ledgerly-ios\",     base = \"main\" }
          b = { name = \"android\", path = \"../ledgerly-android\", base = \"main\" }
          since = \"v1.0\"

          [[product.parity.equivalent]]
          a = \"Apple Pay checkout\"
          b = \"Google Pay checkout\"

        \(h("THE DISCLAIMER IS NON-OPTIONAL"))
          Every AlignReport ships with the framing that parity is candidates
          to confirm, never authoritative. A parity tool that's confidently
          wrong makes you relax when you shouldn't.
        """
    }

    static var providers: String {
        """
        \(h("PROVIDERS — who writes the prose"))

        The semantic commands (new, notes) run through a provider, chosen by the
        \(cmd("provider")) config key or the \(cmd("--provider")) flag \(dim("(flag wins)")):

          \(cmd("anthropic"))  \(dim("(default)"))  Calls the Anthropic API and prints the prose.
                          Needs ANTHROPIC_API_KEY; billed pay-as-you-go.
          \(cmd("gemini"))                Calls the Google Gemini API. Needs GEMINI_API_KEY.
          \(cmd("skill"))                 Emits JSON for a host agent (Claude Code, Cowork)
                          to complete. \(h("No key, no network")) — the agent is the model.

        \(h("API KEY")) \(dim("(anthropic / gemini)"))
          Set the provider's env var — ANTHROPIC_API_KEY or GEMINI_API_KEY
          \(dim("(preferred)")) — or api_key in testthese.toml. The env var wins. With
          gemini selected and the default model left as-is, rw uses a Gemini
          default model automatically.

        \(h("WHICH TO USE"))
          If you already pay for Claude through a plan, \(cmd("--provider skill")) is the
          zero-extra-cost path — see \(cmd("rw help skill")). Use \(cmd("anthropic")) when you
          want rw to produce the prose directly from the terminal.
        """
    }

    static var skill: String {
        """
        \(h("SKILL MODE — rw with no API key"))

        In skill mode rw does the deterministic work and emits a JSON \(h("envelope"));
        a host agent (Claude Code, Cowork) reads it and writes the prose. No key,
        no network call from rw — the agent you already pay for is the model.

        \(h("FROM THE CLI"))
          \(cmd("rw new --provider skill"))     emit the envelope, pipe it to your agent
          \(cmd("rw notes --pr --provider skill"))

        \(h("AS AN INSTALLED SKILL"))
          rw ships a drop-in skill (the skill/ directory). Install it once:
          \(cmd("cp -R skill/ ~/.claude/skills/recap-wins/"))
          Then just ask your agent in plain language:
            \(dim("\"what did I ship on this branch?\""))
            \(dim("\"write the App Store release notes for this update\""))
          The agent runs rw, reads the change report, and writes the answer.

        \(h("THE ENVELOPE"))
          system        the prompt: tone, audience, structure — the agent follows it
          user          the grounded change set — facts to write from, not invent
          ceilingChars  a hard char limit (0 = uncapped) the agent must respect
          report        the full deterministic change_report.json
        """
    }

    static var config: String {
        """
        \(h("CONFIG — testthese.toml"))

        Per-repo, human-readable. Drop a testthese.toml in the repo root. All keys
        are optional; rw works with none. Copy testthese.toml.example to start.

        \(h("TOP LEVEL"))
          \(cmd("base"))      default base ref          \(dim("(--base overrides)"))
          \(cmd("model"))     model for anthropic mode  \(dim("(e.g. claude-sonnet-4-6)"))
          \(cmd("provider"))  anthropic | skill | gemini \(dim("(--provider overrides)"))
          \(cmd("api_key"))   optional \(dim("— prefer the ANTHROPIC_API_KEY env var instead"))

        \(h("PRODUCTS")) \(dim("([[product]] blocks)"))
          id, name, voice, links, platform (iOS|android), and soft length
          targets per note target. Used by the user-facing notes targets and
          (later) rw market. Reference with \(cmd("--product <id>")).

        \(h("LIMITS"))
          \(cmd("[limits_manifest]"))    url + ttl for the fetched store-cap manifest.
          \(cmd("[review_notes.limits]")) baked-in offline fallback ceilings.

        \(dim("Real config (testthese.toml) is gitignored so an api_key can't be committed."))
        """
    }

    static func unknown(_ topic: String) -> String {
        """
        \(Style.yellow("Unknown help topic:")) \(topic)

        Try one of: overview, concepts, commands, notes, market, providers, skill, config.
        \(Style.dim("e.g. `rw help notes`"))
        """
    }
}
