import Foundation

/// Hard platform char ceilings for the notes targets (PRD §6.1/§8). A value of
/// `0` means uncapped (the store form is the authority). These are ceilings,
/// never preferences — the tool warns on overflow, `--limit` only tightens.
public struct ReviewNoteLimits: Codable, Sendable, Equatable {
    public var pr: Int
    public var ascReviewer: Int
    public var whatNewIOS: Int
    public var whatNewAndroid: Int
    public var ascUpdate: Int
    public var gpUpdate: Int

    /// Baked-in offline fallback values from PRD §8. Used when the manifest is
    /// unreachable or stale.
    public static let fallback = ReviewNoteLimits(
        pr: 0, ascReviewer: 0, whatNewIOS: 0, whatNewAndroid: 500,
        ascUpdate: 4000, gpUpdate: 500
    )

    public init(pr: Int, ascReviewer: Int, whatNewIOS: Int, whatNewAndroid: Int, ascUpdate: Int, gpUpdate: Int) {
        self.pr = pr
        self.ascReviewer = ascReviewer
        self.whatNewIOS = whatNewIOS
        self.whatNewAndroid = whatNewAndroid
        self.ascUpdate = ascUpdate
        self.gpUpdate = gpUpdate
    }

    enum CodingKeys: String, CodingKey {
        case pr
        case ascReviewer = "asc_reviewer"
        case whatNewIOS = "what_new_ios"
        case whatNewAndroid = "what_new_android"
        case ascUpdate = "asc_update"
        case gpUpdate = "gp_update"
    }

    /// The ceiling (chars) for a target. `--what-new` keys off platform: iOS is
    /// generous (TestFlight), Android is the tight 500/lang Play limit.
    /// Returns 0 for uncapped.
    public func ceiling(for target: NoteTarget, platform: Platform) -> Int {
        switch target {
        case .pr: return pr
        case .ascReviewer: return ascReviewer
        case .whatNew: return platform == .iOS ? whatNewIOS : whatNewAndroid
        case .ascUpdate: return ascUpdate
        case .gpUpdate: return gpUpdate
        case .changelog: return 0
        }
    }
}

/// The fetched manifest shape (PRD §6.1): the published caps, kept current
/// out-of-band so a store-policy change is a one-line manifest update, not code.
public struct LimitsManifest: Codable, Sendable, Equatable {
    public var reviewNoteLimits: ReviewNoteLimits

    enum CodingKeys: String, CodingKey {
        case reviewNoteLimits = "review_notes_limits"
    }

    public init(reviewNoteLimits: ReviewNoteLimits) {
        self.reviewNoteLimits = reviewNoteLimits
    }
}

/// Resolves the effective ceiling for a render: the per-product soft target,
/// the hard ceiling, and any `--limit` tightening, combined per the PRD rules.
public struct ResolvedLimit: Sendable, Equatable {
    /// Hard platform ceiling (0 = uncapped). Output must never exceed this.
    public var ceiling: Int
    /// Soft editorial target the model aims for (nil = no specific aim).
    public var softTarget: Int?

    public init(ceiling: Int, softTarget: Int?) {
        self.ceiling = ceiling
        self.softTarget = softTarget
    }

    /// True if `count` characters overflow the hard ceiling (0 = never).
    public func overflows(_ count: Int) -> Bool {
        ceiling > 0 && count > ceiling
    }

    /// Resolve the effective limit for a render from the platform ceiling, the
    /// product's soft target, and an optional `--limit` override.
    ///
    /// Rules (PRD §6.1/§8): `--limit` only TIGHTENS — it can lower the ceiling
    /// and the aim, but never raise either past the store ceiling. A soft target
    /// is also clamped to never exceed the (possibly tightened) ceiling.
    public static func resolve(
        target: NoteTarget,
        platform: Platform,
        limits: ReviewNoteLimits,
        softTarget: Int?,
        userLimit: Int?
    ) -> ResolvedLimit {
        let storeCeiling = limits.ceiling(for: target, platform: platform)

        // Apply --limit: it can only tighten. With an uncapped target (ceiling 0),
        // --limit introduces a cap; with a capped target it can only lower it.
        var ceiling = storeCeiling
        if let userLimit, userLimit > 0 {
            ceiling = storeCeiling == 0 ? userLimit : min(storeCeiling, userLimit)
        }

        // Clamp the soft aim to the effective ceiling.
        var soft = softTarget
        if let s = soft, ceiling > 0, s > ceiling { soft = ceiling }

        return ResolvedLimit(ceiling: ceiling, softTarget: soft)
    }
}
