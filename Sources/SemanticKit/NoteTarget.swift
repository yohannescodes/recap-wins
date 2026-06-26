import Foundation

/// The destination a `rw notes` invocation renders for (PRD §6.1). Each target
/// has its own audience, tone, and char ceiling.
public enum NoteTarget: String, Sendable, CaseIterable {
    /// Pull request description — technical, for a reviewer. Uncapped.
    case pr
    /// App Store Connect → App Review notes — Apple's review team, private.
    case ascReviewer
    /// TestFlight "What to Test" (iOS) / Play testing notes (Android), beta testers.
    case whatNew
    /// App Store "What's New in This Version" — public iOS users, product voice.
    case ascUpdate
    /// Google Play "What's new" — public Android users, product voice.
    case gpUpdate

    /// True if the target's copy should be rendered in the product's voice
    /// (user-facing store copy). Internal/technical targets are voice-neutral.
    public var usesProductVoice: Bool {
        switch self {
        case .pr, .ascReviewer: return false
        case .whatNew, .ascUpdate, .gpUpdate: return true
        }
    }

    /// True if a `--product` profile is required to render this target well.
    public var requiresProduct: Bool { usesProductVoice }

    /// Human-readable destination name for messages.
    public var displayName: String {
        switch self {
        case .pr: return "PR description"
        case .ascReviewer: return "App Review notes"
        case .whatNew: return "TestFlight / Play testing notes"
        case .ascUpdate: return "App Store \"What's New\""
        case .gpUpdate: return "Google Play release notes"
        }
    }
}

/// The mobile platform a product targets. Drives the `--what-new` cap, which is
/// generous on iOS (TestFlight) but tight on Android (Play, 500/lang).
public enum Platform: String, Sendable {
    case iOS
    case android
}
