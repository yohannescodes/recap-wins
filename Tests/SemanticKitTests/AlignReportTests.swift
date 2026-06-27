import Testing
import Foundation
import RecapCore
@testable import SemanticKit

@Suite("AlignReport model")
struct AlignReportTests {
    private let snapshotA = LedgerSnapshot(
        portName: "ios", repositoryPath: "/tmp/a", ref: "main",
        headSHA: "aaaaaaa", since: nil, sinceSHA: nil,
        features: [
            LedgerFeature(id: "1", title: "Apple Pay checkout",
                          scope: nil, origin: .declared,
                          sha: "1111111", date: Date(timeIntervalSince1970: 0)),
        ])
    private let snapshotB = LedgerSnapshot(
        portName: "android", repositoryPath: "/tmp/b", ref: "main",
        headSHA: "bbbbbbb", since: nil, sinceSHA: nil,
        features: [
            LedgerFeature(id: "2", title: "Google Pay checkout",
                          scope: nil, origin: .declared,
                          sha: "2222222", date: Date(timeIntervalSince1970: 0)),
        ])

    @Test("slice 1 report carries both ledgers and the mandatory disclaimer")
    func slice1Shape() {
        let report = AlignReport(
            product: "ledgerly",
            portA: snapshotA, portB: snapshotB,
            since: "v1.0")
        #expect(report.product == "ledgerly")
        #expect(report.portA.portName == "ios")
        #expect(report.portB.portName == "android")
        #expect(report.since == "v1.0")
        // Slice 1: no features matched yet, no issues drafted.
        #expect(report.features.isEmpty)
        #expect(report.suggestedIssues.isEmpty)
        #expect(report.summary == AlignSummary())
        // The FRD insists on the disclaimer being non-optional output.
        #expect(report.disclaimer.contains("Candidates to confirm"))
    }

    @Test("AlignSummary aggregates from feature matches")
    func summaryFromFeatures() {
        let features = [
            FeatureMatch(id: "1", status: .paired, confidence: 0.9),
            FeatureMatch(id: "2", status: .paired, confidence: 0.8),
            FeatureMatch(id: "3", status: .equivalent, confidence: 0.7),
            FeatureMatch(id: "4", status: .gapOnA, confidence: 0.8),
            FeatureMatch(id: "5", status: .gapOnB, confidence: 0.6),
            FeatureMatch(id: "6", status: .ambiguous, confidence: 0.4),
        ]
        let s = AlignSummary.from(features)
        #expect(s.paired == 2)
        #expect(s.equivalent == 1)
        #expect(s.gapOnA == 1)
        #expect(s.gapOnB == 1)
        #expect(s.ambiguous == 1)
    }

    @Test("AlignReport round-trips through JSON")
    func roundTripsJSON() throws {
        let report = AlignReport(
            product: "x",
            portA: snapshotA, portB: snapshotB,
            since: "v1.0")
        let json = try report.jsonString()
        // Match the encoder's iso8601 dates — the encoder is canonical for
        // anyone parsing our output, so the test mirrors it.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AlignReport.self, from: Data(json.utf8))
        #expect(decoded == report)
        // Slice 1 has empty features, so gap_on_a/gap_on_b only appear inside
        // the summary block — assert on that instead of feature-level keys.
        #expect(json.contains("\"gap_on_a\""))
        #expect(json.contains("\"gap_on_b\""))
    }

    @Test("MatchStatus rawValues use the FRD-documented snake_case")
    func matchStatusRawValues() {
        #expect(MatchStatus.paired.rawValue == "paired")
        #expect(MatchStatus.equivalent.rawValue == "equivalent")
        #expect(MatchStatus.gapOnA.rawValue == "gap_on_a")
        #expect(MatchStatus.gapOnB.rawValue == "gap_on_b")
        #expect(MatchStatus.ambiguous.rawValue == "ambiguous")
    }
}

@Suite("Config (ports + parity)")
struct ConfigPortsParityTests {
    @Test("[product.ports] is parsed onto the right product")
    func portsBlockParses() throws {
        let toml = """
        [[product]]
        id = "ledgerly"
        name = "Ledgerly"
        voice = "v"

        [product.ports]
        a = { name = "ios", path = "../ledgerly-ios", base = "main" }
        b = { name = "android", path = "../ledgerly-android", base = "main" }
        since = "v1.0"
        """
        let c = try Config.parse(toml)
        let p = c.product("ledgerly")
        #expect(p != nil)
        #expect(p?.ports?.a.name == "ios")
        #expect(p?.ports?.a.path == "../ledgerly-ios")
        #expect(p?.ports?.a.base == "main")
        #expect(p?.ports?.b.name == "android")
        #expect(p?.ports?.b.path == "../ledgerly-android")
        #expect(p?.ports?.since == "v1.0")
    }

    @Test("port `base` defaults to main when omitted")
    func portsBaseDefaults() throws {
        let toml = """
        [[product]]
        id = "x"
        name = "X"

        [product.ports]
        a = { name = "ios", path = "../ios" }
        b = { name = "android", path = "../android" }
        """
        let c = try Config.parse(toml)
        #expect(c.product("x")?.ports?.a.base == "main")
        #expect(c.product("x")?.ports?.b.base == "main")
        #expect(c.product("x")?.ports?.since == nil)
    }

    @Test("[[product.parity.equivalent]] entries accumulate per product")
    func parityEntriesAccumulate() throws {
        let toml = """
        [[product]]
        id = "ledgerly"
        name = "Ledgerly"

        [[product.parity.equivalent]]
        a = "Apple Pay checkout"
        b = "Google Pay checkout"
        note = "platform-native payment"

        [[product.parity.equivalent]]
        a = "Sign in with Apple"
        b = "Google Sign-In"
        """
        let p = try Config.parse(toml).product("ledgerly")
        #expect(p?.parityEquivalent.count == 2)
        #expect(p?.parityEquivalent[0].a == "Apple Pay checkout")
        #expect(p?.parityEquivalent[0].b == "Google Pay checkout")
        #expect(p?.parityEquivalent[0].note == "platform-native payment")
        #expect(p?.parityEquivalent[1].note == nil)
    }

    @Test("ports + parity together on one product, then a sibling product")
    func portsParityIsolatedPerProduct() throws {
        let toml = """
        [[product]]
        id = "ledgerly"
        name = "Ledgerly"

        [product.ports]
        a = { name = "ios", path = "../ios" }
        b = { name = "android", path = "../android" }

        [[product.parity.equivalent]]
        a = "Apple Pay"
        b = "Google Pay"

        [[product]]
        id = "dots"
        name = "DOTS"
        voice = "calm"
        """
        let c = try Config.parse(toml)
        let led = c.product("ledgerly")
        let dots = c.product("dots")
        #expect(led?.ports != nil)
        #expect(led?.parityEquivalent.count == 1)
        // DOTS has no ports or parity — they belong to ledgerly only.
        #expect(dots?.ports == nil)
        #expect(dots?.parityEquivalent.isEmpty == true)
        #expect(dots?.voice == "calm")
    }

    @Test("a product without ports stays nil (half-configured pairs are dropped)")
    func halfConfiguredPortsAreDropped() throws {
        let toml = """
        [[product]]
        id = "x"
        name = "X"

        [product.ports]
        a = { name = "ios", path = "../ios" }
        """
        let c = try Config.parse(toml)
        // b is missing → ports is nil (better than a half-pair the matcher
        // would later trip on).
        #expect(c.product("x")?.ports == nil)
    }
}
