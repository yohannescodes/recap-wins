import Foundation
import RecapCore

/// The parity report `rw align` produces (FRD §7). Two ledgers, a list of
/// matched/unmatched/equivalent features, a summary, and any drafted issues
/// for confirmed gaps.
///
/// `align` is fundamentally different from every other `rw` output: two repos,
/// two languages, no shared history. The deterministic core can build each
/// ledger independently (slice 1); the *match* between them is semantic
/// (slice 2). This struct is the stable contract both halves write to.
///
/// **Slice 1 status:** only `portA`, `portB`, `product`, `since`, `disclaimer`,
/// and `generatedBy` are populated. `features`, `summary`, and
/// `suggestedIssues` arrive in slice 2. The shape is stable so JSON consumers
/// written today don't need to change when the matcher lands.
public struct AlignReport: Codable, Sendable, Equatable {
    /// Schema version for downstream consumers (skill, future API).
    public var schemaVersion: Int
    /// Product id this report covers (e.g. "ledgerly"). Nil when invoked with
    /// `--a/--b` and no product profile.
    public var product: String?
    /// The two ports being compared. Order is meaningful — issue drafts on
    /// "side a" refer to `portA`'s repo.
    public var portA: LedgerSnapshot
    public var portB: LedgerSnapshot
    /// The baseline ref both ports were read against (echoes
    /// `portA.since`/`portB.since` for convenience). FRD §11 stresses the
    /// importance of being explicit about this.
    public var since: String?
    /// Per-feature parity classification. Empty in slice 1 (no matcher yet).
    public var features: [FeatureMatch]
    /// Aggregate counts by status. Empty/zeroed in slice 1.
    public var summary: AlignSummary
    /// Tracker-agnostic issue drafts for confirmed gaps. Empty in slice 1.
    public var suggestedIssues: [IssueDraft]
    /// Provider that produced the match (e.g. "anthropic", "skill"). Empty
    /// string in slice 1 since no match happened.
    public var generatedBy: String
    /// Non-optional disclaimer the FRD insists on (§3 "Not an oracle", §11
    /// "False confidence"). Output must never assert authoritative parity;
    /// this line is part of the report so a consumer can't drop it.
    public var disclaimer: String

    public init(
        schemaVersion: Int = 1,
        product: String? = nil,
        portA: LedgerSnapshot,
        portB: LedgerSnapshot,
        since: String? = nil,
        features: [FeatureMatch] = [],
        summary: AlignSummary = AlignSummary(),
        suggestedIssues: [IssueDraft] = [],
        generatedBy: String = "",
        disclaimer: String = AlignReport.standardDisclaimer
    ) {
        self.schemaVersion = schemaVersion
        self.product = product
        self.portA = portA
        self.portB = portB
        self.since = since
        self.features = features
        self.summary = summary
        self.suggestedIssues = suggestedIssues
        self.generatedBy = generatedBy
        self.disclaimer = disclaimer
    }

    /// The PRD/FRD-mandated framing for every align run.
    public static let standardDisclaimer =
        "Candidates to confirm — not authoritative parity. "
        + "Always review each match before filing the drafted issues."

    /// Pretty-printed JSON for stdout.
    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

/// How a feature pair is classified after the match (FRD §6).
public enum MatchStatus: String, Codable, Sendable, CaseIterable {
    /// Same capability on both sides. Real parity.
    case paired
    /// Different but equivalent platform-native substitutes
    /// (Apple Pay ↔ Google Pay). Parity *achieved*, not a gap.
    case equivalent
    /// Present on side A only — real missing work on side B.
    case gapOnA = "gap_on_a"
    /// Present on side B only — real missing work on side A.
    case gapOnB = "gap_on_b"
    /// Matcher isn't sure — surfaced for human confirmation, never auto-filed
    /// as a gap (FRD §3, §6, §11).
    case ambiguous
}

/// One feature pair (or unmatched single) and its classification.
public struct FeatureMatch: Codable, Sendable, Equatable {
    /// Stable identifier within this report.
    public var id: String
    /// Classification result.
    public var status: MatchStatus
    /// Description of the feature on side A, when present.
    public var descriptionA: String?
    /// Description of the feature on side B, when present.
    public var descriptionB: String?
    /// Why these were treated as equivalent, when status == .equivalent.
    /// Shown to the user so equivalence decisions are auditable.
    public var equivalenceNote: String?
    /// 0–1. Always surfaced, never hidden — the FRD's central anti-overclaim
    /// rule (§11 "False confidence is the cardinal risk").
    public var confidence: Double

    public init(
        id: String,
        status: MatchStatus,
        descriptionA: String? = nil,
        descriptionB: String? = nil,
        equivalenceNote: String? = nil,
        confidence: Double
    ) {
        self.id = id
        self.status = status
        self.descriptionA = descriptionA
        self.descriptionB = descriptionB
        self.equivalenceNote = equivalenceNote
        self.confidence = confidence
    }
}

/// Counts per status (FRD §7). Lets the human read see "5 paired, 2 gaps on
/// android, 1 ambiguous" without iterating the features list.
public struct AlignSummary: Codable, Sendable, Equatable {
    public var paired: Int
    public var equivalent: Int
    public var gapOnA: Int
    public var gapOnB: Int
    public var ambiguous: Int

    public init(
        paired: Int = 0,
        equivalent: Int = 0,
        gapOnA: Int = 0,
        gapOnB: Int = 0,
        ambiguous: Int = 0
    ) {
        self.paired = paired
        self.equivalent = equivalent
        self.gapOnA = gapOnA
        self.gapOnB = gapOnB
        self.ambiguous = ambiguous
    }

    enum CodingKeys: String, CodingKey {
        case paired
        case equivalent
        case gapOnA = "gap_on_a"
        case gapOnB = "gap_on_b"
        case ambiguous
    }

    /// Build a summary from a list of feature matches.
    public static func from(_ features: [FeatureMatch]) -> AlignSummary {
        var s = AlignSummary()
        for f in features {
            switch f.status {
            case .paired: s.paired += 1
            case .equivalent: s.equivalent += 1
            case .gapOnA: s.gapOnA += 1
            case .gapOnB: s.gapOnB += 1
            case .ambiguous: s.ambiguous += 1
            }
        }
        return s
    }
}

/// A tracker-agnostic issue draft for one confirmed gap (FRD §6, §7, §9).
/// `--issues markdown|linear|github|jira` is purely a *formatter* choice at
/// render time; this struct stays format-neutral.
public struct IssueDraft: Codable, Sendable, Equatable {
    /// Which port the work needs to land on (e.g. "android"). Matches a
    /// configured `PortRef.name`.
    public var side: String
    /// Suggested issue title.
    public var title: String
    /// Suggested issue body (Markdown). Tracker formatters tweak this at
    /// render time (labels, checklists) but the source stays one string.
    public var body: String
    /// The feature on the "ahead" side that motivated this draft. Lets a
    /// reviewer trace each issue back to the parity signal that produced it.
    public var sourceFeature: String

    public init(side: String, title: String, body: String, sourceFeature: String) {
        self.side = side
        self.title = title
        self.body = body
        self.sourceFeature = sourceFeature
    }
}
