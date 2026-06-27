import ArgumentParser
import Foundation
import RecapCore
import SemanticKit

/// Flags for `rw align`. Lives in its own ParsableArguments group because
/// argument-parser only reliably propagates `@Flag` defaults to a top-level
/// ParsableCommand when they live in an OptionGroup (matching the pattern
/// every other rw command uses).
struct AlignOptions: ParsableArguments {
    /// `--emit-json` is kept as an alias for one release: earlier versions
    /// exposed only that name because the root command's `--json` flag
    /// shadowed the subcommand's, so users may have scripts on it.
    @Flag(
        name: [.customLong("json"), .customLong("emit-json")],
        help: "Emit the raw AlignReport JSON instead of the formatted view.")
    var emitJSON: Bool = false

    /// Skip the semantic match and emit only the two ledgers (the slice-1
    /// behavior). Useful when you want a deterministic, offline, key-free
    /// look at what each side claims to have, no model in the loop.
    @Flag(name: .customLong("ledger-only"), help: "Skip the matcher; emit only the per-port ledgers.")
    var ledgerOnly: Bool = false

    /// Render the report as a single self-contained, offline HTML file —
    /// the filterable parity matrix (FRD §9.1). Like the other --html flags
    /// across rw, no extra model calls beyond the matcher run.
    ///
    /// `--matrix` and `--page` are kept as aliases for one release: earlier
    /// versions exposed only those names because the root command's `--html`
    /// flag shadowed the subcommand's, so users may have scripts on them.
    @Flag(
        name: [.customLong("html"), .customLong("matrix"), .customLong("page")],
        help: "Render the parity matrix as a self-contained, offline HTML file.")
    var matrix: Bool = false

    /// Override the default HTML output path. Defaults to
    /// `.rw/align-<a>-<b>.html` (same convention as other rw HTML commands).
    @Option(
        name: [.customLong("html-out"), .customLong("matrix-out")],
        help: ArgumentHelp(
            "Output path for --html. Default: .rw/align-<a>-<b>.html.",
            valueName: "path"))
    var matrixOut: String?

    @Flag(
        name: [.customLong("open"), .customLong("open-matrix")],
        help: "Open the generated HTML in the default browser (with --html).")
    var openMatrix: Bool = false

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

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Issue-draft format. Defaults to markdown (the source).",
            valueName: "markdown|linear|github|jira"))
    var issues: String = "markdown"

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Confirm a match by id and append it to testthese.toml as a "
            + "curated parity equivalence. Run align first, find the id, "
            + "then pass it here.",
            valueName: "match-id"))
    var confirm: String?

    @Option(name: .long, help: "Backend: anthropic (API), skill (key-free, emits envelope), gemini.")
    var provider: String?

    @Option(name: .long, help: "Path to read testthese.toml from. Default: current directory.")
    var configRepo: String = FileManager.default.currentDirectoryPath
}

