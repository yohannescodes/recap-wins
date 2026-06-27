import Testing
import Foundation
import RecapCore
@testable import SemanticKit

// MARK: - HTML parity matrix

@Suite("Align HTML matrix")
struct AlignHTMLTests {
    private func sampleReport() -> AlignReport {
        let ledgerA = LedgerSnapshot(
            portName: "ios", repositoryPath: "/tmp/a", ref: "main",
            headSHA: "aaaaaaa", since: "v1.0", sinceSHA: "0000",
            features: [
                LedgerFeature(id: "1", title: "Apple Pay checkout",
                              scope: nil, origin: .declared,
                              sha: "1111111", date: Date(timeIntervalSince1970: 0)),
            ])
        let ledgerB = LedgerSnapshot(
            portName: "android", repositoryPath: "/tmp/b", ref: "main",
            headSHA: "bbbbbbb", since: "v1.0", sinceSHA: "0000",
            features: [
                LedgerFeature(id: "2", title: "Google Pay checkout",
                              scope: nil, origin: .declared,
                              sha: "2222222", date: Date(timeIntervalSince1970: 0)),
            ])
        let features = [
            FeatureMatch(id: "m1", status: .equivalent,
                         descriptionA: "Apple Pay checkout",
                         descriptionB: "Google Pay checkout",
                         equivalenceNote: "platform-native payment",
                         confidence: 0.95),
            FeatureMatch(id: "m2", status: .gapOnB,
                         descriptionA: "Onboarding tour",
                         descriptionB: nil, confidence: 0.85),
            FeatureMatch(id: "m3", status: .ambiguous,
                         descriptionA: "Receipts feed",
                         descriptionB: "Transaction history",
                         confidence: 0.4),
        ]
        return AlignReport(
            product: "ledgerly",
            portA: ledgerA, portB: ledgerB, since: "v1.0",
            features: features,
            summary: AlignSummary.from(features),
            suggestedIssues: [
                IssueDraft(side: "android", title: "Port onboarding tour",
                           body: "iOS ships an onboarding tour. Add parity.",
                           sourceFeature: "Onboarding tour"),
            ],
            generatedBy: "anthropic",
            disclaimer: AlignReport.standardDisclaimer)
    }

    @Test("page is fully self-contained — no CDN, no external script/link refs")
    func selfContained() {
        let html = HTMLRender.alignReport(sampleReport())
        #expect(!html.contains("http://"))
        // Only allowed https:// reference is the footer credit link.
        let externalCount = html.components(separatedBy: "https://").count - 1
        #expect(externalCount == 1)
        #expect(html.contains("https://novarch.lol/recap-wins"))
        #expect(!html.contains("<link "))
        #expect(!html.contains("<script src"))
    }

    @Test("matrix carries the disclaimer banner — non-optional output")
    func disclaimerPresent() {
        let html = HTMLRender.alignReport(sampleReport())
        #expect(html.contains("class=\"disclaimer\""))
        #expect(html.contains("Candidates to confirm"))
    }

    @Test("filter chips render one per status plus 'all', with counts")
    func filterChips() {
        let html = HTMLRender.alignReport(sampleReport())
        #expect(html.contains("data-filter=\"all\""))
        #expect(html.contains("data-filter=\"paired\""))
        #expect(html.contains("data-filter=\"equivalent\""))
        #expect(html.contains("data-filter=\"gap_on_a\""))
        #expect(html.contains("data-filter=\"gap_on_b\""))
        #expect(html.contains("data-filter=\"ambiguous\""))
        // Default body class is filter-all, so on first load nothing's hidden.
        #expect(html.contains("class=\"align filter-all\""))
    }

    @Test("every row carries data-status so the filter shim can hide it")
    func rowsHaveStatusAttribute() {
        let html = HTMLRender.alignReport(sampleReport())
        #expect(html.contains("data-status=\"equivalent\""))
        #expect(html.contains("data-status=\"gap_on_b\""))
        #expect(html.contains("data-status=\"ambiguous\""))
    }

    @Test("status badges + confidence pills show on every row")
    func badgesAndConfidence() {
        let html = HTMLRender.alignReport(sampleReport())
        #expect(html.contains("class=\"badge badge-equivalent\""))
        #expect(html.contains("class=\"badge badge-gap\""))
        #expect(html.contains("class=\"badge badge-ambiguous\""))
        // Confidence-banded pills.
        #expect(html.contains("class=\"conf conf-high\""))   // 0.95
        #expect(html.contains("class=\"conf conf-low\""))    // 0.4
    }

