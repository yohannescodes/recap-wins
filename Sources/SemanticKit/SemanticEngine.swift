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

    /// The matcher response for `rw align`: the per-feature classifications
    /// and any issue drafts for confirmed gaps, both produced by the same
    /// model call so a single round-trip ships both halves of the report.
    public struct AlignResult: Sendable, Equatable {
        public var features: [FeatureMatch]
        public var issues: [IssueDraft]
        public init(features: [FeatureMatch], issues: [IssueDraft]) {
            self.features = features
            self.issues = issues
        }
    }

    /// `rw align` — run the semantic matcher against two ledgers (FRD §5, §6).
    ///
    /// The model receives both ledgers and the merged equivalence table
    /// (built-in Apple↔Google + per-product curated) and returns a JSON
    /// document we parse into typed `FeatureMatch` / `IssueDraft` values.
    /// `equivalences` should already be merged via
    /// `EquivalenceTable.merged(with:)`.
    public func alignFeatures(
        ledgerA: LedgerSnapshot,
        ledgerB: LedgerSnapshot,
        equivalences: [ParityEntry],
        productName: String?
    ) async throws -> AlignResult {
        let request = PromptBuilder.alignMatch(
            ledgerA: ledgerA, ledgerB: ledgerB,
            equivalences: equivalences, productName: productName)
        let raw = try await client.complete(request)
        return try Self.parseAlignResponse(raw)
    }

    /// Parse the matcher's JSON response, tolerating common framing the model
    /// adds even when asked not to: markdown fences, leading prose, trailing
    /// commentary. Extracts the largest balanced `{ ... }` object and decodes.
    static func parseAlignResponse(_ raw: String) throws -> AlignResult {
        guard let object = extractJSONObject(from: raw) else {
            throw ModelError.malformedResponse(
                "matcher returned no parseable JSON object; got: " +
                String(raw.prefix(200)))
        }
        struct Wire: Decodable {
            struct F: Decodable {
                var id: String?
                var status: String
                var descriptionA: String?
                var descriptionB: String?
                var equivalenceNote: String?
                var confidence: Double?
            }
            struct I: Decodable {
                var side: String
                var title: String
                var body: String
                var sourceFeature: String?
            }
            var features: [F]
            var issues: [I]?
        }
        let decoder = JSONDecoder()
        let wire: Wire
        do {
            wire = try decoder.decode(Wire.self, from: Data(object.utf8))
        } catch {
            throw ModelError.malformedResponse(
                "matcher JSON did not match the expected shape: \(error). " +
                "First 200 chars: " + String(object.prefix(200)))
        }
        let features = wire.features.enumerated().map { idx, f -> FeatureMatch in
            let status = MatchStatus(rawValue: f.status) ?? .ambiguous
            // Clamp confidence into [0, 1] and treat nil as 0.5 (the matcher
            // SHOULD always include it, but a missing value shouldn't crash).
            let confidence = max(0.0, min(1.0, f.confidence ?? 0.5))
            return FeatureMatch(
                id: f.id ?? "m\(idx + 1)",
                status: status,
                descriptionA: f.descriptionA,
                descriptionB: f.descriptionB,
                equivalenceNote: f.equivalenceNote,
                confidence: confidence)
        }
        let issues: [IssueDraft] = (wire.issues ?? []).map { i in
            IssueDraft(
                side: i.side, title: i.title, body: i.body,
                sourceFeature: i.sourceFeature ?? "")
        }
        return AlignResult(features: features, issues: issues)
    }

    /// Find the longest balanced top-level `{ ... }` substring in `raw`,
    /// tolerating leading code fences / prose / trailing commentary.
    /// Returns nil when no balanced object exists.
    private static func extractJSONObject(from raw: String) -> String? {
        let scalars = Array(raw)
        guard let start = scalars.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escape = false
        var end: Int?
        for i in start..<scalars.count {
            let ch = scalars[i]
            if escape { escape = false; continue }
            if ch == "\\" { escape = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            if inString { continue }
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { end = i; break }
            }
        }
        guard let end else { return nil }
        return String(scalars[start...end])
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
