import Foundation

/// One piece of a marketing content pack (PRD §6, §6.1, §8). `rw market` produces
/// several of these for the new features, in a product's voice.
///
/// These are the *announcement* pieces — distinct from the store-native release
/// note that `rw notes --asc-update`/`--gp-update` emits. A few pieces map to
/// hard store-metadata ceilings (§8 `[market.limits]`); the longer-form social
/// pieces are uncapped editorial.
public enum MarketPiece: String, Sendable, CaseIterable {
    /// App Store "What's New" style announcement blurb.
    case whatsNew
    /// App Store promotional text (≤170).
    case promotionalText
    /// App Store subtitle (≤30).
    case subtitle
    /// Google Play short description (≤80).
    case shortDescription
    /// A short social post (e.g. for a feed).
    case post
    /// A tweet-length blurb.
    case tweet

    /// Human-readable label for the rendered pack.
    public var title: String {
        switch self {
        case .whatsNew: return "What's New"
        case .promotionalText: return "App Store promotional text"
        case .subtitle: return "App Store subtitle"
        case .shortDescription: return "Google Play short description"
        case .post: return "Social post"
        case .tweet: return "Tweet"
        }
    }

    /// The hard char ceiling for this piece (0 = uncapped editorial).
    public func ceiling(_ limits: MarketLimits) -> Int {
        switch self {
        case .promotionalText: return limits.ascPromotionalText
        case .subtitle: return limits.ascSubtitle
        case .shortDescription: return limits.gpShortDescription
        case .tweet: return 280
        case .whatsNew, .post: return 0
        }
    }
}

/// Marketing-field char ceilings (PRD §8 `[market.limits]`). Hard caps for the
/// store-metadata pieces; verify in-console before a release, stores adjust them.
public struct MarketLimits: Codable, Sendable, Equatable {
    public var ascPromotionalText: Int
    public var ascSubtitle: Int
    public var gpShortDescription: Int

    /// Baked-in offline fallback from PRD §8.
    public static let fallback = MarketLimits(
        ascPromotionalText: 170, ascSubtitle: 30, gpShortDescription: 80
    )

    public init(ascPromotionalText: Int, ascSubtitle: Int, gpShortDescription: Int) {
        self.ascPromotionalText = ascPromotionalText
        self.ascSubtitle = ascSubtitle
        self.gpShortDescription = gpShortDescription
    }

    enum CodingKeys: String, CodingKey {
        case ascPromotionalText = "asc_promotional_text"
        case ascSubtitle = "asc_subtitle"
        case gpShortDescription = "gp_short_description"
    }
}

/// One rendered piece of the pack: its title, the prose, and any cap warning.
public struct MarketPieceResult: Sendable, Equatable {
    public var piece: MarketPiece
    public var text: String
    /// Non-nil when the text overflows the piece's hard ceiling. Warn, never truncate.
    public var overflowWarning: String?

    public init(piece: MarketPiece, text: String, overflowWarning: String?) {
        self.piece = piece
        self.text = text
        self.overflowWarning = overflowWarning
    }
}
