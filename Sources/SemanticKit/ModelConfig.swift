import Foundation

/// Resolves the API key and model into a ready `ModelClient`.
///
/// Key precedence (PRD §8 keeps config in-repo and human-readable, but a key
/// shouldn't live in a committed file): the `ANTHROPIC_API_KEY` environment
/// variable wins, falling back to an optional `api_key` in config.
public enum ModelConfig {
    /// The environment variable each API provider reads its key from.
    static func apiKeyEnvVar(for provider: Provider) -> String {
        switch provider {
        case .anthropic, .skill: return "ANTHROPIC_API_KEY"
        case .gemini: return "GEMINI_API_KEY"
        }
    }

    /// Resolve the API key for a provider: its env var wins, then `api_key` in
    /// config. Throws `missingAPIKey` if neither is set.
    public static func resolveAPIKey(
        for provider: Provider = .anthropic,
        config: Config,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String {
        if let envKey = environment[apiKeyEnvVar(for: provider)], !envKey.isEmpty {
            return envKey
        }
        if let configKey = config.apiKey, !configKey.isEmpty {
            return configKey
        }
        throw ModelError.missingAPIKey(provider: provider)
    }

    /// The model id to use for a provider: the configured `model`, unless it's
    /// still the Anthropic default while a different provider is selected — then
    /// fall back to that provider's own default.
    static func model(for provider: Provider, config: Config) -> String {
        switch provider {
        case .anthropic, .skill:
            return config.model
        case .gemini:
            // If the user left the default Anthropic model but asked for Gemini,
            // use Gemini's default rather than sending a claude-* id to Google.
            return config.model == Config.defaultModel ? GeminiClient.defaultModel : config.model
        }
    }

    /// Build a live Anthropic client from config + environment.
    public static func makeClient(
        config: Config,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AnthropicClient {
        let key = try resolveAPIKey(for: .anthropic, config: config, environment: environment)
        return AnthropicClient(apiKey: key, model: config.model)
    }

    /// Build a `ModelClient` for an API-calling provider. Skill mode does not go
    /// through here — it emits a `SkillEnvelope` instead of calling a model.
    ///
    /// This is the single place a new provider plugs in: add a `case` returning
    /// its client.
    public static func makeClient(
        for provider: Provider,
        config: Config,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> any ModelClient {
        switch provider {
        case .anthropic:
            let key = try resolveAPIKey(for: .anthropic, config: config, environment: environment)
            return AnthropicClient(apiKey: key, model: model(for: .anthropic, config: config))
        case .gemini:
            let key = try resolveAPIKey(for: .gemini, config: config, environment: environment)
            return GeminiClient(apiKey: key, model: model(for: .gemini, config: config))
        case .skill:
            throw ProviderUnavailable(
                provider: .skill,
                reason: "skill mode emits JSON for a host agent and has no model client."
            )
        }
    }
}
