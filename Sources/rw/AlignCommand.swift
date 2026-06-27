import ArgumentParser
import Foundation
import RecapCore
import SemanticKit

/// Flags for `rw align`. Lives in its own ParsableArguments group because
/// argument-parser only reliably propagates `@Flag` defaults to a top-level
/// ParsableCommand when they live in an OptionGroup (matching the pattern
/// every other rw command uses).
struct AlignOptions: ParsableArguments {
    /// Named `--emit-json` (not `--json`) because the root `rw` command
    /// already has a `--json` flag (for the vitals report), and
    /// swift-argument-parser resolves the parent's flag first when both
    /// declare the same long name. The FRD §4 flag table calls it `--json`,
    /// but the parent-name collision makes that ambiguous in practice;
    /// `--emit-json` is unambiguous and reads cleanly as "emit the AlignReport
    /// JSON". RELEASING.md and GUIDE.md document the discrepancy.
    @Flag(name: .customLong("emit-json"), help: "Emit the raw AlignReport JSON instead of the formatted view.")
    var emitJSON: Bool = false

    /// Skip the semantic match and emit only the two ledgers (the slice-1
    /// behavior). Useful when you want a deterministic, offline, key-free
    /// look at what each side claims to have, no model in the loop.
    @Flag(name: .customLong("ledger-only"), help: "Skip the matcher; emit only the per-port ledgers.")
    var ledgerOnly: Bool = false

    @Option(name: .long, help: "Product id with a configured port pair (testthese.toml).")
    var product: String?

    @Option(
        name: .long,
        help: "Side B repo path; the current repo becomes side A.")
    var with: String?

    @Option(name: .customLong("a"), help: "Side A repo path (explicit pair mode).")
    var a: String?

    @Option(name: .customLong("b"), help: "Side B repo path (explicit pair mode).")
    var b: String?

    @Option(name: .customLong("base-a"), help: "Ref to read on side A. Default: configured/main.")
    var baseA: String?

    @Option(name: .customLong("base-b"), help: "Ref to read on side B. Default: configured/main.")
    var baseB: String?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Baseline ref both sides use. Only features added since this point "
            + "are considered. Recommended: a port-start tag.",
            valueName: "ref"))
    var since: String?

    @Option(name: .long, help: "Backend: anthropic (API), skill (key-free, emits envelope), gemini.")
    var provider: String?

    @Option(name: .long, help: "Path to read testthese.toml from. Default: current directory.")
    var configRepo: String = FileManager.default.currentDirectoryPath
}

