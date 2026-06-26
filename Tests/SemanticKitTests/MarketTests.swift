import Testing
import Foundation
import RecapCore
@testable import SemanticKit

@Suite("Market pack")
struct MarketTests {
    private func report() -> ChangeReport {
        let files = [FileChange(path: "Sources/Export.swift", insertions: 80, deletions: 4, status: "A")]
        let vitals = Vitals(features: 1, fixes: 0, chores: 0, filesChanged: 1,
                            insertions: 80, deletions: 4, contributors: [], branchCount: 1, hotspots: files)
        return ChangeReport(
            range: ChangeRange(base: "main", head: "HEAD", baseSHA: "b", headSHA: "h", mergeBaseSHA: "b"),
            commits: [], files: files, branches: [], vitals: vitals, riskFlags: [])
    }

    private let ledgerly = ProductProfile(
        id: "led", name: "Ledgerly",
        voice: "clear, trustworthy, private-by-default",
        links: ["https://novarch.lol/ledgerly"], platform: .iOS, targets: [:])

    @Test("piece ceilings match the market limits")
    func ceilings() {
        let l = MarketLimits.fallback
        #expect(MarketPiece.promotionalText.ceiling(l) == 170)
        #expect(MarketPiece.subtitle.ceiling(l) == 30)
        #expect(MarketPiece.shortDescription.ceiling(l) == 80)
        #expect(MarketPiece.tweet.ceiling(l) == 280)
        #expect(MarketPiece.whatsNew.ceiling(l) == 0)   // uncapped editorial
        #expect(MarketPiece.post.ceiling(l) == 0)
    }

    @Test("market limits decode from config TOML")
    func configLimits() throws {
        let c = try Config.parse("""
        [market.limits]
        asc_promotional_text = 150
        asc_subtitle = 25
        gp_short_description = 70
        """)
        #expect(c.marketLimits.ascPromotionalText == 150)
        #expect(c.marketLimits.ascSubtitle == 25)
        #expect(c.marketLimits.gpShortDescription == 70)
    }

    @Test("prompt carries voice, product name, and cap")
    func prompt() {
        let req = PromptBuilder.marketPiece(report(), piece: .subtitle, product: ledgerly, ceiling: 30)
        #expect(req.system.contains("clear, trustworthy"))
        #expect(req.system.contains("Ledgerly"))
        #expect(req.system.contains("30 characters"))
    }

    @Test("engine renders every requested piece")
    func enginePack() async throws {
        let mock = MockModelClient(response: "Track your money, simply.")
        let engine = SemanticEngine(client: mock)
        let results = try await engine.marketPack(
            report(), pieces: [.whatsNew, .subtitle, .tweet], product: ledgerly, limits: .fallback)
        #expect(results.count == 3)
        #expect(results.map(\.piece) == [.whatsNew, .subtitle, .tweet])
    }

    @Test("engine warns on overflow, never truncates")
    func overflowWarns() async throws {
        // 40 chars, over the 30-char subtitle cap.
        let mock = MockModelClient(response: String(repeating: "x", count: 40))
        let engine = SemanticEngine(client: mock)
        let results = try await engine.marketPack(
            report(), pieces: [.subtitle], product: ledgerly, limits: .fallback)
        #expect(results[0].text.count == 40)             // not truncated
        #expect(results[0].overflowWarning != nil)
        #expect(results[0].overflowWarning?.contains("30") == true)
    }

    @Test("skill mode emits one envelope per piece with caps")
    func skillEnvelopes() {
        let envelopes = SkillEnvelope.forMarket(
            report(), pieces: [.subtitle, .post], product: ledgerly, limits: .fallback)
        #expect(envelopes.count == 2)
        #expect(envelopes[0].command == "market")
        #expect(envelopes[0].target == "subtitle")
        #expect(envelopes[0].ceilingChars == 30)
        #expect(envelopes[1].ceilingChars == 0)          // post is uncapped
    }
}
