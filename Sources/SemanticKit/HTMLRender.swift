import Foundation
import RecapCore

/// Renders each command's report to a single self-contained, offline HTML file
/// (FRD §9.1). Pure presentation — no model calls, no network, no CDN.
///
/// The visual reference is Paul Graham's blog: Verdana, a narrow column,
/// generous line-height, navy links, and almost no chrome. No cards, no
/// shadows, no icons. The only interactive bits are copy buttons on paste-bound
/// blocks (notes/market), implemented with a tiny inline JS shim.
public enum HTMLRender {
    // MARK: - Per-command renderers

    /// `rw --html` — vitals dashboard.
    public static func vitals(_ report: ChangeReport) -> String {
        let v = report.vitals
        let head = report.range.head == "HEAD"
            ? String(report.range.headSHA.prefix(7))
            : report.range.head
        let subtitle = "\(report.range.base)…\(head)"

        var body = ""
        body += paragraph(
            "<strong>\(esc(format(v.features)))</strong> features"
            + " · <strong>\(esc(format(v.fixes)))</strong> fixes"
            + " · \(esc(format(v.chores))) chores")
        if v.inferredCount > 0 {
            body += muted("\(v.inferredCount) inferred from message/diff — not conventional commits")
        }
        body += paragraph(
            "\(esc(format(v.filesChanged))) files changed · "
            + "+\(esc(format(v.insertions))) / −\(esc(format(v.deletions)))")

        if !v.contributors.isEmpty {
            let names = v.contributors
                .map { "\(esc($0.name)) (\($0.commitCount))" }
                .joined(separator: ", ")
            body += paragraph("Contributors: \(names)")
        }
        body += paragraph("Branches involved: \(v.branchCount)")

        if !v.hotspots.isEmpty {
            body += "<h2>Hotspots</h2>\n"
            body += "<ul>\n"
            for f in v.hotspots {
                body += "<li>\(esc(f.path)) — \(f.churn) "
                    + "<span class=\"muted\">(+\(f.insertions) / −\(f.deletions))</span></li>\n"
            }
            body += "</ul>\n"
        }

        if !report.riskFlags.isEmpty {
            body += "<h2>Risk flags <span class=\"muted\">(advisory)</span></h2>\n"
            body += "<ul>\n"
            for flag in report.riskFlags {
                body += "<li>\(esc(flag.message))</li>\n"
            }
            body += "</ul>\n"
        }

        return page(title: "recap-wins", subtitle: subtitle, body: body, includeCopyShim: false)
    }

    /// `rw many --html` — counts and by-type breakdown.
    public static func many(_ report: ChangeReport) -> String {
        let work = report.commits.filter { !$0.isMerge }
        var byType: [CommitType: Int] = [:]
        for c in work { byType[c.type, default: 0] += 1 }
        let v = report.vitals

        var body = ""
        body += paragraph(
            "<strong>\(format(v.features))</strong> features · "
            + "<strong>\(format(v.fixes))</strong> fixes · "
            + "\(format(v.chores)) chores")
        if v.inferredCount > 0 {
            body += muted("\(v.inferredCount) inferred from message/diff — not conventional commits")
        }

        body += "<h2>By declared type</h2>\n<ul>\n"
        for type in CommitType.allCases where (byType[type] ?? 0) > 0 {
            body += "<li>\(byType[type]!) — \(type.rawValue)</li>\n"
        }
        let merges = report.commits.count - work.count
        if merges > 0 {
            body += "<li class=\"muted\">\(merges) — merges (excluded from counts)</li>\n"
        }
        body += "</ul>\n"

        return page(
            title: "Introduced in this change set",
            subtitle: rangeSubtitle(report.range),
            body: body, includeCopyShim: false)
    }

    /// `rw blame --html` — attribution by commit share.
    public static func blame(_ report: ChangeReport) -> String {
        var body = ""
        body += muted("\(report.commits.count) commits")
        if report.vitals.contributors.isEmpty {
            body += paragraph("No non-merge commits in this change set.")
        } else {
            let total = max(report.vitals.contributors.reduce(0) { $0 + $1.commitCount }, 1)
            body += "<ul>\n"
            for c in report.vitals.contributors {
                let pct = Int((Double(c.commitCount) / Double(total) * 100).rounded())
                body += "<li>\(c.commitCount) · \(pct)% — \(esc(c.name)) "
                    + "<span class=\"muted\">&lt;\(esc(c.email))&gt;</span></li>\n"
            }
            body += "</ul>\n"
        }
        return page(
            title: "Attribution",
            subtitle: rangeSubtitle(report.range),
            body: body, includeCopyShim: false)
    }

