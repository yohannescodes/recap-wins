import Foundation

/// The structured, offline, verifiable picture of a change set.
///
/// This is the `change_report.json` contract from PRD §5. Everything countable
/// lives here; the semantic layer (Phase 1+) consumes this to write prose, but
/// the report itself never needs a model or a network.
public struct ChangeReport: Codable, Sendable, Equatable {
    /// Schema version so downstream consumers (skill, future API) can adapt.
    public var schemaVersion: Int
    /// The resolved refs this report describes.
    public var range: ChangeRange
    /// All commits in `base..head`, oldest first, classified.
    public var commits: [Commit]
    /// Per-file change statistics across the whole change set.
    public var files: [FileChange]
    /// Distinct branches that contributed commits to this change set.
    public var branches: [BranchInfo]
    /// Aggregate one-screen health read (PRD §7).
    public var vitals: Vitals
    /// Advisory, heuristic risk flags. Never gates.
    public var riskFlags: [RiskFlag]

    public init(
        schemaVersion: Int = 1,
        range: ChangeRange,
        commits: [Commit],
        files: [FileChange],
        branches: [BranchInfo],
        vitals: Vitals,
        riskFlags: [RiskFlag]
    ) {
        self.schemaVersion = schemaVersion
        self.range = range
        self.commits = commits
        self.files = files
        self.branches = branches
        self.vitals = vitals
        self.riskFlags = riskFlags
    }
}

/// The resolved head/base of a change set.
public struct ChangeRange: Codable, Sendable, Equatable {
    /// Base ref as the user named it (e.g. "main").
    public var base: String
    /// Head ref as the user named it (e.g. "HEAD" or a branch name).
    public var head: String
    /// Resolved base commit SHA.
    public var baseSHA: String
    /// Resolved head commit SHA.
    public var headSHA: String
    /// The merge-base SHA (the fork point the diff is computed from).
    public var mergeBaseSHA: String

    public init(base: String, head: String, baseSHA: String, headSHA: String, mergeBaseSHA: String) {
        self.base = base
        self.head = head
        self.baseSHA = baseSHA
        self.headSHA = headSHA
        self.mergeBaseSHA = mergeBaseSHA
    }
}

/// Conventional-commit type. `.other` covers anything unparseable.
public enum CommitType: String, Codable, Sendable, CaseIterable {
    case feat
    case fix
    case chore
    case docs
    case refactor
    case test
    case perf
    case build
    case ci
    case style
    case revert
    case other

    /// The three top-level buckets the vitals headline counts by (PRD §7):
    /// features / fixes / chores. Everything that isn't feat or fix folds into
    /// the "chore" bucket for the headline, while the precise type is retained.
    public enum Bucket: String, Codable, Sendable {
        case feature
        case fix
        case chore
    }

    public var bucket: Bucket {
        switch self {
        case .feat: return .feature
        case .fix: return .fix
        default: return .chore
        }
    }
}

/// A single commit in the change set, with parsed conventional-commit metadata.
public struct Commit: Codable, Sendable, Equatable {
    public var sha: String
    public var shortSHA: String
    public var authorName: String
    public var authorEmail: String
    public var date: Date
    /// Full first line of the commit message (the summary).
    public var subject: String
    /// Parsed conventional-commit type, or `.other`.
    public var type: CommitType
    /// Optional conventional-commit scope, e.g. `feat(parser):` → "parser".
    public var scope: String?
    /// True if the commit signals a breaking change (`!` or BREAKING CHANGE).
    public var breaking: Bool
    /// True if this is a merge commit (more than one parent).
    public var isMerge: Bool
    /// Detected ticket reference (Linear/JIRA/GitHub) if present. Never required.
    public var ticket: String?
    /// For commits with no conventional prefix (`type == .other`), a heuristic
    /// guess at the bucket from the subject + diff. `nil` when `type` is already
    /// conventional, or when no confident guess was possible. The parsed `type`
    /// is never overwritten — this keeps declared-vs-inferred honest (PRD §7).
    public var inferredBucket: CommitType.Bucket?

