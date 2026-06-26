import Foundation

/// Which backend renders the semantic prose (PRD §5). The deterministic core is
/// provider-independent; only the prose commands (`new`, `notes`) consult this.
///
/// - `anthropic`: call the Anthropic API directly (CLI mode). Needs an API key,
///   billed pay-as-you-go.
/// - `skill`: emit the change report + the rendered prompt as JSON for a host
///   agent to complete (agent-skill mode, PRD §5/§10). No API key, no network —
///   the host agent (Claude Code, Cowork, …) is the model.
/// - `gemini`: Google Gemini API. Reserved — not yet implemented.
public enum Provider: String, Sendable, CaseIterable {
    case anthropic
    case skill
    case gemini

    /// True if this provider makes its own API call (and thus needs a key).
    /// `skill` does not — the host agent supplies the model.
    public var callsAPI: Bool {
        switch self {
        case .anthropic, .gemini: return true
        case .skill: return false
        }
    }

    /// Human-readable label for messages.
    public var displayName: String {
        switch self {
        case .anthropic: return "Anthropic API"
        case .skill: return "agent-skill mode"
        case .gemini: return "Gemini API"
        }
    }
}

/// Raised when a provider is selected but not yet available.
public struct ProviderUnavailable: Error, CustomStringConvertible, Equatable {
    public let provider: Provider
    public let reason: String

    public init(provider: Provider, reason: String) {
        self.provider = provider
        self.reason = reason
    }

    public var description: String {
        "Provider '\(provider.rawValue)' is unavailable: \(reason)"
    }
}
