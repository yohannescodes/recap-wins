import Foundation

/// Parses a commit subject line into conventional-commit metadata.
///
/// Grammar (Conventional Commits 1.0.0): `type(scope)!: description`.
/// Anything that doesn't match the `type:` shape classifies as `.other`, so the
/// parser never throws — unconventional history degrades gracefully into chores.
public enum CommitParser {
    /// Result of parsing a subject line.
    public struct Parsed: Equatable {
        public var type: CommitType
        public var scope: String?
        public var breaking: Bool
    }

    // `type(optional-scope)optional-bang: rest`
    // Type is letters only; scope is any non-paren run.
    // Computed (not stored) because `Regex` isn't Sendable; construction is cheap.
    private static var conventional: Regex<(Substring, type: Substring, scope: Substring?, bang: Substring?)> {
        /^(?<type>[a-zA-Z]+)(?:\((?<scope>[^)]+)\))?(?<bang>!)?:\s/
    }

    /// Detects a leading ticket reference like `ABC-123` or `#123` anywhere in
    /// the branch name or commit body. Returns the first match, or nil.
    private static var ticket: Regex<(Substring, Substring?, Substring?)> {
        /([A-Z][A-Z0-9]+-\d+)|(#\d+)/
    }

    public static func parse(subject: String, body: String = "") -> Parsed {
        guard let match = subject.firstMatch(of: conventional) else {
            return Parsed(type: .other, scope: nil, breaking: false)
        }
        let rawType = String(match.output.type).lowercased()
        let type = CommitType(rawValue: rawType) ?? .other
        let scope = match.output.scope.map(String.init)
        // Breaking if a `!` precedes the colon, or "BREAKING CHANGE" in the body.
        let breaking = match.output.bang != nil
            || body.contains("BREAKING CHANGE")
            || body.contains("BREAKING-CHANGE")
        // An unrecognized type token still parsed as conventional shape; we keep
        // it as `.other` but it's a genuine commit, not a fallback chore. The
        // bucket math treats `.other` as chore either way (PRD §7).
        return Parsed(type: type, scope: scope, breaking: breaking)
    }

    /// Extract a ticket reference from any of the provided strings, in order.
    public static func detectTicket(in candidates: [String]) -> String? {
        for candidate in candidates {
            if let match = candidate.firstMatch(of: ticket) {
                return String(match.output.0)
            }
        }
        return nil
    }
}
