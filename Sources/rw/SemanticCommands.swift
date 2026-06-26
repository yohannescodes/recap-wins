import ArgumentParser
import Foundation
import RecapCore
import SemanticKit

/// `rw new` — list the new user-facing features introduced (PRD §6).
/// Semantic: calls the Anthropic API to filter chores/refactors out of the
/// change set and report only genuine features.
struct New: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the new features you introduced, filtering out chores/refactors."
    )

    @OptionGroup var options: ChangeSetOptions

    func run() throws {
        let config = try options.loadConfig()
        let report = try options.buildReport(config: config)

        if options.json {
            try emitJSON(report)
            return
        }

        let engine = try options.makeSemanticEngine(config: config)
        try runAsync {
            let features = try await engine.newFeatures(report)
            print(features)
        }
    }
}

/// `rw notes` — write a review/release note for a chosen target (PRD §6.1).
/// This pass implements `--pr`; store targets follow.
struct Notes: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Write a review/release note for a chosen target."
    )

    @OptionGroup var options: ChangeSetOptions

    @Flag(name: .long, help: "Write a pull request description (technical, uncapped).")
    var pr: Bool = false

    func validate() throws {
        // Exactly one target required. Only --pr exists this pass; the others
        // (--asc-reviewer, --what-new, --asc-update, --gp-update) land next.
        guard pr else {
            throw ValidationError(
                "Pick a target. This build supports --pr "
                + "(store targets --asc-update/--gp-update/--what-new/--asc-reviewer are coming)."
            )
        }
    }

    func run() throws {
        let config = try options.loadConfig()
        let report = try options.buildReport(config: config)

        if options.json {
            try emitJSON(report)
            return
        }

        let engine = try options.makeSemanticEngine(config: config)
        try runAsync {
            let note = try await engine.pullRequestNote(report)
            print(note)
        }
    }
}
