import Foundation
import RecapCore

/// Minimal ANSI styling for the terminal views. Honors `NO_COLOR` and skips
/// color when stdout isn't a TTY (e.g. piped to a file).
enum Style {
    static let enabled: Bool = {
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
        return isatty(fileno(stdout)) == 1
    }()

    static func wrap(_ text: String, _ code: String) -> String {
        enabled ? "\u{1b}[\(code)m\(text)\u{1b}[0m" : text
    }

    static func bold(_ t: String) -> String { wrap(t, "1") }
    static func dim(_ t: String) -> String { wrap(t, "2") }
    static func green(_ t: String) -> String { wrap(t, "32") }
    static func red(_ t: String) -> String { wrap(t, "31") }
    static func yellow(_ t: String) -> String { wrap(t, "33") }
    static func cyan(_ t: String) -> String { wrap(t, "36") }
}

/// Renders the vitals dashboard (PRD §7) and the smaller command views.
enum Render {
    /// The default `rw` vitals dashboard.
    static func vitals(_ report: ChangeReport) -> String {
        let v = report.vitals
        var lines: [String] = []

        let head = report.range.head == "HEAD"
            ? report.range.headSHA.prefix(7).description
            : report.range.head
        lines.append(Style.bold("recap-wins") + Style.dim("  \(report.range.base)…\(head)"))
        lines.append("")

        // Headline counts.
        let counts = [
            Style.green("\(v.features) ") + Style.dim("features"),
            Style.cyan("\(v.fixes) ") + Style.dim("fixes"),
            Style.dim("\(v.chores) chores"),
        ].joined(separator: Style.dim("  ·  "))
        lines.append("  " + counts)

        // Diff stats.
        let diff = "\(v.filesChanged) files  "
            + Style.green("+\(v.insertions)") + "  "
            + Style.red("-\(v.deletions)")
        lines.append("  " + Style.dim(diff))

        // Contributors & branches.
        if !v.contributors.isEmpty {
            let names = v.contributors.prefix(4)
                .map { "\($0.name) (\($0.commitCount))" }
                .joined(separator: ", ")
            let extra = v.contributors.count > 4 ? ", …" : ""
            lines.append("  " + Style.dim("contributors: ") + names + extra)
        }
        lines.append("  " + Style.dim("branches involved: ") + "\(v.branchCount)")

        // Hotspots.
        if !v.hotspots.isEmpty {
            lines.append("")
            lines.append("  " + Style.bold("Hotspots"))
            for f in v.hotspots {
                let churn = Style.green("+\(f.insertions)") + "/" + Style.red("-\(f.deletions)")
                lines.append("    " + pad("\(f.churn)", 5) + Style.dim("  ") + f.path + "  " + Style.dim(churn))
            }
        }

        // Risk flags.
        if !report.riskFlags.isEmpty {
            lines.append("")
            lines.append("  " + Style.yellow("⚠ Risk flags") + Style.dim("  (advisory)"))
            for flag in report.riskFlags {
                lines.append("    " + Style.yellow("•") + " " + flag.message)
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// `rw many` — counts + breakdown by precise conventional-commit type.
    static func many(_ report: ChangeReport) -> String {
        let work = report.commits.filter { !$0.isMerge }
        var byType: [CommitType: Int] = [:]
        for c in work { byType[c.type, default: 0] += 1 }

        let v = report.vitals
        var lines: [String] = []
        lines.append(Style.bold("Introduced in this change set"))
        lines.append("")
        lines.append("  " + Style.green("\(v.features)") + " features   "
            + Style.cyan("\(v.fixes)") + " fixes   "
            + Style.dim("\(v.chores) chores"))
        lines.append("")
        lines.append("  " + Style.dim("By type"))
        for type in CommitType.allCases {
            let n = byType[type] ?? 0
            if n == 0 { continue }
            lines.append("    " + pad("\(n)", 4) + "  " + type.rawValue)
        }
        let merges = report.commits.count - work.count
        if merges > 0 {
            lines.append("    " + pad("\(merges)", 4) + "  " + Style.dim("merges (excluded from counts)"))
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// `rw blame` — attribution by contributor.
    static func blame(_ report: ChangeReport) -> String {
        var lines: [String] = []
        lines.append(Style.bold("Attribution") + Style.dim("  (\(report.commits.count) commits)"))
        lines.append("")
        let total = max(report.vitals.contributors.reduce(0) { $0 + $1.commitCount }, 1)
        for c in report.vitals.contributors {
            let pct = Int((Double(c.commitCount) / Double(total) * 100).rounded())
            lines.append("  " + pad("\(c.commitCount)", 4) + "  "
                + pad("\(pct)%", 5) + "  "
                + c.name + Style.dim("  <\(c.email)>"))
        }
        if report.vitals.contributors.isEmpty {
            lines.append("  " + Style.dim("no non-merge commits in this change set"))
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// `rw branch` — branches that contributed to this change set.
    static func branch(_ report: ChangeReport) -> String {
        var lines: [String] = []
        lines.append(Style.bold("Branches in this change set"))
        lines.append("")
        for b in report.branches {
            let marker = b.isHead ? Style.green("● ") : Style.dim("○ ")
            let headTag = b.isHead ? Style.dim("  (head)") : ""
            lines.append("  " + marker + b.name + Style.dim("  \(b.commitCount) commits") + headTag)
        }
        if report.branches.isEmpty {
            lines.append("  " + Style.dim("none"))
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Right-pad a string to a fixed width (left-aligned numbers read cleanly).
    private static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }
}
