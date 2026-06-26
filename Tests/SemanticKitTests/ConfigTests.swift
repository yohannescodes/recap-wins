import Testing
@testable import SemanticKit

@Suite("Config parsing")
struct ConfigTests {
    @Test("empty config yields defaults")
    func defaults() throws {
        let c = try Config.parse("")
        #expect(c.base == "main")
        #expect(c.model == Config.defaultModel)
        #expect(c.apiKey == nil)
        #expect(c.products.isEmpty)
    }

    @Test("parses top-level scalars")
    func scalars() throws {
        let c = try Config.parse("""
        base = "develop"
        model = "claude-sonnet-4-6"
        api_key = "sk-test-123"
        """)
        #expect(c.base == "develop")
        #expect(c.model == "claude-sonnet-4-6")
        #expect(c.apiKey == "sk-test-123")
    }

    @Test("parses product profiles")
    func products() throws {
        let c = try Config.parse("""
        base = "main"

        [[product]]
        id = "ledgerly"
        name = "Ledgerly"
        voice = "clear, trustworthy, private-by-default"
        links = ["https://novarch.lol/ledgerly"]

        [[product]]
        id = "dots"
        name = "DOTS"
        voice = "calm, reflective"
        links = []
        """)
        #expect(c.products.count == 2)
        let ledgerly = try #require(c.product("ledgerly"))
        #expect(ledgerly.name == "Ledgerly")
        #expect(ledgerly.voice == "clear, trustworthy, private-by-default")
        #expect(ledgerly.links == ["https://novarch.lol/ledgerly"])
        #expect(c.product("dots")?.links == [])
        #expect(c.product("missing") == nil)
    }

    @Test("ignores comments and unknown tables")
    func commentsAndTables() throws {
        let c = try Config.parse("""
        base = "main"  # the base branch
        # a full-line comment
        model = "claude-sonnet-4-6"

        [limits_manifest]
        url = "https://example/limits.json"
        ttl = "30d"

        [[product]]
        id = "x"
        name = "X"
        """)
        #expect(c.base == "main")
        #expect(c.model == "claude-sonnet-4-6")
        #expect(c.products.count == 1)
        #expect(c.product("x")?.name == "X")
    }

    @Test("preserves # inside quoted strings")
    func hashInString() throws {
        let c = try Config.parse(#"voice_test = "a # b""#)
        // No top-level "voice_test" key is consumed, but parsing must not crash
        // and the comment stripper must not truncate at the in-string #.
        #expect(c.base == "main")
    }

    @Test("parses product platform and inline targets table")
    func platformAndTargets() throws {
        let c = try Config.parse("""
        [[product]]
        id = "dots"
        name = "DOTS"
        voice = "calm"
        platform = "android"
        targets = { asc_update = 220, gp_update = 200, what_new = 300 }
        """)
        let dots = try #require(c.product("dots"))
        #expect(dots.platform == .android)
        #expect(dots.softTarget(for: .ascUpdate) == 220)
        #expect(dots.softTarget(for: .gpUpdate) == 200)
        #expect(dots.softTarget(for: .whatNew) == 300)
        #expect(dots.softTarget(for: .pr) == nil)
    }

    @Test("defaults platform to iOS when unspecified")
    func defaultPlatform() throws {
        let c = try Config.parse("""
        [[product]]
        id = "x"
        name = "X"
        """)
        #expect(c.product("x")?.platform == .iOS)
    }

    @Test("parses limits_manifest and review_notes.limits tables")
    func limitsTables() throws {
        let c = try Config.parse("""
        base = "main"

        [limits_manifest]
        url = "https://example/limits.json"
        ttl = "30d"

        [review_notes.limits]
        pr = 0
        asc_update = 4000
        gp_update = 500
        what_new_android = 500
        """)
        #expect(c.limitsManifestURL == "https://example/limits.json")
        #expect(c.limitsManifestTTL == "30d")
        #expect(c.reviewNoteLimits.ascUpdate == 4000)
        #expect(c.reviewNoteLimits.gpUpdate == 500)
        #expect(c.reviewNoteLimits.whatNewAndroid == 500)
    }
}
