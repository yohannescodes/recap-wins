import Foundation

/// Resolves the API key and model into a ready `ModelClient`.
///
/// Key precedence (PRD §8 keeps config in-repo and human-readable, but a key
/// shouldn't live in a committed file): the `ANTHROPIC_API_KEY` environment
/// variable wins, falling back to an optional `api_key` in config.
public enum ModelConfig {
    /// Resolve the API key from environment, then config. Throws if neither.
    public static func resolveAPIKey(
        config: Config,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String {
        if let envKey = environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        if let configKey = config.apiKey, !configKey.isEmpty {
            return configKey
        }
        throw ModelError.missingAPIKey
    }

    /// Build a live Anthropic client from config + environment.
    public static func makeClient(
        config: Config,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AnthropicClient {
        let key = try resolveAPIKey(config: config, environment: environment)
        return AnthropicClient(apiKey: key, model: config.model)
    }

    /// Build a `ModelClient` for an API-calling provider. Skill mode does not go
    /// through here — it emits a `SkillEnvelope` instead of calling a model.
    ///
    /// This is the single place a new provider plugs in: add a `case` returning
    /// its client. Gemini is reserved here as the next slot.
    public static func makeClient(
        for provider: Provider,
        config: Config,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> any ModelClient {
        switch provider {
        case .anthropic:
            return try makeClient(config: config, environment: environment)
        case .gemini:
            throw ProviderUnavailable(
                provider: .gemini,
                reason: "Gemini support isn't implemented yet. Use --provider anthropic or --provider skill."
            )
        case .skill:
            throw ProviderUnavailable(
                provider: .skill,
                reason: "skill mode emits JSON for a host agent and has no model client."
            )
        }
    }
}