/// `rw align` — compare two ports of the same product and report parity (FRD).
///
/// Unlike every other `rw` command, `align` reads TWO repos with no shared
/// git history. Slice 1 built the deterministic ledger half; slice 2 (this
/// PR) adds the semantic matcher and tracker-agnostic issue drafts; slice 3
/// will add the HTML parity matrix and the curated-map confirmation loop.
struct Align: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Compare two ports of the same product and report parity gaps."
    )

    @OptionGroup var options: AlignOptions

    func validate() throws {
        let modes = [
            options.product != nil,
            options.with != nil,
            (options.a != nil && options.b != nil),
        ]
        let chosen = modes.filter { $0 }.count
        if chosen == 0 {
            throw ValidationError(
                "Pick a mode: --product <id>, --with <path>, or --a <path> --b <path>.")
        }
        if chosen > 1 {
            throw ValidationError(
                "These modes are exclusive — pass exactly one of --product, --with, or --a/--b.")
        }
        if (options.a != nil) != (options.b != nil) {
            throw ValidationError("--a and --b must be provided together.")
        }
    }

    func run() throws {
        let pair = try resolvePortPair()
        let baseline = options.since ?? pair.since

        let config = try Config.load(fromRepo: options.configRepo)
        let profile: ProductProfile? = options.product.flatMap { config.product($0) }

        let ledgerA = try buildLedger(port: pair.a, base: options.baseA, since: baseline)
        let ledgerB = try buildLedger(port: pair.b, base: options.baseB, since: baseline)

        let equivalences = EquivalenceTable.merged(
            with: profile?.parityEquivalent ?? [])

        // Ledger-only mode: deterministic, key-free, no model call.
        if options.ledgerOnly {
            let report = AlignReport(
                product: options.product,
                portA: ledgerA, portB: ledgerB, since: baseline,
                features: [], summary: AlignSummary(), suggestedIssues: [],
                generatedBy: "ledger-only",
                disclaimer: AlignReport.standardDisclaimer)
            try emit(report: report)
            return
        }

        let provider = try resolveProvider(flag: options.provider, config: config)

        // Skill mode: hand the envelope to the host agent and exit. No model
        // call from rw, no API key required.
        if provider == .skill {
            let envelope = SkillEnvelope.forAlign(
                ledgerA: ledgerA, ledgerB: ledgerB,
                equivalences: equivalences,
                product: profile, productId: options.product,
                since: baseline)
            print(try envelope.jsonString())
            return
        }

        // API providers: run the matcher.
        let engine = try makeAlignEngine(config: config, provider: provider)
        let productName = profile?.name
        let productId = options.product
        try runAsync {
            let result = try await engine.alignFeatures(
                ledgerA: ledgerA, ledgerB: ledgerB,
                equivalences: equivalences, productName: productName)
            let report = AlignReport(
                product: productId,
                portA: ledgerA, portB: ledgerB,
                since: baseline,
                features: result.features,
                summary: AlignSummary.from(result.features),
                suggestedIssues: result.issues,
                generatedBy: provider.rawValue,
                disclaimer: AlignReport.standardDisclaimer)
            try emit(report: report)
        }
    }

    // MARK: - Emit

    /// Print the report in whichever shape the user asked for.
    private func emit(report: AlignReport) throws {
        if options.emitJSON {
            print(try report.jsonString())
        } else {
            print(Render.alignReport(report))
        }
    }

    // MARK: - Port-pair resolution

    /// Turn whichever mode the user picked into a concrete `PortPair`.
    /// Validation already ensured exactly one mode is active.
    private func resolvePortPair() throws -> PortPair {
        if let product = options.product {
            let config = try Config.load(fromRepo: options.configRepo)
            guard let profile = config.product(product) else {
                throw ValidationError("No product '\(product)' in config. Check testthese.toml.")
            }
            guard let pair = profile.ports else {
                throw ValidationError(
                    "Product '\(product)' has no [product.ports] block in config. "
                    + "Add one, or pass --a/--b explicitly.")
            }
            return pair
        }
        if let with = options.with {
            let cwd = FileManager.default.currentDirectoryPath
            return PortPair(
                a: PortRef(name: "a", path: cwd, base: options.baseA ?? "main"),
                b: PortRef(name: "b", path: with, base: options.baseB ?? "main"),
                since: options.since)
        }
        // --a/--b — validate already ensured both are set.
        return PortPair(
            a: PortRef(name: "a", path: options.a!, base: options.baseA ?? "main"),
            b: PortRef(name: "b", path: options.b!, base: options.baseB ?? "main"),
            since: options.since)
    }

    /// Build one side's ledger, honoring per-side base overrides.
    private func buildLedger(port: PortRef, base: String?, since: String?) throws -> LedgerSnapshot {
        let ref = base ?? port.base
        let git = Git(repositoryPath: port.path)
        let builder = LedgerBuilder(git: git)
        do {
            return try builder.build(portName: port.name, ref: ref, since: since)
        } catch let error as GitError {
            // Surface git errors with the port name attached so the user knows
            // which side failed — a common mistake is pointing at the wrong path.
            throw ValidationError("[\(port.name)] \(error.description)")
        }
    }

    /// Build a SemanticEngine for the API providers, mapping common config
    /// errors to clean ValidationError exits rather than stack traces.
    private func makeAlignEngine(config: Config, provider: Provider) throws -> SemanticEngine {
        do {
            let client = try ModelConfig.makeClient(for: provider, config: config)
            return SemanticEngine(client: client)
        } catch let error as ModelError {
            throw ValidationError(error.description)
        } catch let error as ProviderUnavailable {
            throw ValidationError(error.description)
        }
    }
}
