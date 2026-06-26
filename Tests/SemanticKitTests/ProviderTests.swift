import Testing
@testable import SemanticKit

@Suite("Provider selection")
struct ProviderTests {
    @Test("only skill mode is key-free")
    func callsAPI() {
        #expect(Provider.anthropic.callsAPI)
        #expect(Provider.gemini.callsAPI)
        #expect(!Provider.skill.callsAPI)
    }

    @Test("config parses the provider key")
    func parseProvider() throws {
        #expect(try Config.parse("provider = \"skill\"").provider == .skill)
        #expect(try Config.parse("provider = \"anthropic\"").provider == .anthropic)
        // Unknown value leaves the default untouched.
        #expect(try Config.parse("provider = \"nope\"").provider == .anthropic)
        // Absent key → default.
        #expect(try Config.parse("base = \"main\"").provider == .anthropic)
    }

    @Test("factory builds anthropic client with a key")
    func anthropicFactory() throws {
        var config = Config(provider: .anthropic)
        config.model = "claude-sonnet-4-6"
        let client = try ModelConfig.makeClient(
            for: .anthropic, config: config, environment: ["ANTHROPIC_API_KEY": "k"])
        #expect(client is AnthropicClient)
    }

    @Test("factory reports gemini as unavailable, not a crash")
    func geminiUnavailable() {
        #expect(throws: ProviderUnavailable.self) {
            _ = try ModelConfig.makeClient(
                for: .gemini, config: Config(), environment: ["GEMINI_API_KEY": "k"])
        }
    }

    @Test("factory refuses skill mode — it has no model client")
    func skillHasNoClient() {
        #expect(throws: ProviderUnavailable.self) {
            _ = try ModelConfig.makeClient(for: .skill, config: Config(), environment: [:])
        }
    }
}
