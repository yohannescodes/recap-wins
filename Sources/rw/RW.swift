import ArgumentParser
import Foundation
import RecapCore

/// Root command. With no subcommand, `rw` itself prints the vitals dashboard
/// (PRD §6/§7). Vitals lives on the root rather than as a `defaultSubcommand`
/// because swift-argument-parser doesn't reliably route top-level options to a
/// default subcommand — the root command owns the default behavior directly.
@main
struct RW: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rw",
        abstract: "recap-wins — see what your branch introduced, offline and instant.",
        version: "0.1.0",
        subcommands: [Many.self, Blame.self, Branch.self]
    )

    @OptionGroup var options: ChangeSetOptions

    func run() throws {
        let report = try options.buildReport()
        if options.json {
            try emitJSON(report)
        } else {
            print(Render.vitals(report))
        }
    }
}

/// `rw many` — deterministic counts of features / fixes / chores (PRD §6).
/// Semantic dedup is deferred to Phase 1; this is conventional-commit counts.
struct Many: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Count distinct features / fixes / chores introduced."
    )

    @OptionGroup var options: ChangeSetOptions

    func run() throws {
        let report = try options.buildReport()
        if options.json {
            try emitJSON(report)
        } else {
            print(Render.many(report))
        }
    }
}

/// `rw blame` — attribution across the change set (PRD §6).
struct Blame: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Attribute who changed what across the change set."
    )

    @OptionGroup var options: ChangeSetOptions

    func run() throws {
        let report = try options.buildReport()
        if options.json {
            try emitJSON(report)
        } else {
            print(Render.blame(report))
        }
    }
}

/// `rw branch` — branches that contributed commits (PRD §6).
struct Branch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show which branches contributed commits to this change set."
    )

    @OptionGroup var options: ChangeSetOptions

    func run() throws {
        let report = try options.buildReport()
        if options.json {
            try emitJSON(report)
        } else {
            print(Render.branch(report))
        }
    }
}
