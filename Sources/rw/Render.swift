import Foundation
import RecapCore
import SemanticKit

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

        // When some counts came from inference (not declared conventional-commit
        // prefixes), say so — the number isn't purely from declared types.
        if v.inferredCount > 0 {
            lines.append("  " + Style.dim("(\(v.inferredCount) inferred from message/diff — not conventional commits)"))
        }

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
        if v.inferredCount > 0 {
            lines.append("  " + Style.dim("(\(v.inferredCount) inferred from message/diff — not conventional commits)"))
        }
        lines.append("")
        lines.append("  " + Style.dim("By declared type"))
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

    /// `rw market` — the rendered content pack.
    static func marketPack(
        _ results: [MarketPieceResult],
        product: ProductProfile,
        limits: MarketLimits
    ) -> String {
        var lines: [String] = []
        lines.append(Style.bold("Marketing pack") + Style.dim("  \(product.name)"))
        for r in results {
            lines.append("")
            // Title, with the char count and (if any) the cap.
            let ceiling = r.piece.ceiling(limits)
            let count = ceiling > 0
                ? Style.dim("  \(r.text.count)/\(ceiling) chars")
                : Style.dim("  \(r.text.count) chars")
            let warn = r.overflowWarning != nil ? Style.yellow("  ⚠ over cap") : ""
            lines.append("  " + Style.bold(r.piece.title) + count + warn)
            // The copy itself, indented.
            for line in r.text.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("    " + String(line))
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// `rw align` — the parity read: headline counts, then gaps, then
    /// ambiguous items, then drafted issues, then the mandatory disclaimer.
    /// Leads with the FRD framing that this is candidates to confirm, never
    /// authoritative parity.
    static func alignReport(_ report: AlignReport) -> String {
        var lines: [String] = []
        let head = "\(report.portA.portName)…\(report.portB.portName)"
        lines.append(Style.bold("rw align") + Style.dim("  \(head)"))
        if let since = report.since {
            lines.append("  " + Style.dim("since: ") + since)
        }
        lines.append("")

        // Headline counts.
        let s = report.summary
        let parts = [
            Style.green("\(s.paired) paired"),
            Style.cyan("\(s.equivalent) equivalent"),
            Style.red("\(s.gapOnA) gap on \(report.portA.portName)"),
            Style.red("\(s.gapOnB) gap on \(report.portB.portName)"),
            Style.yellow("\(s.ambiguous) ambiguous"),
        ]
        lines.append("  " + parts.joined(separator: Style.dim("  ·  ")))
        lines.append("")

        // Ledger sizes — auditable context.
        lines.append("  " + Style.dim("ledgers: ")
            + "\(report.portA.features.count) \(report.portA.portName) features  ·  "
            + "\(report.portB.features.count) \(report.portB.portName) features")

        // Gaps — the actionable signal.
        let gaps = report.features.filter { $0.status == .gapOnA || $0.status == .gapOnB }
        if !gaps.isEmpty {
            lines.append("")
            lines.append("  " + Style.bold("Gaps") + Style.dim("  (work to schedule)"))
            for f in gaps {
                let side: String
                let title: String
                switch f.status {
                case .gapOnA:
                    side = report.portA.portName
                    title = f.descriptionB ?? "(unknown)"
                case .gapOnB:
                    side = report.portB.portName
                    title = f.descriptionA ?? "(unknown)"
                default:
                    side = ""
                    title = ""
                }
                let confidence = formatConfidence(f.confidence)
                lines.append("    " + Style.red("•") + " "
                    + Style.bold("[\(side)]") + " " + title
                    + Style.dim("  \(confidence)"))
            }
        }

        // Ambiguous — surface for human confirmation, NEVER auto-file.
        let ambiguous = report.features.filter { $0.status == .ambiguous }
        if !ambiguous.isEmpty {
            lines.append("")
            lines.append("  " + Style.yellow("Ambiguous") + Style.dim("  (confirm before treating as gaps)"))
            for f in ambiguous {
                let a = f.descriptionA ?? "—"
                let b = f.descriptionB ?? "—"
                let confidence = formatConfidence(f.confidence)
                lines.append("    " + Style.yellow("?") + " "
                    + a + Style.dim("  ↔  ") + b
                    + Style.dim("  \(confidence)"))
            }
        }

        // Issue drafts, paste-ready.
        if !report.suggestedIssues.isEmpty {
            lines.append("")
            lines.append("  " + Style.bold("Drafted issues") + Style.dim("  (paste into your tracker)"))
            for issue in report.suggestedIssues {
                lines.append("")
                lines.append("    " + Style.bold("[\(issue.side)] \(issue.title)"))
                for bodyLine in issue.body.split(separator: "\n", omittingEmptySubsequences: false) {
                    lines.append("      " + String(bodyLine))
                }
            }
        }

        // Footer: provider + the mandatory disclaimer.
        lines.append("")
        if !report.generatedBy.isEmpty {
            lines.append("  " + Style.dim("generated by: ") + report.generatedBy)
        }
        lines.append("  " + Style.dim(report.disclaimer))
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Format a confidence value for terminal output, color-coded by band:
    /// high (≥ 0.8) green, mid (0.5–0.8) plain, low (< 0.5) yellow.
    private static func formatConfidence(_ c: Double) -> String {
        let pct = Int((c * 100).rounded())
        let text = "confidence \(pct)%"
        if c >= 0.8 { return Style.green(text) }
        if c < 0.5 { return Style.yellow(text) }
        return text
    }

    /// Right-pad a string to a fixed width (left-aligned numbers read cleanly).
    private static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }
}
