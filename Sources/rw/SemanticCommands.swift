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
            print(try SkillEnvelope.forNewFeatures(report).jsonString())
            return
        }

        let engine = try options.makeSemanticEngine(config: config, provider: provider)
        try runAsync {
            let features = try await engine.newFeatures(report)
            print(features)
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

    @Option(name: .long, help: "Product id for voice + platform (required for store targets).")
    var product: String?

    @Option(name: .long, help: "Tighten the char limit below the store ceiling (never loosens past it).")
    var limit: Int?

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
        return t
    }

    func validate() throws {
        let targets = selectedTargets
        guard !targets.isEmpty else {
            throw ValidationError(
                "Pick a target: --pr, --asc-reviewer, --what-new, --asc-update, or --gp-update."
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
        try runAsync {
            let resolved = try await resolveLimit(
                config: config, target: target, profile: profile,
                userLimit: limitOption, refresh: refresh)
            let result = try await engine.note(report, target: target, product: profile, limit: resolved)
            print(result.text)
            if let warning = result.overflowWarning {
                FileHandle.standardError.write(Data(("\n⚠ " + warning + "\n").utf8))
            }
        }
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
