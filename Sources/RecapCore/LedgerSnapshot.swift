import Foundation

/// A deterministic, offline snapshot of what one port of a product claims to
/// have shipped — the input to `rw align`'s parity match (FRD §5).
///
/// Unlike `ChangeReport`, a ledger isn't about a *change set*; it's about a
/// **state at a ref**. The two ports of a product (e.g. Ledgerly iOS in Swift
/// and Ledgerly Android in Kotlin) have no shared git history, so we can't
/// diff them. Instead we build one of these from each repo, then hand both
/// to the semantic matcher (slice 2) to classify features as paired,
/// equivalent, or a gap.
///
/// This shape is intentionally narrow: a list of *feature claims* with just
/// enough provenance to audit, not a re-rendering of every file touched.
public struct LedgerSnapshot: Codable, Sendable, Equatable {
    /// Schema version so downstream consumers (skill, future API) can adapt.
    public var schemaVersion: Int
    /// Stable port name (e.g. "ios", "android"). Comes from config or the CLI.
    public var portName: String
    /// Absolute path to the repository this ledger was read from.
    public var repositoryPath: String
    /// The ref the ledger was built at (e.g. "main", "v1.2.0", a SHA).
    public var ref: String
    /// Resolved commit SHA of `ref` at build time — pins the snapshot.
    public var headSHA: String
    /// The baseline this ledger considers — typically a "port-start" tag.
    /// `nil` means "whole history" (FRD §11 calls this out as a known foot-gun
    /// for repos that share old parity from before the second port existed).
    public var since: String?
    /// Resolved SHA of `since`, when given. Lets future re-runs detect drift
    /// without re-resolving the ref.
    public var sinceSHA: String?
    /// The classified feature claims this port makes. Authoritative for the
    /// matcher: it reads these, not the underlying git history.
    public var features: [LedgerFeature]

    public init(
        schemaVersion: Int = 1,
        portName: String,
        repositoryPath: String,
        ref: String,
        headSHA: String,
        since: String?,
        sinceSHA: String?,
        features: [LedgerFeature]
    ) {
        self.schemaVersion = schemaVersion
        self.portName = portName
        self.repositoryPath = repositoryPath
        self.ref = ref
        self.headSHA = headSHA
        self.since = since
        self.sinceSHA = sinceSHA
        self.features = features
    }
}

/// One feature claim within a `LedgerSnapshot`. Distilled from a commit (or
/// future: a tag's accumulated commits) so the matcher has structure to reason
/// over, not raw subject lines.
///
/// Origin matters: a feature surfaced from a `feat:` commit is **declared**;
/// one inferred from verbs/diff on a non-conventional commit is **inferred**.
/// The matcher should treat the two with different confidence, same way the
/// vitals view flags inferred counts (PRD §7).
public struct LedgerFeature: Codable, Sendable, Equatable {
    /// How this feature came to be in the ledger.
    public enum Origin: String, Codable, Sendable {
        /// Conventional `feat:` commit. The strongest signal.
        case declared
        /// Heuristic guess from a non-conventional commit. Slice 2 should
        /// weight these lower; the matcher must respect the distinction.
        case inferred
    }

    /// Stable identifier inside this ledger (the short SHA today; lets the
    /// matcher reference a specific feature unambiguously across runs).
    public var id: String
    /// Cleaned title for the matcher to reason over — the commit subject with
    /// any conventional-commit prefix stripped (e.g. `feat(auth): ...` → `...`).
    public var title: String
    /// Conventional-commit scope if one was declared (e.g. "auth"). Useful as
    /// a soft grouping hint for the matcher.
    public var scope: String?
    /// Where this feature came from in the commit graph.
    public var origin: Origin
    /// Full commit SHA so an auditor can `git show <sha>` to verify.
    public var sha: String
    /// Author date of the commit. Lets the matcher sort or de-duplicate by
    /// recency when two commits arguably describe the same feature.
    public var date: Date

    public init(
        id: String,
        title: String,
        scope: String?,
        origin: Origin,
        sha: String,
        date: Date
    ) {
        self.id = id
        self.title = title
        self.scope = scope
        self.origin = origin
        self.sha = sha
        self.date = date
    }
}

public extension LedgerSnapshot {
    /// Pretty-printed JSON for stdout (matches `ChangeReport.jsonString` shape).
    func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}
