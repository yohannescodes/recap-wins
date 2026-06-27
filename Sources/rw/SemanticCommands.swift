import ArgumentParser
import Foundation
import RecapCore
import SemanticKit

/// `rw new` — list the new user-facing features introduced (PRD §6).
/// Semantic: in API mode the provider filters chores/refactors and writes the
/// list; in skill mode `rw` emits a JSON envelope for the host agent to write it.
struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the new features you introduced, filtering out chores/refactors."
    )

    @OptionGroup var options: ChangeSetOptions

    @Option(name: .long, help: "Backend: anthropic (API), skill (key-free, emits JSON), gemini (reserved).")
    var provider: String?

    func run() throws {
        let config = try options.loadConfig()
        let report = try options.buildReport(config: config)

        if options.json {
            try emitJSON(report)
            return
        }

        let provider = try resolveProvider(flag: provider, config: config)

        // Skill mode: emit the envelope for the host agent; no API call.
        if provider == .skill {
            if options.wantsHTML {
                throw ValidationError(
                    "--html doesn't apply in skill mode (the host agent renders, "
                    + "not rw). Run without --provider skill, or render the agent's "
                    + "output yourself.")
            }
            print(try SkillEnvelope.forNewFeatures(report).jsonString())
            return
        }

        let engine = try options.makeSemanticEngine(config: config, provider: provider)
        let wantsHTML = options.wantsHTML
        let htmlOut = options.htmlOut
        let openInBrowser = options.open
        let repoPath = options.repo
        let range = report.range
        try runAsync {
            let features = try await engine.newFeatures(report)
            if wantsHTML {
                let html = HTMLRender.newFeatures(features, range: range)
                try writeHTMLReport(
                    html, command: "new", range: range, repoPath: repoPath,
                    outPath: htmlOut, open: openInBrowser)
            } else {
                print(features)
            }
        }
    }
}