    @Test("gap rows show '— missing —' on the side that's missing")
    func missingSideLabel() {
        let html = HTMLRender.alignReport(sampleReport())
        // m2 is gap_on_b: side B is missing.
        #expect(html.contains("— missing —"))
        // The missing row gets a `.missing` class for muted styling.
        #expect(html.contains("class=\"row missing\""))
    }

    @Test("drafted issues render with copy buttons")
    func draftedIssues() {
        let html = HTMLRender.alignReport(sampleReport())
        #expect(html.contains("Drafted issues"))
        #expect(html.contains("Port onboarding tour"))
        #expect(html.contains("data-copy-target=\"issue-0\""))
    }

    @Test("filter shim is included so chips actually filter")
    func filterShimPresent() {
        let html = HTMLRender.alignReport(sampleReport())
        #expect(html.contains("data-filter"))
        // The shim flips body classes on click.
        #expect(html.contains("classList"))
        #expect(html.contains("filter-"))
    }

    @Test("hostile feature titles are HTML-escaped")
    func escapingHostile() {
        var report = sampleReport()
        report.features[0].descriptionA = "<script>alert(1)</script>"
        let html = HTMLRender.alignReport(report)
        #expect(html.contains("&lt;script&gt;"))
        #expect(!html.contains("<script>alert(1)</script>"))
    }
}

// MARK: - Issue formatters

@Suite("IssueFormatter (--issues format)")
struct IssueFormatterTests {
    private let issue = IssueDraft(
        side: "android",
        title: "Port onboarding tour",
        body: "iOS ships an onboarding tour. Add `WidgetKit`-equivalent on Android.\n\n## Acceptance\n\n- Walk-through on first launch\n- **Persists** completion",
        sourceFeature: "Onboarding tour")

    @Test("markdown is the canonical source, with title as ## and side tag")
    func markdownFormat() {
        let out = IssueFormatter.format(issue, as: .markdown)
        #expect(out.contains("## [android] Port onboarding tour"))
        #expect(out.contains("`WidgetKit`"))
        #expect(out.contains("_source: Onboarding tour_"))
    }

    @Test("linear format adds a Labels: line and h1 title")
    func linearFormat() {
        let out = IssueFormatter.format(issue, as: .linear)
        #expect(out.contains("# Port onboarding tour"))
        #expect(out.contains("Labels: parity, android"))
        #expect(out.contains("Source feature:"))
    }

    @Test("github format prefixes Title: and Labels: lines")
    func githubFormat() {
        let out = IssueFormatter.format(issue, as: .github)
        #expect(out.hasPrefix("Title: [android] Port onboarding tour"))
        #expect(out.contains("Labels: parity, port:android"))
        #expect(out.contains("> Source feature"))
    }

    @Test("jira converts headings, bold, and code spans to wiki markup")
    func jiraFormat() {
        let out = IssueFormatter.format(issue, as: .jira)
        #expect(out.contains("h2. [android] Port onboarding tour"))
        // ## Acceptance → h3.
        #expect(out.contains("h3. Acceptance"))
        // `WidgetKit` → {{WidgetKit}}
        #expect(out.contains("{{WidgetKit}}"))
        // **Persists** → *Persists*
        #expect(out.contains("*Persists*"))
        // Bullets demoted to * style
        #expect(out.contains("* Walk-through on first launch"))
        #expect(out.contains("{quote}Source feature:"))
    }

    @Test("unmatched bold marker stays literal in jira output")
    func jiraLenient() {
        let stray = IssueDraft(
            side: "ios", title: "Stray markers",
            body: "Talking about **emphasis without closer", sourceFeature: "")
        let out = IssueFormatter.format(stray, as: .jira)
        // The lone `**` is left literal — the converter doesn't open a Jira
        // bold (`*emphasis...`) it can't close. (Note: `**emphasis` does
        // technically contain `*emphasis`, so this assertion counts the
        // doubled marker, not a single one.)
        #expect(out.contains("**emphasis"))
    }

    @Test("formatAll separates entries with the right rule per format")
    func formatAllSeparators() {
        let issues = [issue, issue]
        let md = IssueFormatter.formatAll(issues, as: .markdown)
        let jr = IssueFormatter.formatAll(issues, as: .jira)
        #expect(md.contains("\n\n---\n\n"))
        #expect(jr.contains("\n----\n\n"))
    }