    public init(
        sha: String,
        shortSHA: String,
        authorName: String,
        authorEmail: String,
        date: Date,
        subject: String,
        type: CommitType,
        scope: String?,
        breaking: Bool,
        isMerge: Bool,
        ticket: String?,
        inferredBucket: CommitType.Bucket? = nil
    ) {
        self.sha = sha
        self.shortSHA = shortSHA
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.date = date
        self.subject = subject
        self.type = type
        self.scope = scope
        self.breaking = breaking
        self.isMerge = isMerge
        self.ticket = ticket
        self.inferredBucket = inferredBucket
    }

    /// The bucket used for counting: the conventional bucket when the commit has
    /// a recognized prefix, otherwise the inferred guess, falling back to chore.
    public var effectiveBucket: CommitType.Bucket {
        if type != .other { return type.bucket }
        return inferredBucket ?? .chore
    }

    /// True if this commit's bucket came from inference, not a declared prefix.
    public var isInferred: Bool {
        type == .other && inferredBucket != nil
    }
}

/// Per-file change stats across the change set.
public struct FileChange: Codable, Sendable, Equatable {
    public var path: String
    public var insertions: Int
    public var deletions: Int
    /// "A" added, "M" modified, "D" deleted, "R" renamed, etc. (git status letter).
    public var status: String

    /// Total churn = insertions + deletions. Used for hotspot ranking.
    public var churn: Int { insertions + deletions }

    public init(path: String, insertions: Int, deletions: Int, status: String) {
        self.path = path
        self.insertions = insertions
        self.deletions = deletions
        self.status = status
    }
}

/// A branch that contributed commits to the change set (PRD §6 `branch`).
public struct BranchInfo: Codable, Sendable, Equatable {
    public var name: String
    /// Number of commits in the change set reachable from this branch's tip.
    public var commitCount: Int
    /// True if this is the head branch the change set is defined from.
    public var isHead: Bool

    public init(name: String, commitCount: Int, isHead: Bool) {
        self.name = name
        self.commitCount = commitCount
        self.isHead = isHead
    }
}

/// One contributor's authored share of the change set (PRD §6 `blame`).
public struct Contributor: Codable, Sendable, Equatable {
    public var name: String
    public var email: String
    public var commitCount: Int

    public init(name: String, email: String, commitCount: Int) {
        self.name = name
        self.email = email
        self.commitCount = commitCount
    }
}

/// The one-screen vitals read (PRD §7).
public struct Vitals: Codable, Sendable, Equatable {
    public var features: Int
    public var fixes: Int
    public var chores: Int
    public var filesChanged: Int
    public var insertions: Int
    public var deletions: Int
    public var contributors: [Contributor]
    public var branchCount: Int
    /// The few files with the largest churn, already sorted descending.
    public var hotspots: [FileChange]
    /// How many of the counted commits were bucketed by inference rather than a
    /// declared conventional-commit prefix. `0` means every count is from a
    /// declared type. Lets the UI flag when a number isn't purely declared.
    public var inferredCount: Int

    public init(
        features: Int,
        fixes: Int,
        chores: Int,
        filesChanged: Int,
        insertions: Int,
        deletions: Int,
        contributors: [Contributor],
        branchCount: Int,
        hotspots: [FileChange],
        inferredCount: Int = 0
    ) {
        self.features = features
        self.fixes = fixes
        self.chores = chores
        self.filesChanged = filesChanged
        self.insertions = insertions
        self.deletions = deletions
        self.contributors = contributors
        self.branchCount = branchCount
        self.hotspots = hotspots
        self.inferredCount = inferredCount
    }
}

/// An advisory risk flag (PRD §7). A nudge, never a gate.
public struct RiskFlag: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// Unusually large diff for one change set.
        case largeDiff
        /// Core / shared files touched.
        case coreFilesTouched
        /// Source changed but no test files added/changed alongside.
        case noTestsAlongsideSource
    }

    public var kind: Kind
    /// Human-readable one-line explanation.
    public var message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}
