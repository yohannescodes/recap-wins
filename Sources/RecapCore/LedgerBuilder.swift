import Foundation

/// Builds a `LedgerSnapshot` for one port of a product (FRD §5). Deterministic
/// and offline — same code path as `ChangeReportBuilder`, but the question is
/// different: not "what changed between two refs," but "what features does
/// this repo claim to have, since the baseline."
///
/// The output is the input to slice 2's parity matcher. This builder makes
/// no model calls and does no matching; it just produces a clean list of
/// feature claims with provenance.
public struct LedgerBuilder {
    public let git: Git

    public init(git: Git) {
        self.git = git
    }

    /// Build the ledger for one port.
    ///
    /// - Parameters:
    ///   - portName: stable name for the port (e.g. "ios"). Just a label.
    ///   - ref: the ref to read the ledger at (e.g. "main", "v1.2.0").
    ///   - since: optional baseline ref — only features added after this point
    ///     are considered. Recommended to set this to the "port start" tag
    ///     so old shared parity (predating the second port) doesn't show up
    ///     on every run (FRD §11 "Baseline choice").
    public func build(portName: String, ref: String, since: String?) throws -> LedgerSnapshot {
        try git.ensureRepository()

        let headSHA = try git.resolve(ref)
        let sinceSHA = try since.map { try git.resolve($0) }

        let commits = try loadFeatureCommits(headSHA: headSHA, sinceSHA: sinceSHA)
        let features = commits.compactMap { commitToFeature($0) }

        return LedgerSnapshot(
            portName: portName,
            repositoryPath: git.repositoryPath,
            ref: ref,
            headSHA: headSHA,
            since: since,
            sinceSHA: sinceSHA,
            features: features
        )
    }

    // MARK: - Commit loading

    /// Field separator unlikely to appear in commit metadata. Mirrors
    /// `ChangeReportBuilder` so the parsing shape is familiar.
    private static let fieldSep = "\u{1f}"   // ASCII Unit Separator
    private static let recordSep = "\u{1e}"  // ASCII Record Separator

    /// Read commits between `sinceSHA..headSHA` (or whole history when no
    /// since), already parsed into the `RecapCore.Commit` shape we use
    /// elsewhere. Merge commits are excluded — they're not work introduced.
    func loadFeatureCommits(headSHA: String, sinceSHA: String?) throws -> [Commit] {
        let format = ["%H", "%h", "%an", "%ae", "%aI", "%P", "%s", "%b"]
            .joined(separator: Self.fieldSep) + Self.recordSep

        var args = ["log", "--no-color", "--reverse", "--pretty=format:\(format)"]
        if let sinceSHA {
            args.append("\(sinceSHA)..\(headSHA)")
        } else {
            args.append(headSHA)
        }

        let raw = try git.run(args)

        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        var commits: [Commit] = []
        for record in raw.components(separatedBy: Self.recordSep) {
            let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let fields = record.components(separatedBy: Self.fieldSep)
            guard fields.count >= 8 else {
                throw GitError.unexpectedOutput("ledger commit had \(fields.count) fields, expected 8")
            }
            let sha = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let shortSHA = fields[1]
            let authorName = fields[2]
            let authorEmail = fields[3]
            let dateString = fields[4]
            let parents = fields[5].split(separator: " ")
            let subject = fields[6]
            let body = fields[7]
            // Skip merges; they're not introductions of work (FRD §5 implicit:
            // "feature ledger" — merges fan in existing work, they don't
            // create new claims).
            if parents.count > 1 { continue }
            let date = isoFull.date(from: dateString)
                ?? isoPlain.date(from: dateString)
                ?? Date(timeIntervalSince1970: 0)
            let parsed = CommitParser.parse(subject: subject, body: body)
            let ticket = CommitParser.detectTicket(in: [subject, body])
            commits.append(Commit(
                sha: sha,
                shortSHA: shortSHA,
                authorName: authorName,
                authorEmail: authorEmail,
                date: date,
                subject: subject,
                type: parsed.type,
                scope: parsed.scope,
                breaking: parsed.breaking,
                isMerge: false,
                ticket: ticket
            ))
        }
        return commits
    }

    // MARK: - Distillation

    /// Turn one commit into a `LedgerFeature` — or nil if it isn't a feature.
    ///
    /// Declared `feat:` commits map directly. Non-conventional commits get an
    /// inferred bucket from `CommitClassifier`; only those that infer to
    /// `.feature` produce a ledger entry, and they're flagged `.inferred` so
    /// the matcher can weight them lower (FRD §11 "Cold start" and the
    /// inference-honesty rule from PRD §7).
    ///
    /// Everything else (fix:, chore:, docs:, refactor:, etc.) is dropped —
    /// they're real work, but not features for parity-matching purposes.
    func commitToFeature(_ commit: Commit) -> LedgerFeature? {
        if commit.type == .feat {
            return LedgerFeature(
                id: commit.shortSHA,
                title: cleanedTitle(commit.subject),
                scope: commit.scope,
                origin: .declared,
                sha: commit.sha,
                date: commit.date
            )
        }
        if commit.type == .other {
            // Non-conventional: classify, keep only if it looks like a feature.
            // Without diff data here (ledgers don't load files — that'd defeat
            // the point) we pass `addedSourceFiles: false`, so this is the
            // subject-verb signal alone. Slice 2's matcher knows these are
            // `.inferred` and can weight accordingly.
            let inferred = CommitClassifier.infer(
                subject: commit.subject, addedSourceFiles: false)
            guard inferred == .feature else { return nil }
            return LedgerFeature(
                id: commit.shortSHA,
                title: cleanedTitle(commit.subject),
                scope: nil,
                origin: .inferred,
                sha: commit.sha,
                date: commit.date
            )
        }
        return nil
    }

    /// Strip a conventional-commit prefix from the subject so the matcher sees
    /// the bare title (e.g. `feat(auth)!: add SSO` → `add SSO`). If the subject
    /// isn't conventional, it comes through unchanged. The parser already
    /// classified the commit; this is purely cosmetic for the matcher.
    ///
    /// Computed (not stored) because `Regex` isn't Sendable; same pattern
    /// `CommitParser` uses. Construction is cheap.
    private static var prefixPattern: Regex<Substring> {
        /^[a-zA-Z]+(?:\([^)]+\))?!?:\s+/
    }
    func cleanedTitle(_ subject: String) -> String {
        if let match = subject.firstMatch(of: Self.prefixPattern) {
            return String(subject[match.range.upperBound...])
        }
        return subject
    }
}
