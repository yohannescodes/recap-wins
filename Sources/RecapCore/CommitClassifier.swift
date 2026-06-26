import Foundation

/// Infers a bucket for commits that lack a conventional-commit prefix.
///
/// Conventional commits (`feat:`, `fix:`…) are the authoritative signal and are
/// never overridden. This only runs on `.other` commits — where the parser found
/// no recognized type — to *guess* whether the work is a feature, fix, or chore
/// from the commit subject and its diff. The guess is recorded separately
/// (`inferredType` + `inferred`), never written over the parsed `type`, so the
/// report stays honest about what was declared vs. inferred (PRD §7: deterministic
/// and transparent — a developer can predict why a guess fired).
public enum CommitClassifier {
    /// Subject-keyword tables. Lowercased whole-word-ish matching on the subject.
    /// Order of precedence: fix > feature > chore (a "fix" verb is the strongest
    /// signal; "add tests" should read as chore, handled by the chore table).
    static let fixVerbs = [
        "fix", "fixes", "fixed", "resolve", "resolves", "resolved",
        "patch", "patches", "correct", "corrects", "repair", "hotfix",
        "bugfix", "address", "addresses",
    ]
    static let featureVerbs = [
        "add", "adds", "added", "introduce", "introduces", "ship", "ships",
        "shipped", "implement", "implements", "create", "creates", "build",
        "support", "enable", "enables", "new", "launch", "launches",
    ]
    static let choreVerbs = [
        "refactor", "rename", "renames", "bump", "bumps", "chore", "cleanup",
        "clean", "tidy", "format", "lint", "docs", "document", "test", "tests",
        "update", "updates", "remove", "removes", "delete", "revert", "gate",
        "move", "moves", "tweak", "style", "comment", "wip",
    ]

    /// Infer a bucket from the subject alone.
    static func bucketFromSubject(_ subject: String) -> CommitType.Bucket? {
        let words = Set(
            subject.lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
        )
        // Fix first (strongest), then feature, then chore.
        if !words.isDisjoint(with: fixVerbs) { return .fix }
        if !words.isDisjoint(with: featureVerbs) {
            // "add tests" / "add docs" lean chore despite the feature verb.
            if !words.isDisjoint(with: ["test", "tests", "docs", "doc", "readme"]) {
                return .chore
            }
            return .feature
        }
        if !words.isDisjoint(with: choreVerbs) { return .chore }
        return nil
    }

    /// Whether a path looks like a non-trivial source file (mirrors the risk
    /// heuristic's notion of source — code, not docs/config/tests).
    static func isSourceFile(_ path: String) -> Bool {
        RiskHeuristics.isSourceFile(path) && !RiskHeuristics.isTestFile(path)
    }

    /// Infer a bucket for one `.other` commit, given the files added in the whole
    /// change set as supporting evidence. Returns nil if no confident guess.
    ///
    /// - Parameters:
    ///   - subject: the commit subject line.
    ///   - addedSourceFiles: true if the change set added new source files — a
    ///     supporting signal that nudges an ambiguous subject toward "feature".
    public static func infer(subject: String, addedSourceFiles: Bool) -> CommitType.Bucket? {
        if let fromSubject = bucketFromSubject(subject) {
            return fromSubject
        }
        // No subject keyword matched. If the change set introduced new source
        // files, lean feature; otherwise leave it unknown (caller treats nil as
        // chore for counting, same as today).
        return addedSourceFiles ? .feature : nil
    }
}
