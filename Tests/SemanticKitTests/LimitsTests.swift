import Testing
import Foundation
@testable import SemanticKit

@Suite("Limits & cap resolution")
struct LimitsTests {
    @Test("ceiling keys off platform for what-new")
    func whatNewPlatform() {
        let l = ReviewNoteLimits.fallback
        #expect(l.ceiling(for: .whatNew, platform: .iOS) == 0)       // TestFlight uncapped
        #expect(l.ceiling(for: .whatNew, platform: .android) == 500) // Play 500/lang
    }

    @Test("store ceilings come from fallback values")
    func storeCeilings() {
        let l = ReviewNoteLimits.fallback
        #expect(l.ceiling(for: .ascUpdate, platform: .iOS) == 4000)
        #expect(l.ceiling(for: .gpUpdate, platform: .android) == 500)
        #expect(l.ceiling(for: .pr, platform: .iOS) == 0)
    }

    @Test("--limit only tightens, never loosens past the ceiling")
    func limitTightensOnly() {
        let l = ReviewNoteLimits.fallback
        // Trying to loosen a 4000 cap to 9000 is ignored — ceiling stays 4000.
        let loosen = ResolvedLimit.resolve(
            target: .ascUpdate, platform: .iOS, limits: l, softTarget: nil, userLimit: 9000)
        #expect(loosen.ceiling == 4000)
        // Tightening to 1000 works.
        let tighten = ResolvedLimit.resolve(
            target: .ascUpdate, platform: .iOS, limits: l, softTarget: nil, userLimit: 1000)
        #expect(tighten.ceiling == 1000)
    }

    @Test("--limit caps an otherwise-uncapped target")
    func limitCapsUncapped() {
        let l = ReviewNoteLimits.fallback
        let resolved = ResolvedLimit.resolve(
            target: .pr, platform: .iOS, limits: l, softTarget: nil, userLimit: 500)
        #expect(resolved.ceiling == 500)
    }

    @Test("soft target is clamped to the effective ceiling")
    func softClampedToCeiling() {
        let l = ReviewNoteLimits.fallback
        // Soft 800 under a tightened 500 ceiling clamps to 500.
        let resolved = ResolvedLimit.resolve(
            target: .gpUpdate, platform: .android, limits: l, softTarget: 800, userLimit: nil)
        #expect(resolved.ceiling == 500)
        #expect(resolved.softTarget == 500)
    }

    @Test("overflow detection respects uncapped (0)")
    func overflow() {
        #expect(ResolvedLimit(ceiling: 500, softTarget: nil).overflows(501))
        #expect(!ResolvedLimit(ceiling: 500, softTarget: nil).overflows(500))
        #expect(!ResolvedLimit(ceiling: 0, softTarget: nil).overflows(10_000)) // uncapped
    }

    @Test("TTL parsing handles d/h/m/s")
    func ttl() {
        #expect(LimitsProvider.parseTTL("30d") == TimeInterval(30 * 24 * 60 * 60))
        #expect(LimitsProvider.parseTTL("12h") == TimeInterval(12 * 60 * 60))
        #expect(LimitsProvider.parseTTL("45m") == TimeInterval(45 * 60))
        #expect(LimitsProvider.parseTTL("90s") == TimeInterval(90))
        #expect(LimitsProvider.parseTTL("nonsense") == nil)
        #expect(LimitsProvider.parseTTL(nil) == nil)
    }

    @Test("manifest decodes from JSON")
    func manifestDecode() throws {
        let json = """
        { "review_notes_limits": {
            "pr": 0, "asc_reviewer": 0, "what_new_ios": 0,
            "what_new_android": 500, "asc_update": 4000, "gp_update": 500 } }
        """
        let m = try JSONDecoder().decode(LimitsManifest.self, from: Data(json.utf8))
        #expect(m.reviewNoteLimits.ascUpdate == 4000)
    }

    @Test("provider falls back to config when no manifest URL")
    func providerFallback() async {
        var config = Config()
        config.reviewNoteLimits.ascUpdate = 1234   // distinctive fallback
        let provider = LimitsProvider(config: config)
        let limits = await provider.limits()
        #expect(limits.ascUpdate == 1234)
    }
}