/// `rw notes` — write a review/release note for a chosen target (PRD §6.1).
/// One required target flag picks the destination; caps are enforced per target.
struct Notes: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Write a review/release note for a chosen target."
    )

    @OptionGroup var options: ChangeSetOptions

    @Flag(name: .long, help: "PR description (technical, uncapped).")
    var pr: Bool = false

    @Flag(name: .customLong("asc-reviewer"), help: "App Store Connect → App Review notes (private).")
    var ascReviewer: Bool = false

    @Flag(name: .customLong("what-new"), help: "TestFlight / Play testing notes (platform-aware length).")
    var whatNew: Bool = false

    @Flag(name: .customLong("asc-update"), help: "App Store \"What's New\" (4000 cap).")
    var ascUpdate: Bool = false

    @Flag(name: .customLong("gp-update"), help: "Google Play release notes (500/lang cap).")
    var gpUpdate: Bool = false

    @Flag(name: .long, help: "Release-page changelog (HTML-only artifact; see RELEASING.md).")
    var changelog: Bool = false

    @Option(name: .long, help: "Product id for voice + platform (required for store targets).")
    var product: String?

    @Option(name: .long, help: "Tighten the char limit below the store ceiling (never loosens past it).")
    var limit: Int?

    @Option(
        name: .customLong("version-label"),
        help: ArgumentHelp(
            "Version label shown as the changelog page title (e.g. v0.2.0). "
            + "Defaults to the head ref or short SHA.",
            valueName: "label"))
    var versionLabel: String?

    @Flag(name: .long, help: "Force a refresh of the cached store-limit manifest now.")
    var refreshLimits: Bool = false

    @Option(name: .long, help: "Backend: anthropic (API), skill (key-free, emits JSON), gemini (reserved).")
    var provider: String?

    /// Which targets the user selected.
    private var selectedTargets: [NoteTarget] {
        var t: [NoteTarget] = []
        if pr { t.append(.pr) }
        if ascReviewer { t.append(.ascReviewer) }
        if whatNew { t.append(.whatNew) }
        if ascUpdate { t.append(.ascUpdate) }
        if gpUpdate { t.append(.gpUpdate) }
        if changelog { t.append(.changelog) }
        return t
    }

    func validate() throws {
        let targets = selectedTargets
        guard !targets.isEmpty else {
            throw ValidationError(
                "Pick a target: --pr, --asc-reviewer, --what-new, --asc-update, --gp-update, or --changelog."
            )
        }
        guard targets.count == 1 else {
            throw ValidationError("Pick exactly one target, not \(targets.count).")
        }
        if let limit, limit <= 0 {
            throw ValidationError("--limit must be a positive number of characters.")
        }
    }

    func run() throws {
        let target = selectedTargets[0]
        let config = try options.loadConfig()
        let report = try options.buildReport(config: config)

        if options.json {
            try emitJSON(report)
            return
        }

        // Resolve the product profile; user-facing targets need one for voice.
        let profile = product.flatMap { config.product($0) }
        if target.requiresProduct {
            if product == nil {
                throw ValidationError(
                    "\(target.displayName) is user-facing — pass --product <id> so it's in the product's voice."
                )
            }
            if profile == nil {
                throw ValidationError("No product '\(product!)' in config. Check testthese.toml.")
            }
        }

        let selectedProvider = try resolveProvider(flag: provider, config: config)
        let limitOption = limit
        let refresh = refreshLimits

        // Skill mode emits the envelope; API providers call the model. Both need
        // the resolved limit, so compute it first (limits fetch may be async).
        if selectedProvider == .skill {
            if options.wantsHTML {
                throw ValidationError(
                    "--html doesn't apply in skill mode (the host agent renders, "
                    + "not rw). Run without --provider skill, or render the agent's "
                    + "output yourself.")
            }
            try runAsync {
                let resolved = try await resolveLimit(
                    config: config, target: target, profile: profile,
                    userLimit: limitOption, refresh: refresh)
                let envelope = SkillEnvelope.forNote(
                    report, target: target, product: profile, limit: resolved)
                print(try envelope.jsonString())
            }
            return
        }

        let engine = try options.makeSemanticEngine(config: config, provider: selectedProvider)
        // --changelog is HTML-only: the page IS the artifact, not a preview.
        // It also defaults its output path under docs/changelogs/ so per-version
        // pages end up in the canonical spot for committing.
        let wantsHTML = options.wantsHTML || target.isHTMLOnly
        let htmlOut = resolvedHTMLOut(target: target)
        let openInBrowser = options.open
        let repoPath = options.repo
        let range = report.range
        let versionLabelCopy = changelogVersionLabel(report: report)
        try runAsync {
            let resolved = try await resolveLimit(
                config: config, target: target, profile: profile,
                userLimit: limitOption, refresh: refresh)
            let result = try await engine.note(report, target: target, product: profile, limit: resolved)
            if wantsHTML {
                let html: String
                let commandLabel: String
                if target == .changelog {
                    html = HTMLRender.changelog(
                        result.text, version: versionLabelCopy, range: range)
                    commandLabel = "changelog"
                } else {
                    html = HTMLRender.notes(
                        result.text, target: target, limit: resolved,
                        product: profile, range: range)
                    commandLabel = "notes-\(target.rawValue)"
                }
                try writeHTMLReport(
                    html, command: commandLabel, range: range,
                    repoPath: repoPath, outPath: htmlOut, open: openInBrowser)
            } else {
                print(result.text)
            }
            if let warning = result.overflowWarning {
                FileHandle.standardError.write(Data(("\n⚠ " + warning + "\n").utf8))
            }
        }
    }

    /// For --changelog without an explicit --html-out, default to
    /// `docs/changelogs/<version-label>.html` so per-version pages land in the
    /// canonical spot for committing. Other targets keep the standard default.
    private func resolvedHTMLOut(target: NoteTarget) -> String? {
        if let override = options.htmlOut { return override }
        guard target == .changelog else { return nil }
        let label = (versionLabel ?? "").trimmingCharacters(in: .whitespaces)
        // No version label: let writeHTMLReport pick its default name (which
        // uses the change range) under .rw/. Better than guessing a version.
        guard !label.isEmpty else { return nil }
        return "docs/changelogs/\(label).html"
    }

    /// The label for the changelog page title. Prefer the user's --version-label,
    /// then the head ref name, then the short SHA — there's always something.
    private func changelogVersionLabel(report: ChangeReport) -> String {
        if let label = versionLabel?.trimmingCharacters(in: .whitespaces), !label.isEmpty {
            return label
        }
        if report.range.head != "HEAD" { return report.range.head }
        return String(report.range.headSHA.prefix(7))
    }
}

/// Resolve the effective limit for a notes render: fetch ceilings (cached),
/// combine with the product's soft target and any `--limit` tightening.
private func resolveLimit(
    config: Config,
    target: NoteTarget,
    profile: ProductProfile?,
    userLimit: Int?,
    refresh: Bool
) async throws -> ResolvedLimit {
    let limitsProvider = LimitsProvider(config: config)
    let ceilings = await limitsProvider.limits(forceRefresh: refresh)
    return ResolvedLimit.resolve(
        target: target,
        platform: profile?.platform ?? .iOS,
        limits: ceilings,
        softTarget: profile?.softTarget(for: target),
        userLimit: userLimit
    )
}
