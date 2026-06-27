import Testing
import Foundation
import RecapCore
@testable import SemanticKit

/// Golden-ish coverage for the HTML renderer. Each per-command renderer is
/// exercised with a small canned report — we don't snapshot the whole file
/// (the CSS would drown signal in noise); instead we assert the load-bearing
/// invariants: facts make it in, hostile input is escaped, the output is
/// fully self-contained (no CDN / external refs), and the cap meter shifts
/// classes at the documented thresholds.
@Suite("HTML renderer")
struct HTMLRenderTests {
    // MARK: - Fixtures

    private let range = ChangeRange(
        base: "main", head: "HEAD",
        baseSHA: "abcdef1234", headSHA: "1234567abcdef",
        mergeBaseSHA: "abcdef1234")

    private let ledgerly = ProductProfile(
        id: "led", name: "Ledgerly",
        voice: "clear, trustworthy",
        links: [], platform: .iOS, targets: [:])

    private func fullReport() -> ChangeReport {
        let files = [
            FileChange(path: "Sources/Export.swift", insertions: 80, deletions: 4, status: "M"),
            FileChange(path: "README.md", insertions: 20, deletions: 0, status: "M"),
        ]
        let commits = [
            Commit(sha: "a1b2c3d4", shortSHA: "a1b2c3d", authorName: "Ada",
                   authorEmail: "ada@example.com", date: Date(timeIntervalSince1970: 0),
                   subject: "feat: export CSV", type: .feat, scope: nil,
                   breaking: false, isMerge: false, ticket: nil),
            Commit(sha: "b2c3d4e5", shortSHA: "b2c3d4e", authorName: "Ada",
                   authorEmail: "ada@example.com", date: Date(timeIntervalSince1970: 1),
                   subject: "fix: rounding", type: .fix, scope: nil,
                   breaking: false, isMerge: false, ticket: nil),
        ]
        let vitals = Vitals(
            features: 1, fixes: 1, chores: 0, filesChanged: 2,
            insertions: 100, deletions: 4,
            contributors: [Contributor(name: "Ada", email: "ada@example.com", commitCount: 2)],
            branchCount: 1, hotspots: files, inferredCount: 0)
        return ChangeReport(
            range: range, commits: commits, files: files,
            branches: [BranchInfo(name: "main", commitCount: 2, isHead: true)],
            vitals: vitals,
            riskFlags: [RiskFlag(kind: .largeDiff, message: "diff is large")])
    }

    // MARK: - Shared invariants

    @Test("rendered pages are fully self-contained — no CDN, no external refs")
    func selfContained() {
        let html = HTMLRender.vitals(fullReport())
        #expect(!html.contains("http://"))
        // The one https:// allowed is the footer link to novarch.lol.
        let externalCount = html.components(separatedBy: "https://").count - 1
        #expect(externalCount == 1)
        #expect(html.contains("https://novarch.lol/recap-wins"))
        #expect(!html.lowercased().contains("cdn"))
        #expect(!html.contains("<link "))
        #expect(!html.contains("<script src"))
    }

    @Test("HTML special chars in commit subjects and paths are escaped")
    func escaping() {
        var report = fullReport()
        // The vitals header renders the hotspots list, which reads from
        // `vitals.hotspots` — so mutate both for the assertion to cover the
        // path that actually reaches the HTML.
        let hostile = FileChange(
            path: "Sources/<evil>&\"'.swift",
            insertions: 80, deletions: 4, status: "M")
        report.files[0] = hostile
        report.vitals.hotspots[0] = hostile
        let html = HTMLRender.vitals(report)
        #expect(html.contains("Sources/&lt;evil&gt;&amp;&quot;&#39;.swift"))
        #expect(!html.contains("Sources/<evil>"))
    }

    // MARK: - Per-command renders

    @Test("vitals carries counts, hotspots, and risk flags")
    func vitals() {
        let html = HTMLRender.vitals(fullReport())
        #expect(html.contains("<h1>recap-wins</h1>"))
        #expect(html.contains("<strong>1</strong> features"))
        #expect(html.contains("<strong>1</strong> fixes"))
        #expect(html.contains("Hotspots"))
        #expect(html.contains("Sources/Export.swift"))
        #expect(html.contains("diff is large"))
    }

