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

    // MARK: - Building blocks

    /// Wrap the page chrome. `subtitle` is the small dim line under the title.
    /// `copySource` (when set) becomes the document-level fallback for the
    /// "copy" buttons — unused for vitals/many/blame/branch.
    private static func page(
        title: String,
        subtitle: String,
        body: String,
        includeCopyShim: Bool,
        copySource: String? = nil
    ) -> String {
        var html = ""
        html += "<!doctype html>\n<html lang=\"en\">\n<head>\n"
        html += "<meta charset=\"utf-8\">\n"
        html += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        html += "<title>\(esc(title)) — rw</title>\n"
        html += "<style>\n\(css)\n</style>\n"
        html += "</head>\n<body>\n"
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
}