    /// `rw branch --html` — branches that contributed to this change set.
    public static func branch(_ report: ChangeReport) -> String {
        var body = ""
        if report.branches.isEmpty {
            body += paragraph("No branches found for this change set.")
        } else {
            body += "<ul>\n"
            for b in report.branches {
                let head = b.isHead ? " <span class=\"muted\">(head)</span>" : ""
                body += "<li>\(esc(b.name)) — \(b.commitCount) commits\(head)</li>\n"
            }
            body += "</ul>\n"
        }
        return page(
            title: "Branches in this change set",
            subtitle: rangeSubtitle(report.range),
            body: body, includeCopyShim: false)
    }

    /// `rw new --html` — the bulleted feature list, rendered as prose.
    public static func newFeatures(_ text: String, range: ChangeRange) -> String {
        var body = ""
        body += renderProse(text)
        return page(
            title: "New features",
            subtitle: rangeSubtitle(range),
            body: body, includeCopyShim: true,
            copySource: text)
    }

    /// `rw notes <target> --html` — the note in context with a live cap meter.
    public static func notes(
        _ text: String,
        target: NoteTarget,
        limit: ResolvedLimit,
        product: ProductProfile?,
        range: ChangeRange
    ) -> String {
        var body = ""
        if let product {
            body += muted("Voice: \(esc(product.name))")
        }
        body += capMeter(count: text.count, ceiling: limit.ceiling, softTarget: limit.softTarget)
        body += copyableBlock(text: text, id: "note-body")
        return page(
            title: target.displayName,
            subtitle: rangeSubtitle(range),
            body: body, includeCopyShim: true,
            copySource: text)
    }

    /// `rw notes --changelog` — release-page changelog (HTML-only target).
    /// Renders the model's `## Added / ## Changed / ## Fixed` markdown into a
    /// clean release page. `version` is the human-facing label ("v0.2.0");
    /// `range` carries the diff range for the subtitle line.
    public static func changelog(
        _ text: String,
        version: String,
        range: ChangeRange
    ) -> String {
        var body = renderChangelogBody(text)
        body += "<p class=\"muted footnote\">"
        body += "Generated by <a href=\"https://novarch.lol/recap-wins\">recap-wins</a> "
        body += "via <code>rw notes --changelog</code>."
        body += "</p>\n"
        return page(
            title: version,
            subtitle: "Changelog · \(rangeSubtitle(range))",
            body: body, includeCopyShim: false)
    }