    @Test("many shows the by-declared-type breakdown")
    func many() {
        let html = HTMLRender.many(fullReport())
        #expect(html.contains("By declared type"))
        #expect(html.contains("1 — feat"))
        #expect(html.contains("1 — fix"))
    }

    @Test("blame lists contributors with percentages")
    func blame() {
        let html = HTMLRender.blame(fullReport())
        #expect(html.contains("Attribution"))
        #expect(html.contains("Ada"))
        #expect(html.contains("100%"))
    }

    @Test("branch lists branches with head marker")
    func branch() {
        let html = HTMLRender.branch(fullReport())
        #expect(html.contains("Branches in this change set"))
        #expect(html.contains("main"))
        #expect(html.contains("(head)"))
    }

    @Test("new renders markdown bullets as <ul>/<li>")
    func newFeatures() {
        let body = "- CSV export\n- Dark mode\n\nNon-bullet line."
        let html = HTMLRender.newFeatures(body, range: range)
        #expect(html.contains("<li>CSV export</li>"))
        #expect(html.contains("<li>Dark mode</li>"))
        #expect(html.contains("<p>Non-bullet line.</p>"))
        // Copy shim only renders on pages with copyable text.
        #expect(html.contains("button.copy"))  // CSS for the button class
    }

    // MARK: - notes + cap meter

    @Test("notes renders the prose with a copy button and meter")
    func notes() {
        let limit = ResolvedLimit(ceiling: 4000, softTarget: 300)
        let html = HTMLRender.notes(
            "Bug fixes and improvements.",
            target: .ascUpdate, limit: limit, product: ledgerly, range: range)
        #expect(html.contains("App Store"))
        #expect(html.contains("/ 4000 chars"))
        #expect(html.contains("aim ~300"))
        #expect(html.contains("data-copy-target"))
        #expect(html.contains("Bug fixes and improvements."))
    }

    @Test("cap meter switches class as it nears, hits, and exceeds the ceiling")
    func meterClasses() {
        let make: (Int) -> String = { count in
            HTMLRender.notes(
                String(repeating: "x", count: count),
                target: .ascUpdate,
                limit: ResolvedLimit(ceiling: 100, softTarget: nil),
                product: nil, range: self.range)
        }
        // Below 90% — plain meter.
        let under = make(50)
        #expect(under.contains("class=\"meter\""))
        #expect(!under.contains("meter near"))
        #expect(!under.contains("meter over"))
        // 90–100% — "near".
        let near = make(95)
        #expect(near.contains("meter near"))
        // Over — "over".
        let over = make(120)
        #expect(over.contains("meter over"))
    }

    @Test("uncapped meter (ceiling 0) shows count only, no bar")
    func uncappedMeter() {
        let html = HTMLRender.notes(
            "PR body.",
            target: .pr,
            limit: ResolvedLimit(ceiling: 0, softTarget: nil),
            product: nil, range: range)
        // No "/ N chars" since there's no ceiling — just "N chars".
        #expect(html.contains("8 chars"))
        #expect(!html.contains("/ 0 chars"))
    }

    // MARK: - market

    @Test("market renders each piece with its own meter and copy button")
    func market() {
        let results = [
            MarketPieceResult(piece: .subtitle, text: "Money, calm.", overflowWarning: nil),
            MarketPieceResult(piece: .tweet, text: String(repeating: "x", count: 300),
                              overflowWarning: "over"),
        ]
        let html = HTMLRender.market(
            results, product: ledgerly, limits: .fallback, range: range)
        #expect(html.contains("App Store subtitle"))
        #expect(html.contains("Tweet"))
        #expect(html.contains("12 / 30 chars"))    // subtitle, 12 chars
        #expect(html.contains("300 / 280 chars"))  // tweet, over
        #expect(html.contains("meter over"))
        // One <button> per piece — count the opening tags, not bare attribute
        // mentions (the inline JS shim also references data-copy-target).
        let copyButtons = html.components(separatedBy: "<button class=\"copy\"").count - 1
        #expect(copyButtons == 2)
    }

    @Test("market still renders cleanly when results are empty")
    func emptyMarket() {
        let html = HTMLRender.market(
            [], product: ledgerly, limits: .fallback, range: range)
        #expect(html.contains("Marketing pack"))
        // No copy buttons when there are no pieces — count the opening tags,
        // not the JS shim's own mention of the data attribute.
        #expect(!html.contains("<button class=\"copy\""))
    }
}
