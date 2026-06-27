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

    @Option(name: .long, help: "Path to read testthese.toml from. Default: current directory.")
    var configRepo: String = FileManager.default.currentDirectoryPath
}

/// `rw align` — compare two ports of the same product and report parity (FRD).
///
/// Unlike every other `rw` command, `align` reads TWO repos with no shared
/// git history. Slice 1 (this PR) builds a deterministic ledger of each
/// side's feature claims and emits the structured report; the semantic
/// match between them lands in slice 2.
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

        let ledgerA = try buildLedger(port: pair.a, base: options.baseA, since: baseline)
        let ledgerB = try buildLedger(port: pair.b, base: options.baseB, since: baseline)

        let report = AlignReport(
            product: options.product,
            portA: ledgerA,
            portB: ledgerB,
            since: baseline,
            features: [],
            summary: AlignSummary(),
            suggestedIssues: [],
            generatedBy: "",
            disclaimer: AlignReport.standardDisclaimer
        )

        if options.emitJSON {
            print(try report.jsonString())
            return
        }
        // Slice 1: the matcher isn't built yet. Tell the user honestly rather
        // than printing a misleading "0 gaps" view (FRD §11 "False confidence
        // is the cardinal risk"). They can still pipe --json to see the
        // ledgers themselves.
        print(slice1Notice(report: report))
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

    // MARK: - Slice 1 notice

    /// Honest "match not yet implemented" text — never asserts parity.
    private func slice1Notice(report: AlignReport) -> String {
        var lines: [String] = []
        lines.append(Style.bold("rw align") + Style.dim("  preview — match arrives in slice 2"))
        lines.append("")
        lines.append("  " + Style.dim("side a (\(report.portA.portName)): ")
            + "\(report.portA.features.count) feature claims @ "
            + String(report.portA.headSHA.prefix(7)))
        lines.append("  " + Style.dim("side b (\(report.portB.portName)): ")
            + "\(report.portB.features.count) feature claims @ "
            + String(report.portB.headSHA.prefix(7)))
        if let since = report.since {
            lines.append("  " + Style.dim("since: ") + since)
        }
        lines.append("")
        lines.append("  " + Style.yellow("Slice 1 of 3: ledger extraction only."))
        lines.append("  " + Style.dim("The semantic matcher (paired / equivalent / gap / ambiguous)"))
        lines.append("  " + Style.dim("ships in the next PR. Run with --emit-json to see the ledgers."))
        lines.append("")
        lines.append("  " + Style.dim(report.disclaimer))
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