    /// Parse the model's Added/Changed/Fixed markdown into HTML. Lenient: any
    /// `## Heading` becomes an `<h2>`, `- ` / `* ` lines become list items,
    /// blank lines close lists. Within a line we render two inline markdown
    /// spans — `**bold**` and `` `code` `` — because the changelog prose
    /// leans on them. Unknown headings still render as `<h2>` (we'd rather
    /// show the prose than swallow it).
    private static func renderChangelogBody(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var html = ""
        var inList = false
        for raw in lines {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if inList { html += "</ul>\n"; inList = false }
                continue
            }
            if line.hasPrefix("## ") {
                if inList { html += "</ul>\n"; inList = false }
                html += "<h2>\(escAndInline(String(line.dropFirst(3))))</h2>\n"
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !inList { html += "<ul>\n"; inList = true }
                html += "<li>\(escAndInline(String(line.dropFirst(2))))</li>\n"
            } else {
                if inList { html += "</ul>\n"; inList = false }
                html += "<p>\(escAndInline(line))</p>\n"
            }
        }
        if inList { html += "</ul>\n" }
        return html
    }

    /// HTML-escape, then convert two inline markdown spans we care about:
    /// `**bold**` → `<strong>`, `` `code` `` → `<code>`. Escaping first is
    /// safe because both span markers are pure ASCII punctuation that survive
    /// the escape unchanged. Greedy but non-nested — good enough for
    /// changelog list items, and predictable.
    private static func escAndInline(_ s: String) -> String {
        let escaped = esc(s)
        let withCode = applyInlineSpan(escaped, marker: "`", openTag: "<code>", closeTag: "</code>")
        return applyInlineSpan(withCode, marker: "**", openTag: "<strong>", closeTag: "</strong>")
    }

    /// Replace alternating occurrences of `marker` with `openTag` / `closeTag`.
    /// An odd trailing marker is left as literal text rather than producing
    /// an unclosed tag.
    private static func applyInlineSpan(_ s: String, marker: String, openTag: String, closeTag: String) -> String {
        let parts = s.components(separatedBy: marker)
        // Zero or one part → nothing to wrap.
        guard parts.count > 2 else { return s }
        var out = parts[0]
        var i = 1
        var open = true
        while i < parts.count {
            // If there's an odd unmatched trailing marker, emit it literally
            // alongside the remaining text.
            let isLast = (i == parts.count - 1)
            if open && isLast {
                out += marker + parts[i]
            } else {
                out += (open ? openTag : closeTag) + parts[i]
                open.toggle()
            }
            i += 1
        }
        return out
    }

    /// `rw market --html` — store-listing proof sheet. One block per piece with
    /// its cap meter and a copy button.
    public static func market(
        _ results: [MarketPieceResult],
        product: ProductProfile,
        limits: MarketLimits,
        range: ChangeRange
    ) -> String {
        var body = ""
        body += muted("Voice: \(esc(product.name))")
        for (i, r) in results.enumerated() {
            let ceiling = r.piece.ceiling(limits)
            body += "<h2>\(esc(r.piece.title))</h2>\n"
            body += capMeter(count: r.text.count, ceiling: ceiling, softTarget: nil)
            body += copyableBlock(text: r.text, id: "piece-\(i)")
        }
        return page(
            title: "Marketing pack",
            subtitle: rangeSubtitle(range),
            body: body, includeCopyShim: true)
    }

    /// `rw align --html` — the parity matrix view (FRD §9.1).
    ///
    /// Layout: filter chips at the top (paired / equivalent / gap / ambiguous,
    /// click to filter), then a two-column matrix with each side's features
    /// labeled by status chip, then drafted issues at the bottom with copy
    /// buttons. Confidence inline on each row. Same PG-blog aesthetic as the
    /// other HTML renders, just wider to accommodate two columns.
    public static func alignReport(_ report: AlignReport) -> String {
        var body = ""

        // Disclaimer banner. The FRD insists this is non-optional output.
        body += "<div class=\"disclaimer\">"
        body += esc(report.disclaimer)
        body += "</div>\n"

        // Headline counts + filter chips. Each chip toggles a class on <body>
        // that hides non-matching rows via CSS; click again to clear. Pure
        // CSS-driven would be even cleaner, but a tiny JS shim handles the
        // toggle without introducing framework weight.
        let s = report.summary
        body += "<div class=\"chips\">\n"
        body += chip(label: "all",        count: report.features.count, key: "all", kind: "all")
        body += chip(label: "paired",     count: s.paired,     key: "paired",     kind: "paired")
        body += chip(label: "equivalent", count: s.equivalent, key: "equivalent", kind: "equivalent")
        body += chip(label: "gap on \(report.portA.portName)", count: s.gapOnA, key: "gap_on_a", kind: "gap")
        body += chip(label: "gap on \(report.portB.portName)", count: s.gapOnB, key: "gap_on_b", kind: "gap")
        body += chip(label: "ambiguous",  count: s.ambiguous,  key: "ambiguous",  kind: "ambiguous")
        body += "</div>\n"

        body += muted(
            "ledgers: \(report.portA.features.count) \(report.portA.portName) features"
            + " · \(report.portB.features.count) \(report.portB.portName) features"
            + (report.since.map { " · since \($0)" } ?? "")
            + (report.generatedBy.isEmpty ? "" : " · generated by \(report.generatedBy)"))

        // The matrix: side A on the left, side B on the right. Each feature
        // gets a status chip and confidence. For paired/equivalent rows we
        // show both descriptions side by side; for gaps, the missing side
        // says "— missing —"; for ambiguous, both shown with a "?" marker.
        body += "<div class=\"matrix\">\n"
        body += "  <div class=\"col\">\n"
        body += "    <h2>\(esc(report.portA.portName)) "
            + "<span class=\"muted\">(\(report.portA.features.count))</span></h2>\n"
        for (i, m) in report.features.enumerated() {
            body += renderMatrixRow(m, side: .a, rowID: "m-\(i)")
        }
        body += "  </div>\n"
        body += "  <div class=\"col\">\n"
        body += "    <h2>\(esc(report.portB.portName)) "
            + "<span class=\"muted\">(\(report.portB.features.count))</span></h2>\n"
        for (i, m) in report.features.enumerated() {
            body += renderMatrixRow(m, side: .b, rowID: "m-\(i)")
        }
        body += "  </div>\n"
        body += "</div>\n"

        // Drafted issues. Each gets a copy button on its markdown body — the
        // canonical paste-ready surface. Tracker-specific reformatting is
        // handled at the command layer (--issues), not here.
        if !report.suggestedIssues.isEmpty {
            body += "<h2>Drafted issues "
                + "<span class=\"muted\">(\(report.suggestedIssues.count))</span></h2>\n"
            for (i, issue) in report.suggestedIssues.enumerated() {
                let header = "[\(issue.side)] \(issue.title)"
                body += "<h3>\(esc(header))</h3>\n"
                if !issue.sourceFeature.isEmpty {
                    body += muted("source: \(esc(issue.sourceFeature))")
                }
                body += copyableBlock(text: issue.body, id: "issue-\(i)")
            }
        }

        let title: String
        if let product = report.product, !product.isEmpty {
            title = "rw align — \(product)"
        } else {
            title = "rw align"
        }
        let subtitle = "\(report.portA.portName) @ \(String(report.portA.headSHA.prefix(7)))"
            + " · \(report.portB.portName) @ \(String(report.portB.headSHA.prefix(7)))"
        return page(
            title: title, subtitle: subtitle,
            body: body, includeCopyShim: true,
            bodyClass: "align filter-all",
            extraScripts: alignFilterShim)
    }

    /// Which port a matrix row column is rendering for.
    private enum Side { case a, b }

    /// Render one feature match as a row in the matrix column for a side.
    /// The row's `data-status` attribute drives the filter shim — chips hide
    /// rows whose status doesn't match the active filter.
    private static func renderMatrixRow(_ m: FeatureMatch, side: Side, rowID: String) -> String {
        let descA = m.descriptionA ?? "— missing —"
        let descB = m.descriptionB ?? "— missing —"
        let text: String
        let missing: Bool
        switch side {
        case .a:
            text = descA
            missing = m.descriptionA == nil
        case .b:
            text = descB
            missing = m.descriptionB == nil
        }
        let chipHTML = statusChip(m.status)
        let confidence = confidenceBadge(m.confidence)
        let note = m.equivalenceNote.map {
            " <span class=\"note muted\">— \(esc($0))</span>"
        } ?? ""
        let missingClass = missing ? " missing" : ""
        return "    <div class=\"row\(missingClass)\" data-row=\"\(rowID)\" data-status=\"\(m.status.rawValue)\">"
            + "\(chipHTML)<span class=\"text\">\(esc(text))</span>"
            + "\(note)\(confidence)</div>\n"
    }

    /// One filter chip — clicking toggles a body class that hides non-matching
    /// rows via CSS. `kind` controls the chip's color; `key` is the status raw
    /// value the filter targets (or "all"/"gap" for compound filters).
    private static func chip(label: String, count: Int, key: String, kind: String) -> String {
        "<button class=\"chip chip-\(esc(kind))\" data-filter=\"\(esc(key))\" type=\"button\">"
            + "\(esc(label)) <span class=\"count\">\(count)</span></button>\n"
    }

    /// Status chip used inside matrix rows — same coloring as the filter chips
    /// but smaller. Marker text matches the status.
    private static func statusChip(_ status: MatchStatus) -> String {
        let kind: String
        let label: String
        switch status {
        case .paired:     kind = "paired";     label = "paired"
        case .equivalent: kind = "equivalent"; label = "equivalent"
        case .gapOnA:     kind = "gap";        label = "gap"
        case .gapOnB:     kind = "gap";        label = "gap"
        case .ambiguous:  kind = "ambiguous";  label = "?"
        }
        return "<span class=\"badge badge-\(kind)\">\(esc(label))</span>"
    }

    /// Confidence pill, color-banded the same way the terminal render bands:
    /// high (≥0.8) green, mid plain, low (<0.5) amber. Always surfaced.
    private static func confidenceBadge(_ c: Double) -> String {
        let pct = Int((c * 100).rounded())
        let band: String
        if c >= 0.8 { band = "high" }
        else if c < 0.5 { band = "low" }
        else { band = "mid" }
        return " <span class=\"conf conf-\(band)\">\(pct)%</span>"
    }

    // MARK: - Building blocks

    /// Wrap the page chrome. `subtitle` is the small dim line under the title.
    /// `copySource` (when set) becomes the document-level fallback for the
    /// "copy" buttons — unused for vitals/many/blame/branch.
    private static func page(
        title: String,
        subtitle: String,
        body: String,
        includeCopyShim: Bool,
        copySource: String? = nil,
        bodyClass: String? = nil,
        extraScripts: String? = nil
    ) -> String {
        var html = ""
        html += "<!doctype html>\n<html lang=\"en\">\n<head>\n"
        html += "<meta charset=\"utf-8\">\n"
        html += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        html += "<title>\(esc(title)) — rw</title>\n"
        html += "<style>\n\(css)\n</style>\n"
        html += "</head>\n"
        if let bodyClass {
            html += "<body class=\"\(esc(bodyClass))\">\n"
        } else {
            html += "<body>\n"
        }
        html += "<main>\n"
        html += "<h1>\(esc(title))</h1>\n"
        if !subtitle.isEmpty {
            html += "<p class=\"subtitle muted\">\(esc(subtitle))</p>\n"
        }
        html += body
        html += "<footer class=\"muted\">Generated by <a href=\"https://novarch.lol/recap-wins\">recap-wins</a>.</footer>\n"
        html += "</main>\n"
        if includeCopyShim {
            html += "<script>\n\(copyShim)\n</script>\n"
        }
        if let extraScripts {
            html += "<script>\n\(extraScripts)\n</script>\n"
        }
        // copySource is reserved for a future "copy whole document" affordance;
        // unused today, but reading it from the param keeps the call sites stable.
        _ = copySource
        html += "</body>\n</html>\n"
        return html
    }

    /// A short paragraph helper. Caller passes pre-built HTML; nothing escaped.
    private static func paragraph(_ html: String) -> String { "<p>\(html)</p>\n" }

    /// A muted one-line note ("9 inferred from message/diff…"). Plain text in.
    private static func muted(_ text: String) -> String {
        "<p class=\"muted\">\(esc(text))</p>\n"
    }

    /// The cap meter: "847 / 4000 chars" with a tiny bar. Amber as it nears
    /// the limit (>=90%), red over. Uncapped (ceiling == 0) shows count only.
    private static func capMeter(count: Int, ceiling: Int, softTarget: Int?) -> String {
        if ceiling <= 0 {
            var line = "\(count) chars"
            if let s = softTarget { line += " · aim ~\(s)" }
            return "<p class=\"meter muted\">\(esc(line))</p>\n"
        }
        let ratio = Double(count) / Double(ceiling)
        let cls: String
        if ratio > 1.0 { cls = "meter over" }
        else if ratio >= 0.9 { cls = "meter near" }
        else { cls = "meter" }
        var line = "\(count) / \(ceiling) chars"
        if let s = softTarget { line += " · aim ~\(s)" }
        let percent = min(Int((ratio * 100).rounded()), 100)
        return """
        <p class=\"\(cls)\">\(esc(line))</p>
        <div class=\"bar\"><div class=\"fill\" style=\"width:\(percent)%\"></div></div>
        \n
        """
    }

    /// A monospace block holding paste-ready text, with a Copy button. Uses a
    /// hidden textarea so the copy shim reads the verbatim value — `<pre>`
    /// preserves whitespace visually, the textarea preserves it for the clipboard.
    private static func copyableBlock(text: String, id: String) -> String {
        var html = ""
        html += "<div class=\"copyable\">\n"
        html += "<button class=\"copy\" data-copy-target=\"\(esc(id))\" type=\"button\">Copy</button>\n"
        html += "<pre id=\"\(esc(id))-view\">\(esc(text))</pre>\n"
        html += "<textarea id=\"\(esc(id))\" aria-hidden=\"true\" tabindex=\"-1\">\(esc(text))</textarea>\n"
        html += "</div>\n"
        return html
    }

    /// Render model prose (typically a bulleted list) into HTML. Recognizes
    /// `- ` and `* ` bullets; everything else becomes a paragraph. Keeps the
    /// PG-blog visual rule: no heavy formatting.
    private static func renderProse(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var html = ""
        var inList = false
        for raw in lines {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if inList { html += "</ul>\n"; inList = false }
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !inList { html += "<ul>\n"; inList = true }
                let item = String(line.dropFirst(2))
                html += "<li>\(esc(item))</li>\n"
            } else {
                if inList { html += "</ul>\n"; inList = false }
                html += "<p>\(esc(line))</p>\n"
            }
        }
        if inList { html += "</ul>\n" }
        return html
    }

    /// Subtitle line for the page header — "base…shorthead".
    private static func rangeSubtitle(_ range: ChangeRange) -> String {
        let head = range.head == "HEAD" ? String(range.headSHA.prefix(7)) : range.head
        return "\(range.base)…\(head)"
    }

    /// Thousands-grouped integer; vitals reads more easily than `1234`.
    private static func format(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Minimal HTML escape — these strings reach the page verbatim, so any
    /// path/subject containing `<` or `&` would otherwise break the markup.
    private static func esc(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    // MARK: - Inline assets

    /// PG-blog leaning CSS. Verdana for body, narrow column, navy links, no
    /// shadows or cards. The only color beyond text and links is a single
    /// muted amber/red used by cap meters.
    private static let css = """
    html { background: #ffffff; color: #000000; }
    body { margin: 0; }
    main {
      max-width: 38em;
      margin: 2.5em auto;
      padding: 0 1.25em;
      font-family: Verdana, Geneva, sans-serif;
      font-size: 15px;
      line-height: 1.55;
    }
    h1 { font-size: 1.4em; margin: 0 0 0.1em 0; }
    h2 { font-size: 1.05em; margin: 1.6em 0 0.4em 0; }
    p { margin: 0.6em 0; }
    ul { margin: 0.5em 0 0.5em 1.2em; padding: 0; }
    li { margin: 0.15em 0; }
    a { color: #00008b; text-decoration: underline; }
    .subtitle { margin-top: 0; }
    .muted { color: #6b6b6b; }
    .meter { margin-bottom: 0.2em; font-size: 0.9em; }
    .meter.near { color: #a06a00; }
    .meter.over { color: #a00000; }
    .bar { height: 2px; background: #eeeeee; margin: 0 0 0.8em 0; overflow: hidden; }
    .bar .fill { height: 100%; background: #cccccc; }
    .meter.near + .bar .fill { background: #d6a000; }
    .meter.over + .bar .fill { background: #c00000; }
    .copyable { position: relative; margin: 0.4em 0 1.4em 0; }
    .copyable pre {
      margin: 0;
      padding: 0.6em 0.8em;
      background: #fafafa;
      border-left: 2px solid #eeeeee;
      white-space: pre-wrap;
      word-wrap: break-word;
      font-family: Verdana, Geneva, sans-serif;
      font-size: 0.95em;
    }
    .copyable textarea {
      position: absolute;
      left: -9999px;
      top: 0;
      width: 1px;
      height: 1px;
      opacity: 0;
    }
    button.copy {
      float: right;
      margin: 0 0 0.4em 0.6em;
      font: inherit;
      font-size: 0.85em;
      background: #ffffff;
      color: #00008b;
      border: 1px solid #d0d0d0;
      padding: 0.15em 0.55em;
      cursor: pointer;
    }
    button.copy:hover { border-color: #00008b; }
    button.copy.copied { color: #2a7a2a; border-color: #2a7a2a; }
    footer { margin-top: 2.5em; font-size: 0.85em; }
    .footnote { font-size: 0.85em; margin-top: 2em; }
    code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.95em; }

    /* --- align page (rw align --html) --- */
    body.align main { max-width: 64em; }
    .disclaimer {
      background: #fff8e6; border-left: 3px solid #d6a000;
      padding: 0.6em 0.9em; margin: 1em 0 1.2em 0; font-size: 0.95em;
    }
    .chips { margin: 0.6em 0 0.8em 0; }
    .chip {
      display: inline-block; margin: 0 0.3em 0.3em 0;
      padding: 0.2em 0.55em; font: inherit; font-size: 0.85em;
      background: #ffffff; color: #000000;
      border: 1px solid #d0d0d0; border-radius: 2px; cursor: pointer;
    }
    .chip:hover { border-color: #00008b; }
    .chip .count {
      margin-left: 0.4em; padding: 0 0.35em; border-radius: 2px;
      background: #f0f0f0; color: #6b6b6b; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 0.85em;
    }
    /* Each filter-X body class hides rows not matching the active status.
       The chip click toggles the body class. "all" shows everything. */
    body.filter-paired     .row[data-status]:not([data-status="paired"])    { display: none; }
    body.filter-equivalent .row[data-status]:not([data-status="equivalent"]){ display: none; }
    body.filter-gap_on_a   .row[data-status]:not([data-status="gap_on_a"])  { display: none; }
    body.filter-gap_on_b   .row[data-status]:not([data-status="gap_on_b"])  { display: none; }
    body.filter-ambiguous  .row[data-status]:not([data-status="ambiguous"]) { display: none; }
    /* Active chip styling tracks the body class via these matching selectors. */
    body.filter-all        .chip[data-filter="all"]        { background: #00008b; color: #ffffff; border-color: #00008b; }
    body.filter-paired     .chip[data-filter="paired"]     { background: #1a6e38; color: #ffffff; border-color: #1a6e38; }
    body.filter-equivalent .chip[data-filter="equivalent"] { background: #00008b; color: #ffffff; border-color: #00008b; }
    body.filter-gap_on_a   .chip[data-filter="gap_on_a"]   { background: #a00000; color: #ffffff; border-color: #a00000; }
    body.filter-gap_on_b   .chip[data-filter="gap_on_b"]   { background: #a00000; color: #ffffff; border-color: #a00000; }
    body.filter-ambiguous  .chip[data-filter="ambiguous"]  { background: #a06a00; color: #ffffff; border-color: #a06a00; }

    .matrix {
      display: grid; grid-template-columns: 1fr 1fr;
      gap: 1.4em; margin: 1em 0 1.6em 0;
    }
    @media (max-width: 48em) { .matrix { grid-template-columns: 1fr; } }
    .matrix .col h2 { margin-top: 0; }
    .row {
      padding: 0.4em 0; border-bottom: 1px solid #f0f0f0;
      font-size: 0.92em; line-height: 1.45;
    }
    .row.missing .text { color: #b0b0b0; font-style: italic; }
    .row .text { margin-left: 0.35em; }
    .row .note { margin-left: 0.35em; font-size: 0.9em; }
    .badge {
      display: inline-block; padding: 0.05em 0.4em;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 0.72em; text-transform: uppercase; border-radius: 2px;
      vertical-align: 1px;
    }
    .badge-paired     { background: #e6f4ea; color: #1a6e38; }
    .badge-equivalent { background: #e6e9ff; color: #00008b; }
    .badge-gap        { background: #ffe6e6; color: #a00000; }
    .badge-ambiguous  { background: #fff8e6; color: #a06a00; }
    .conf {
      display: inline-block; margin-left: 0.3em;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 0.82em; color: #6b6b6b;
    }
    .conf-high { color: #1a6e38; }
    .conf-low  { color: #a06a00; }
    h3 { font-size: 0.98em; margin: 1.2em 0 0.3em 0; }
    """

    /// One-purpose copy shim — no framework, no polyfills. Reads from the
    /// hidden textarea so multi-line text round-trips with line breaks intact.
    private static let copyShim = """
    document.addEventListener('click', function (e) {
      var btn = e.target.closest('button.copy');
      if (!btn) return;
      var id = btn.getAttribute('data-copy-target');
      var src = document.getElementById(id);
      if (!src) return;
      var text = src.value;
      var done = function () {
        var label = btn.textContent;
        btn.textContent = 'Copied';
        btn.classList.add('copied');
        setTimeout(function () {
          btn.textContent = label;
          btn.classList.remove('copied');
        }, 1200);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () {
          src.select(); document.execCommand('copy'); done();
        });
      } else {
        src.select(); document.execCommand('copy'); done();
      }
    });
    """

    /// Filter shim for the align matrix. Clicking a chip toggles a `filter-X`
    /// class on <body>; CSS hides non-matching rows. Clicking the active chip
    /// (or "all") clears the filter. No framework — just one event listener.
    private static let alignFilterShim = """
    document.addEventListener('click', function (e) {
      var chip = e.target.closest('.chip[data-filter]');
      if (!chip) return;
      var filter = chip.getAttribute('data-filter');
      var classes = document.body.classList;
      // Strip any existing filter-* class, then set the new one.
      var toRemove = [];
      classes.forEach(function (c) { if (c.indexOf('filter-') === 0) toRemove.push(c); });
      toRemove.forEach(function (c) { classes.remove(c); });
      // Clicking the active chip toggles back to "all".
      if (toRemove.indexOf('filter-' + filter) !== -1) {
        classes.add('filter-all');
      } else {
        classes.add('filter-' + filter);
      }
    });
    """
}
