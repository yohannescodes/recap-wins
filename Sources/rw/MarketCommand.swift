import ArgumentParser
import Foundation
import RecapCore
import SemanticKit

/// `rw market` — generate a marketing content pack for the new features, in a
/// product's voice (PRD §6, §8). Semantic + product profile.
struct Market: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate a marketing content pack for new features, in a product's voice."
    )

    @OptionGroup var options: ChangeSetOptions

    @Option(name: .long, help: "Product id for voice + links (required).")
    var product: String

    @Option(name: .long, help: "Comma-separated pieces (default: whatsNew,promotionalText,subtitle,shortDescription,post,tweet).")
    var pieces: String?

    @Option(name: .long, help: "Backend: anthropic (API), skill (key-free, emits JSON), gemini (reserved).")
    var provider: String?

    /// Resolve the requested pieces, or the full default pack.
    private func resolvePieces() throws -> [MarketPiece] {
        guard let pieces else { return MarketPiece.allCases }
        var resolved: [MarketPiece] = []
        for raw in pieces.split(separator: ",") {
            let key = raw.trimmingCharacters(in: .whitespaces)
            guard let piece = MarketPiece(rawValue: key) else {
                throw ValidationError(
                    "Unknown piece '\(key)'. Options: "
                    + MarketPiece.allCases.map(\.rawValue).joined(separator: ", ") + ".")
            }
            resolved.append(piece)
        }
        return resolved
    }

    func run() throws {
        let config = try options.loadConfig()
        let report = try options.buildReport(config: config)

        if options.json {
            try emitJSON(report)
            return
        }

        guard let profile = config.product(product) else {
            throw ValidationError("No product '\(product)' in config. Check testthese.toml.")
        }
        let selectedPieces = try resolvePieces()
        let selectedProvider = try resolveProvider(flag: provider, config: config)

        // Skill mode: emit one envelope per piece for the host agent.
        if selectedProvider == .skill {
            if options.wantsHTML {
                throw ValidationError(
                    "--html doesn't apply in skill mode (the host agent renders, "
                    + "not rw). Run without --provider skill, or render the agent's "
                    + "output yourself.")
            }
            let envelopes = SkillEnvelope.forMarket(
                report, pieces: selectedPieces, product: profile, limits: config.marketLimits)
            print(try skillEnvelopesJSON(envelopes))
            return
        }

        let engine = try options.makeSemanticEngine(config: config, provider: selectedProvider)
        let pieces = selectedPieces
        let limits = config.marketLimits
        let wantsHTML = options.wantsHTML
        let htmlOut = options.htmlOut
        let openInBrowser = options.open
        let repoPath = options.repo
        let range = report.range
        try runAsync {
            let results = try await engine.marketPack(
                report, pieces: pieces, product: profile, limits: limits)
            if wantsHTML {
                let html = HTMLRender.market(results, product: profile, limits: limits, range: range)
                try writeHTMLReport(
                    html, command: "market", range: range, repoPath: repoPath,
                    outPath: htmlOut, open: openInBrowser)
            } else {
                print(Render.marketPack(results, product: profile, limits: limits))
            }
            // Surface any cap overflows on stderr — warn, never truncate.
            for r in results where r.overflowWarning != nil {
                FileHandle.standardError.write(Data(("⚠ " + r.overflowWarning! + "\n").utf8))
            }
        }
    }
}
