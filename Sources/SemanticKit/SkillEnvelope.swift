import Foundation
import RecapCore

/// The JSON a host agent receives in skill mode (PRD §5/§10). `rw` does the
/// deterministic work and hands the agent everything it needs to write the
/// prose itself — no API key, no network call from `rw`.
///
/// The host agent reads `instruction` (what to produce) and `prompt` (the
/// system + user text the API provider would have sent), grounded by `report`.
public struct SkillEnvelope: Codable, Sendable, Equatable {
    /// Schema version for host-agent consumers.
    public var schemaVersion: Int
    /// The semantic command being requested: "new" or "notes".
    public var command: String
    /// For `notes`, the target (e.g. "asc_update"); nil for `new`.
    public var target: String?
    /// A one-line, human-readable instruction for the host agent.
    public var instruction: String
    /// The system prompt the API provider would have used.
    public var system: String
    /// The user-message text (the grounded change-set context).
    public var user: String
    /// Soft length aim in characters, if any (host should aim for it).
    public var softTargetChars: Int?
    /// Hard char ceiling; 0 = uncapped. Host must not exceed when > 0.
    public var ceilingChars: Int
    /// The full deterministic change report, for grounding/verification.
    public var report: ChangeReport

    public init(
        schemaVersion: Int = 1,
        command: String,
        target: String?,
        instruction: String,
        system: String,
        user: String,
        softTargetChars: Int?,
        ceilingChars: Int,
        report: ChangeReport
    ) {
        self.schemaVersion = schemaVersion
        self.command = command
        self.target = target
        self.instruction = instruction
        self.system = system
        self.user = user
        self.softTargetChars = softTargetChars
        self.ceilingChars = ceilingChars
        self.report = report
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
    /// Build the envelope for `rw new` in skill mode.
    static func forNewFeatures(_ report: ChangeReport) -> SkillEnvelope {
        let req = PromptBuilder.newFeatures(report)
        return SkillEnvelope(
            command: "new",
            target: nil,
            instruction: "Write the list of new user-facing features for this change set, "
                + "following the system prompt. Output only the bulleted list.",
            system: req.system,
            user: req.messages.first?.text ?? "",
            softTargetChars: nil,
            ceilingChars: 0,
            report: report
        )
    }

    /// Build the envelope for a `rw notes` target in skill mode.
    static func forNote(
        _ report: ChangeReport,
        target: NoteTarget,
        product: ProductProfile?,
        limit: ResolvedLimit
    ) -> SkillEnvelope {
        let req = PromptBuilder.note(report, target: target, product: product, limit: limit)
        var instruction = "Write the \(target.displayName) for this change set, following the system prompt."
        if limit.ceiling > 0 {
            instruction += " Stay within \(limit.ceiling) characters."
        }
        return SkillEnvelope(
            command: "notes",
            target: target.rawValue,
            instruction: instruction,
            system: req.system,
            user: req.messages.first?.text ?? "",
            softTargetChars: limit.softTarget,
            ceilingChars: limit.ceiling,
            report: report
        )
    }

    /// Build one envelope per piece of a `rw market` pack. The host agent writes
    /// each piece from its own system prompt and cap.
    static func forMarket(
        _ report: ChangeReport,
        pieces: [MarketPiece],
        product: ProductProfile,
        limits: MarketLimits
    ) -> [SkillEnvelope] {
        pieces.map { piece in
            let ceiling = piece.ceiling(limits)
            let req = PromptBuilder.marketPiece(
                report, piece: piece, product: product, ceiling: ceiling)
            var instruction = "Write the \(piece.title) marketing copy, following the system prompt."
            if ceiling > 0 { instruction += " Stay within \(ceiling) characters." }
            return SkillEnvelope(
                command: "market",
                target: piece.rawValue,
                instruction: instruction,
                system: req.system,
                user: req.messages.first?.text ?? "",
                softTargetChars: nil,
                ceilingChars: ceiling,
                report: report
            )
        }
    }
}

/// A pretty JSON array of envelopes (skill-mode `market` output).
public func skillEnvelopesJSON(_ envelopes: [SkillEnvelope]) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try encoder.encode(envelopes), as: UTF8.self)
}
