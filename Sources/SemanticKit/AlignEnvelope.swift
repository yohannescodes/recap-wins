import Foundation
import RecapCore

/// The JSON a host agent receives in skill mode for `rw align` (FRD §5).
/// `rw` does all the deterministic work — builds both ledgers, loads the
/// equivalence table — and hands the agent the prompt + grounded data; the
/// agent is the model, returns the matched `FeatureMatch[]` + `IssueDraft[]`.
///
/// Distinct from `SkillEnvelope` (which carries a single `ChangeReport`)
/// because align's input is fundamentally different: two ledgers, no
/// shared history, plus the equivalence table. A separate type keeps both
/// shapes honest and makes host-agent consumers simpler.
public struct AlignEnvelope: Codable, Sendable, Equatable {
    /// Schema version for host-agent consumers.
    public var schemaVersion: Int
    /// Always "align" — lets the agent disambiguate when multiple envelope
    /// types share a host inbox.
    public var command: String
    /// One-line, human-readable instruction for the host agent.
    public var instruction: String
    /// The system prompt the API provider would have used.
    public var system: String
    /// The user-message text (the grounded two-ledger context).
    public var user: String
    /// The product id if one was supplied (nil for ad-hoc --a/--b runs).
    public var product: String?
    /// Baseline ref both sides were read against.
    public var since: String?
    /// Side A's full deterministic ledger, for grounding/verification.
    public var ledgerA: LedgerSnapshot
    /// Side B's full deterministic ledger.
    public var ledgerB: LedgerSnapshot
    /// The merged equivalence table the matcher should respect.
    public var equivalences: [ParityEntry]

    public init(
        schemaVersion: Int = 1,
        command: String = "align",
        instruction: String,
        system: String,
        user: String,
        product: String?,
        since: String?,
        ledgerA: LedgerSnapshot,
        ledgerB: LedgerSnapshot,
        equivalences: [ParityEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.command = command
        self.instruction = instruction
        self.system = system
        self.user = user
        self.product = product
        self.since = since
        self.ledgerA = ledgerA
        self.ledgerB = ledgerB
        self.equivalences = equivalences
    }

    /// Encode to pretty JSON for emission to stdout.
    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

public extension SkillEnvelope {
    /// Build the envelope for `rw align` in skill mode.
    ///
    /// The host agent should follow the system prompt's JSON schema exactly
    /// (`features[]` + `issues[]`) and return the result back. `rw` itself
    /// has no role beyond emitting this envelope — the agent IS the matcher.
    ///
    /// This method lives on `SkillEnvelope` for discoverability alongside
    /// the other `forX(...)` helpers, but returns an `AlignEnvelope` (a
    /// distinct shape — two ledgers + equivalences, not a ChangeReport).
    static func forAlign(
        ledgerA: LedgerSnapshot,
        ledgerB: LedgerSnapshot,
        equivalences: [ParityEntry],
        product: ProductProfile?,
        productId: String?,
        since: String?
    ) -> AlignEnvelope {
        let req = PromptBuilder.alignMatch(
            ledgerA: ledgerA, ledgerB: ledgerB,
            equivalences: equivalences, productName: product?.name)
        let instruction = "Classify each feature pairing across the two ports "
            + "as paired / equivalent / gap_on_a / gap_on_b / ambiguous and "
            + "draft tracker-agnostic issues for confirmed gaps. Return the "
            + "single JSON object the system prompt specifies — no preamble, "
            + "no markdown fence — so rw can decode it. When in doubt, prefer "
            + "\"ambiguous\"; never assert authoritative parity."
        return AlignEnvelope(
            instruction: instruction,
            system: req.system,
            user: req.messages.first?.text ?? "",
            product: productId,
            since: since,
            ledgerA: ledgerA, ledgerB: ledgerB,
            equivalences: equivalences)
    }
}
