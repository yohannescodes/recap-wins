import Foundation
import RecapCore

/// Runs the semantic commands: takes a deterministic `ChangeReport`, prompts the
/// model, and returns prose. Generic over `ModelClient` so production uses the
/// live Anthropic client and tests inject a mock — no network in the test path.
public struct SemanticEngine: Sendable {
    public let client: any ModelClient

    public init(client: any ModelClient) {
        self.client = client
    }

    /// `rw new` — list the new user-facing features in the change set.
    public func newFeatures(_ report: ChangeReport) async throws -> String {
        let request = PromptBuilder.newFeatures(report)
        return try await client.complete(request).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `rw notes --pr` — write a PR description for the change set.
    public func pullRequestNote(_ report: ChangeReport) async throws -> String {
        let request = PromptBuilder.pullRequestNote(report)
        return try await client.complete(request).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The result of rendering a notes target: the prose plus any cap warning.
    public struct NoteResult: Sendable, Equatable {
        public var text: String
        /// Non-nil when output overflows the hard ceiling. The PRD says warn,
        /// never silently truncate — the caller surfaces this; text is untouched.
        public var overflowWarning: String?

        public init(text: String, overflowWarning: String?) {
            self.text = text
            self.overflowWarning = overflowWarning
        }
    }

    /// `rw notes <target>` — render the change set for a target within its cap.
    ///
    /// - Parameters:
    ///   - limit: the resolved hard ceiling + soft target for this render.
    public func note(
        _ report: ChangeReport,
        target: NoteTarget,
        product: ProductProfile?,
        limit: ResolvedLimit
    ) async throws -> NoteResult {
        let request = PromptBuilder.note(report, target: target, product: product, limit: limit)
        let text = try await client.complete(request).trimmingCharacters(in: .whitespacesAndNewlines)

        var warning: String?
        if limit.overflows(text.count) {
            warning = "Output is \(text.count) characters, over the "
                + "\(limit.ceiling)-character limit for \(target.displayName). "
                + "Tighten before publishing — not truncated automatically."
        }
        return NoteResult(text: text, overflowWarning: warning)
    }

    /// `rw market` — render a content pack for the new features in a product's
    /// voice (PRD §6). Each requested piece is generated independently so a long
    /// social post and a 30-char subtitle don't constrain each other.
    public func marketPack(
        _ report: ChangeReport,
        pieces: [MarketPiece],
        product: ProductProfile,
        limits: MarketLimits
    ) async throws -> [MarketPieceResult] {
        var results: [MarketPieceResult] = []
        for piece in pieces {
            let ceiling = piece.ceiling(limits)
            let request = PromptBuilder.marketPiece(
                report, piece: piece, product: product, ceiling: ceiling)
            let text = try await client.complete(request)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var warning: String?
            if ceiling > 0 && text.count > ceiling {
                warning = "\(text.count) chars, over the \(ceiling)-char limit for "
                    + "\(piece.title). Tighten before publishing — not truncated."
            }
            results.append(MarketPieceResult(piece: piece, text: text, overflowWarning: warning))
        }
        return results
    }
}
