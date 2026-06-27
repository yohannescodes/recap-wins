import ArgumentParser
import Foundation
import RecapCore
import SemanticKit

/// Root command. With no subcommand, `rw` itself prints the vitals dashboard
/// (PRD §6/§7). Vitals lives on the root rather than as a `defaultSubcommand`
/// because swift-argument-parser doesn't reliably route top-level options to a
/// default subcommand — the root command owns the default behavior directly.
@main
struct RW: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rw",
        abstract: "recap-wins — see what your branch introduced, offline and instant.",
        discussion: "Run `rw help` for the full guide, or `rw help <topic>` "
            + "(concepts, commands, notes, providers, skill, config).",
        version: "0.2.0",
        subcommands: [New.self, Notes.self, Market.self, Many.self, Blame.self, Branch.self, Align.self, Help.self]
    )

    @OptionGroup var options: ChangeSetOptions

    func run() throws {
        let report = try options.buildReport()
        if options.json {
            try emitJSON(report)
        } else if options.wantsHTML {
            try writeHTMLReport(
                HTMLRender.vitals(report),
                command: "vitals", range: report.range, repoPath: options.repo,
                outPath: options.htmlOut, open: options.open)
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
        } else if options.wantsHTML {
            try writeHTMLReport(
                HTMLRender.many(report),
                command: "many", range: report.range, repoPath: options.repo,
                outPath: options.htmlOut, open: options.open)
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
        } else if options.wantsHTML {
            try writeHTMLReport(
                HTMLRender.blame(report),
                command: "blame", range: report.range, repoPath: options.repo,
                outPath: options.htmlOut, open: options.open)
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
        } else if options.wantsHTML {
            try writeHTMLReport(
                HTMLRender.branch(report),
                command: "branch", range: report.range, repoPath: options.repo,
                outPath: options.htmlOut, open: options.open)
        } else {
            print(Render.branch(report))
        }
    }
}