/// `rw align` — compare two ports of the same product and report parity (FRD).
///
/// Unlike every other `rw` command, `align` reads TWO repos with no shared
/// git history. The full FRD-spec command shipped over three slices:
/// (1) per-port feature ledger extraction, (2) the semantic matcher + drafted
/// issues, (3) the filterable HTML parity matrix + `--confirm` loop and
/// tracker-flavored `--issues` formatters.
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
        if IssueFormat.parse(options.issues) == nil {
            let valid = IssueFormat.allCases.map(\.rawValue).joined(separator: ", ")
            throw ValidationError(
                "--issues '\(options.issues)' isn't recognized. Pick one of: \(valid).")
        }
        if options.confirm != nil && options.product == nil {
            throw ValidationError(
                "--confirm requires --product (the curated map lives under a product profile).")
        }
        if options.confirm != nil && options.ledgerOnly {
            throw ValidationError(
                "--confirm needs matcher results; can't combine with --ledger-only.")
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
        // call from rw, no API key required. --html / --confirm don't apply
        // here because rw doesn't see the agent's response — surface a clean
        // error rather than silently producing nothing.
        if provider == .skill {
            if options.matrix {
                throw ValidationError(
                    "--html doesn't apply in skill mode (rw doesn't see the agent's "
                    + "match results). Run without --provider skill, or pipe the "
                    + "agent's reply through --json + a separate render step.")
            }
            if options.confirm != nil {
                throw ValidationError(
                    "--confirm doesn't apply in skill mode (rw doesn't see the "
                    + "agent's match results). Run without --provider skill.")
            }
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
            // --confirm short-circuits the normal emit: find the named match,
            // append it as a curated equivalence, report what happened.
            if let matchID = options.confirm {
                try confirmMatch(matchID, in: report)
                return
            }
            try emit(report: report)
        }
    }

    // MARK: - Emit

    /// Print the report in whichever shape the user asked for.
    private func emit(report: AlignReport) throws {
        if options.matrix {
            let html = HTMLRender.alignReport(report)
            try writeHTMLReport(
                html, command: "align",
                range: ChangeRange(
                    base: report.portA.portName, head: report.portB.portName,
                    baseSHA: report.portA.headSHA, headSHA: report.portB.headSHA,
                    mergeBaseSHA: report.portA.headSHA),
                repoPath: options.configRepo,
                outPath: options.matrixOut, open: options.openMatrix)
            return
        }
        if options.emitJSON {
            print(try report.jsonString())
            return
        }
        print(Render.alignReport(report))
        // When --issues is anything but the default, also emit the formatted
        // drafts after the human view — saves a second `rw align ...` run.
        let format = IssueFormat.parse(options.issues) ?? .markdown
        if format != .markdown && !report.suggestedIssues.isEmpty {
            print("--- issues (\(format.rawValue)) ---\n")
            print(IssueFormatter.formatAll(report.suggestedIssues, as: format))
            print("")
        }
    }

    // MARK: - --confirm

    /// Append the named match as a curated parity equivalence and report.
    /// The match must classify as `equivalent` or `ambiguous` — confirming
    /// an actual paired/gap is meaningless (paired needs no curation; gaps
    /// are gaps, not equivalences).
    private func confirmMatch(_ matchID: String, in report: AlignReport) throws {
        guard let productID = options.product else { return }   // validate() catches this
        guard let match = report.features.first(where: { $0.id == matchID }) else {
            let available = report.features.map(\.id).joined(separator: ", ")
            throw ValidationError(
                "No match with id '\(matchID)' in this run. "
                + "Available ids: \(available.isEmpty ? "(none)" : available).")
        }
        switch match.status {
        case .paired:
            throw ValidationError(
                "match '\(matchID)' is already 'paired' — no equivalence needed.")
        case .gapOnA, .gapOnB:
            throw ValidationError(
                "match '\(matchID)' is a gap, not an equivalence. "
                + "Confirming a gap as equivalent would hide real missing work.")
        case .equivalent, .ambiguous:
            break
        }
        guard let a = match.descriptionA, let b = match.descriptionB else {
            throw ValidationError(
                "match '\(matchID)' is missing one side's description; "
                + "can't write a complete equivalence entry.")
        }

        let configPath = (options.configRepo as NSString)
            .appendingPathComponent("testthese.toml")
        do {
            let outcome = try ParityMapUpdater.append(
                a: a, b: b, note: match.equivalenceNote,
                productId: productID, configPath: configPath)
            switch outcome {
            case .appended:
                print("Added equivalence to \(configPath):")
                print("  a = \"\(a)\"")
                print("  b = \"\(b)\"")
                if let note = match.equivalenceNote, !note.isEmpty {
                    print("  note = \"\(note)\"")
                }
                print("It won't be re-flagged on the next align run.")
            case .alreadyPresent:
                print("Already in \(configPath): \"\(a)\" ↔ \"\(b)\".")
                print("No change made.")
            }
        } catch let err as ParityMapError {
            throw ValidationError(err.description)
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
