import ArgumentParser
import Foundation
import RecapCore

/// Flags shared across every command (PRD §6): `--base`, `--head`, `--json`,
/// and the repository path.
struct ChangeSetOptions: ParsableArguments {
    @Option(name: .long, help: "Base ref to diff against. Default: main.")
    var base: String = "main"

    @Option(name: .long, help: "Head ref. Default: HEAD (current branch).")
    var head: String = "HEAD"

    @Option(name: .long, help: "Path to the git repository. Default: current directory.")
    var repo: String = FileManager.default.currentDirectoryPath

    @Flag(name: .long, help: "Emit the raw change_report.json instead of the formatted view.")
    var json: Bool = false

    /// Build the change report for the requested change set.
    func buildReport() throws -> ChangeReport {
        let git = Git(repositoryPath: repo)
        let builder = ChangeReportBuilder(git: git)
        return try builder.build(base: base, head: head)
    }
}

/// Print a report as raw JSON to stdout. Shared by every command's `--json` path.
func emitJSON(_ report: ChangeReport) throws {
    print(try report.jsonString())
}