    @Test("parse maps the documented spellings to enum values")
    func parsing() {
        #expect(IssueFormat.parse("markdown") == .markdown)
        #expect(IssueFormat.parse("Linear") == .linear)
        #expect(IssueFormat.parse("GITHUB") == .github)
        #expect(IssueFormat.parse("jira") == .jira)
        #expect(IssueFormat.parse("notion") == nil)
    }
}

// MARK: - --confirm parity-map updates

@Suite("ParityMapUpdater (--confirm writes back to testthese.toml)")
struct ParityMapUpdaterTests {
    /// Write a temp testthese.toml and return its path.
    private func writeConfig(_ contents: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rw-confirm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("testthese.toml").path
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    @Test("appends a new equivalence block when the product exists")
    func appendNew() throws {
        let path = try writeConfig("""
        [[product]]
        id = "ledgerly"
        name = "Ledgerly"
        """)
        let outcome = try ParityMapUpdater.append(
            a: "Apple Pay checkout", b: "Google Pay checkout",
            note: "platform-native payment",
            productId: "ledgerly", configPath: path)
        #expect(outcome == .appended)
        let updated = try String(contentsOfFile: path, encoding: .utf8)
        #expect(updated.contains("[[product.parity.equivalent]]"))
        #expect(updated.contains("\"Apple Pay checkout\""))
        #expect(updated.contains("\"Google Pay checkout\""))
        #expect(updated.contains("# added by `rw align --confirm`"))
    }

    @Test("re-running on the same pair is a no-op (idempotent)")
    func idempotent() throws {
        let path = try writeConfig("""
        [[product]]
        id = "ledgerly"
        name = "Ledgerly"

        [[product.parity.equivalent]]
        a = "Apple Pay checkout"
        b = "Google Pay checkout"
        """)
        let outcome = try ParityMapUpdater.append(
            a: "Apple Pay checkout", b: "Google Pay checkout",
            note: "platform-native payment",
            productId: "ledgerly", configPath: path)
        #expect(outcome == .alreadyPresent)
    }

    @Test("missing product throws ParityMapError.productNotInConfig")
    func unknownProduct() throws {
        let path = try writeConfig("""
        [[product]]
        id = "other"
        name = "Other"
        """)
        do {
            _ = try ParityMapUpdater.append(
                a: "x", b: "y", note: nil,
                productId: "ledgerly", configPath: path)
            #expect(Bool(false), "expected ParityMapError")
        } catch let err as ParityMapError {
            if case .productNotInConfig(let id) = err {
                #expect(id == "ledgerly")
            } else {
                #expect(Bool(false), "wrong ParityMapError: \(err)")
            }
        }
    }

    @Test("missing config file throws ParityMapError.configMissing")
    func missingConfig() {
        let path = "/tmp/definitely-does-not-exist-\(UUID().uuidString)/testthese.toml"
        do {
            _ = try ParityMapUpdater.append(
                a: "x", b: "y", note: nil,
                productId: "anything", configPath: path)
            #expect(Bool(false), "expected ParityMapError")
        } catch let err as ParityMapError {
            if case .configMissing = err {
                // ok
            } else {
                #expect(Bool(false), "wrong ParityMapError: \(err)")
            }
        } catch {
            #expect(Bool(false), "wrong error type: \(error)")
        }
    }

    @Test("appended block round-trips through the parser")
    func roundTripsThroughParser() throws {
        let path = try writeConfig("""
        [[product]]
        id = "ledgerly"
        name = "Ledgerly"
        """)
        _ = try ParityMapUpdater.append(
            a: "Apple Pay checkout", b: "Google Pay checkout",
            note: "platform-native payment",
            productId: "ledgerly", configPath: path)
        // Parse the updated file and confirm the entry made it in.
        let updated = try String(contentsOfFile: path, encoding: .utf8)
        let parsed = try Config.parse(updated)
        let ledgerly = parsed.product("ledgerly")
        #expect(ledgerly?.parityEquivalent.count == 1)
        #expect(ledgerly?.parityEquivalent[0].a == "Apple Pay checkout")
        #expect(ledgerly?.parityEquivalent[0].b == "Google Pay checkout")
        #expect(ledgerly?.parityEquivalent[0].note == "platform-native payment")
    }
}
