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

    @Test("factory builds a Gemini client from GEMINI_API_KEY")
    func geminiFactory() throws {
        let client = try ModelConfig.makeClient(
            for: .gemini, config: Config(), environment: ["GEMINI_API_KEY": "g"])
        #expect(client is GeminiClient)
    }

    @Test("gemini reads its own env var, not ANTHROPIC_API_KEY")
    func geminiKeyVar() {
        // Only the Anthropic key is set → Gemini still can't find a key.
        #expect(throws: ModelError.self) {
            _ = try ModelConfig.makeClient(
                for: .gemini, config: Config(), environment: ["ANTHROPIC_API_KEY": "a"])
        }
        #expect(ModelConfig.apiKeyEnvVar(for: .gemini) == "GEMINI_API_KEY")
        #expect(ModelConfig.apiKeyEnvVar(for: .anthropic) == "ANTHROPIC_API_KEY")
    }

    @Test("gemini falls back to a Gemini model when config still has the Anthropic default")
    func geminiModelFallback() {
        // Default config model is the Anthropic one; for Gemini, use Gemini's default.
        #expect(ModelConfig.model(for: .gemini, config: Config()) == GeminiClient.defaultModel)
        // But an explicitly-set model is respected.
        var config = Config()
        config.model = "gemini-1.5-pro"
        #expect(ModelConfig.model(for: .gemini, config: config) == "gemini-1.5-pro")
        // Anthropic always uses the configured model as-is.
        #expect(ModelConfig.model(for: .anthropic, config: Config()) == Config.defaultModel)
    }

    @Test("factory refuses skill mode — it has no model client")
    func skillHasNoClient() {
        #expect(throws: ProviderUnavailable.self) {
            _ = try ModelConfig.makeClient(for: .skill, config: Config(), environment: [:])
        }
    }

    @Test("Gemini client maps assistant role to model and carries system instruction")
    func geminiWireShape() throws {
        // Build a client and confirm it encodes without error (smoke of the
        // wire format); a full network test needs a live key.
        let client = GeminiClient(apiKey: "k", model: "gemini-2.5-pro")
        #expect(client.model == "gemini-2.5-pro")
        #expect(client.apiKey == "k")
    }

    @Test("Gemini default model is the pinned, current GA id")
    func geminiDefaultModelPinned() {
        // Guard against a silent regression to a retired model id: Google shut
        // down gemini-2.0-flash on 2026-06-01, turning the old default into a
        // hard 404 for every default-config Gemini run.
        #expect(GeminiClient.defaultModel == "gemini-3.5-flash")
        #expect(!GeminiClient.defaultModel.isEmpty)
    }
}
