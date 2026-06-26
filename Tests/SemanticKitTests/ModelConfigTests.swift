import Testing
@testable import SemanticKit

@Suite("API key resolution")
struct ModelConfigTests {
    @Test("environment key takes precedence over config")
    func envWins() throws {
        var config = Config()
        config.apiKey = "from-config"
        let key = try ModelConfig.resolveAPIKey(
            config: config,
            environment: ["ANTHROPIC_API_KEY": "from-env"]
        )
        #expect(key == "from-env")
    }

    @Test("falls back to config key when env is absent")
    func configFallback() throws {
        var config = Config()
        config.apiKey = "from-config"
        let key = try ModelConfig.resolveAPIKey(config: config, environment: [:])
        #expect(key == "from-config")
    }

    @Test("empty env key is ignored, config used")
    func emptyEnvIgnored() throws {
        var config = Config()
        config.apiKey = "from-config"
        let key = try ModelConfig.resolveAPIKey(
            config: config,
            environment: ["ANTHROPIC_API_KEY": ""]
        )
        #expect(key == "from-config")
    }

    @Test("throws missingAPIKey when neither is set")
    func missing() {
        #expect(throws: ModelError.missingAPIKey(provider: .anthropic)) {
            try ModelConfig.resolveAPIKey(config: Config(), environment: [:])
        }
    }
}
