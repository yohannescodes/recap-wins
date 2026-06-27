import ArgumentParser
import Foundation
import RecapCore

/// Git-range inputs (`--base`, `--head`, `--repo`). Kept separate from the
/// output flags below so the root `rw` command can mount these without also
/// mounting `--html` / `--json` — if it did, swift-argument-parser would
/// resolve those parent-level names first when subcommands like `align`
/// declare the same long name, and the subcommand's flag would silently
/// never fire.
struct GitRangeOptions: ParsableArguments {
    @Option(name: .long, help: "Base ref to diff against. Default: main.")
    var base: String = "main"

    @Option(name: .long, help: "Head ref. Default: HEAD (current branch).")
    var head: String = "HEAD"

    @Option(name: .long, help: "Path to the git repository. Default: current directory.")
    var repo: String = FileManager.default.currentDirectoryPath

    /// Build the change report for the requested change set.
    func buildReport() throws -> ChangeReport {
        let git = Git(repositoryPath: repo)
        let builder = ChangeReportBuilder(git: git)
        return try builder.build(base: base, head: head)
    }
}

/// Output flags (`--json`, `--html`, `--html-out`, `--open`) used by every
/// subcommand that produces a change-set report. Lives separately from
/// `GitRangeOptions` so the root command can take the range inputs without
/// inheriting these names — see `GitRangeOptions` for why that matters.
struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Emit the raw change_report.json instead of the formatted view.")
    var json: Bool = false

    /// Render to a self-contained, offline HTML file (FRD §9.1). Writes to
    /// `.rw/<command>-<range>.html` by default; override with `--html-out`.
    @Flag(name: .long, help: "Render the report to a single self-contained, offline HTML file.")
    var html: Bool = false

    /// Override the default output path. Implies `--html` if the user forgets it.
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Output path for --html. Default: .rw/<command>-<range>.html.",
            valueName: "path"))
    var htmlOut: String?

    @Flag(name: .long, help: "Open the generated HTML in the default browser (with --html).")
    var open: Bool = false

    /// True if the user wants HTML output (either flag set, or a path given).
    var wantsHTML: Bool { html || htmlOut != nil }
}

/// The full per-subcommand flag set: git range inputs plus output flags.
/// Subcommands use this directly; the root command uses only `GitRangeOptions`
/// (with a dedicated `Vitals` subcommand for the JSON / HTML paths).
struct ChangeSetOptions: ParsableArguments {
    @OptionGroup var range: GitRangeOptions
    @OptionGroup var output: OutputOptions

    var base: String { range.base }
    var head: String { range.head }
    var repo: String { range.repo }
    var json: Bool { output.json }
    var html: Bool { output.html }
    var htmlOut: String? { output.htmlOut }
    var open: Bool { output.open }
    var wantsHTML: Bool { output.wantsHTML }

    func buildReport() throws -> ChangeReport { try range.buildReport() }
}

/// Print a report as raw JSON to stdout. Shared by every command's `--json` path.
func emitJSON(_ report: ChangeReport) throws {
    print(try report.jsonString())
}

/// Write a self-contained HTML render to disk, print the path, and optionally
/// open it. Default location is `<repo>/.rw/<command>-<short-range>.html`.
///
/// `outPath` is `--html-out` when the user gave one; otherwise the default
/// path under `.rw/` is used. Absolute paths are honored verbatim; relative
/// paths resolve against `repoPath`.
func writeHTMLReport(
    _ html: String,
    command: String,
    range: ChangeRange,
    repoPath: String,
    outPath: String?,
    open: Bool
) throws {
    let resolved = resolveHTMLPath(
        requested: outPath, command: command, range: range, repoPath: repoPath)
    let url = URL(fileURLWithPath: resolved)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    try html.write(to: url, atomically: true, encoding: .utf8)
    print(resolved)
    if open {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [resolved]
        try? task.run()
    }
}

/// Resolve the output path for `--html`. An empty/`nil` requested path falls
/// back to `.rw/<command>-<base>..<short-head>.html` under the repo root, which
/// is what most users want and keeps the file out of the project's main tree.
private func resolveHTMLPath(
    requested: String?,
    command: String,
    range: ChangeRange,
    repoPath: String
) -> String {
    if let requested, !requested.isEmpty {
        if requested.hasPrefix("/") { return requested }
        return (repoPath as NSString).appendingPathComponent(requested)
    }
    let safeBase = sanitizeForFilename(range.base)
    let head = range.head == "HEAD" ? String(range.headSHA.prefix(7)) : sanitizeForFilename(range.head)
    let filename = "\(command)-\(safeBase)..\(head).html"
    let dir = (repoPath as NSString).appendingPathComponent(".rw")
    return (dir as NSString).appendingPathComponent(filename)
}

/// Make a git ref safe for a filename — replace anything outside `[A-Za-z0-9._-]`
/// with `-` so a slash-bearing ref like `origin/main` doesn't create a directory.
private func sanitizeForFilename(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for ch in s {
        if ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-" {
            out.append(ch)
        } else {
            out.append("-")
        }
    }
    return out
}
