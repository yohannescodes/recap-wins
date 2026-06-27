import Foundation

/// Tracker-flavored formatters for `IssueDraft`s (FRD §4 `--issues`).
///
/// `rw align` never calls a tracker API — it produces paste-ready text. The
/// matcher returns Markdown bodies; these formatters layer in tracker-native
/// wrappers (labels, checklists, front-matter) so a draft drops cleanly into
/// the user's tool without manual cleanup.
public enum IssueFormat: String, Sendable, CaseIterable {
    /// The canonical Markdown body, unchanged. Default.
    case markdown
    /// Linear-flavored: title as `# `, labels line, plain Markdown body.
    case linear
    /// GitHub-flavored: title + labels: line + body, suitable for `gh issue create`.
    case github
    /// Jira-flavored: title + h1./bullet conversion + WBS-style "Acceptance".
    case jira

    /// Parse from a CLI flag value.
    public static func parse(_ raw: String) -> IssueFormat? {
        IssueFormat(rawValue: raw.lowercased())
    }
}

/// Renders an `IssueDraft` for one of the supported tracker formats.
public enum IssueFormatter {
    /// Format a single issue, returning the paste-ready text. Title is shown
    /// in-line because the canonical "issue draft" surface is one block of
    /// text per issue — easier to pipe to `pbcopy` or paste manually.
    public static func format(_ issue: IssueDraft, as format: IssueFormat) -> String {
        switch format {
        case .markdown:
            return formatMarkdown(issue)
        case .linear:
            return formatLinear(issue)
        case .github:
            return formatGithub(issue)
        case .jira:
            return formatJira(issue)
        }
    }

    /// Format all issues separated by a horizontal rule appropriate to the
    /// chosen format. Convenient for "dump them all" terminal output.
    public static func formatAll(_ issues: [IssueDraft], as fmt: IssueFormat) -> String {
        let rendered = issues.map { format($0, as: fmt) }
        let sep = fmt == .jira ? "\n----\n\n" : "\n\n---\n\n"
        return rendered.joined(separator: sep)
    }

    // MARK: - Per-format renderers

    private static func formatMarkdown(_ issue: IssueDraft) -> String {
        // The source format. Title as an h2 (h1 is the page); body verbatim.
        var s = "## [\(issue.side)] \(issue.title)\n\n"
        s += issue.body
        if !issue.sourceFeature.isEmpty {
            s += "\n\n_source: \(issue.sourceFeature)_"
        }
        return s
    }

    private static func formatLinear(_ issue: IssueDraft) -> String {
        // Linear's import format: a title line, optional labels, then body.
        // `Labels:` is a Linear convention picked up by their importers and
        // the `linear` CLI's `--label` flag readers.
        var s = "# \(issue.title)\n\n"
        s += "Labels: parity, \(issue.side)\n\n"
        s += issue.body
        if !issue.sourceFeature.isEmpty {
            s += "\n\n_Source feature: \(issue.sourceFeature)_"
        }
        return s
    }

    private static func formatGithub(_ issue: IssueDraft) -> String {
        // Optimized for paste into a GitHub issue OR pipe through `gh issue
        // create --title ... --body ...`. We emit `Title:` / `Labels:` lines
        // so a small wrapper can grep them; the body itself stays markdown.
        var s = "Title: [\(issue.side)] \(issue.title)\n"
        s += "Labels: parity, port:\(issue.side)\n\n"
        s += issue.body
        if !issue.sourceFeature.isEmpty {
            s += "\n\n> Source feature (other port): \(issue.sourceFeature)"
        }
        return s
    }

    private static func formatJira(_ issue: IssueDraft) -> String {
        // Jira wiki markup converted from common Markdown idioms. Limited but
        // covers the common cases: heading, bold, bullets, code spans.
        var s = "h2. [\(issue.side)] \(issue.title)\n\n"
        s += convertMarkdownToJira(issue.body)
        if !issue.sourceFeature.isEmpty {
            s += "\n\n{quote}Source feature: \(issue.sourceFeature){quote}"
        }
        return s
    }

    /// Tiny Markdown → Jira wiki-markup converter. Handles only the patterns
    /// the matcher's prompt produces: `## H2`, `### H3`, `**bold**`, `` `code` ``,
    /// `- bullets`. Anything else passes through unchanged (Jira renders most
    /// Markdown as plain text, which is at least readable).
    private static func convertMarkdownToJira(_ md: String) -> String {
        var out: [String] = []
        for raw in md.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if line.hasPrefix("### ") {
                line = "h4. " + String(line.dropFirst(4))
            } else if line.hasPrefix("## ") {
                line = "h3. " + String(line.dropFirst(3))
            } else if line.hasPrefix("# ") {
                line = "h2. " + String(line.dropFirst(2))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "* " + String(line.dropFirst(2))
            }
            // `code` → {{code}}
            line = applySpan(line, marker: "`", openTag: "{{", closeTag: "}}")
            // **bold** → *bold* (Jira uses single asterisks for bold)
            line = applySpan(line, marker: "**", openTag: "*", closeTag: "*")
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    /// Replace alternating `marker` runs with open/close tags; an unmatched
    /// trailing marker is left as literal text. Same lenient policy
    /// HTMLRender uses for changelog inline spans.
    private static func applySpan(_ s: String, marker: String, openTag: String, closeTag: String) -> String {
        let parts = s.components(separatedBy: marker)
        guard parts.count > 2 else { return s }
        var out = parts[0]
        var open = true
        for i in 1..<parts.count {
            let isLast = (i == parts.count - 1)
            if open && isLast {
                out += marker + parts[i]
            } else {
                out += (open ? openTag : closeTag) + parts[i]
                open.toggle()
            }
        }
        return out
    }
}
