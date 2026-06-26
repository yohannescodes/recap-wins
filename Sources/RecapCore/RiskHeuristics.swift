import Foundation

/// Computes advisory risk flags from a change set (PRD §7).
///
/// These are nudges, never gates. The thresholds are intentionally simple and
/// transparent — a developer should be able to predict why a flag fired.
public enum RiskHeuristics {
    /// Tunable thresholds. Kept here so the values are easy to find and adjust.
    public struct Thresholds: Sendable {
        /// Total churn (insertions + deletions) above which a diff is "large".
        public var largeDiffChurn: Int
        /// Path fragments that mark a file as core/shared infrastructure.
        public var coreFragments: [String]

        public init(
            largeDiffChurn: Int = 1000,
            coreFragments: [String] = ["core/", "shared/", "common/", "lib/", "Package.swift"]
        ) {
            self.largeDiffChurn = largeDiffChurn
            self.coreFragments = coreFragments
        }
    }

    /// Heuristic test-ness of a path. Mirrors common conventions across the
    /// language-agnostic repos recap-wins targets.
    static func isTestFile(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("/tests/")
            || lower.contains("/test/")
            || lower.contains("__tests__")
            || lower.hasSuffix("test.swift")
            || lower.hasSuffix("tests.swift")
            || lower.hasSuffix(".test.ts")
            || lower.hasSuffix(".test.js")
            || lower.hasSuffix(".spec.ts")
            || lower.hasSuffix("_test.go")
            || lower.hasSuffix("_test.py")
            || lower.hasSuffix("test_")
    }

    /// A source file is a non-test file that looks like code (has an extension
    /// and isn't an obvious doc/config asset). Deliberately permissive: the flag
    /// is advisory, so a false "source" is cheap.
    static func isSourceFile(_ path: String) -> Bool {
        if isTestFile(path) { return false }
        let lower = path.lowercased()
        let docOrConfig = [".md", ".txt", ".json", ".yml", ".yaml", ".toml",
                           ".lock", ".gitignore", ".cfg", ".ini"]
        if docOrConfig.contains(where: { lower.hasSuffix($0) }) { return false }
        // Must have a file extension to count as source.
        return path.contains(".")
    }

    public static func evaluate(
        files: [FileChange],
        thresholds: Thresholds = Thresholds()
    ) -> [RiskFlag] {
        var flags: [RiskFlag] = []

        // 1. Large diff.
        let totalChurn = files.reduce(0) { $0 + $1.churn }
        if totalChurn > thresholds.largeDiffChurn {
            flags.append(RiskFlag(
                kind: .largeDiff,
                message: "Large change set: \(totalChurn) lines changed across \(files.count) files."
            ))
        }

        // 2. Core / shared files touched.
        let coreHits = files.filter { file in
            thresholds.coreFragments.contains { file.path.contains($0) }
        }
        if !coreHits.isEmpty {
            let names = coreHits.prefix(3).map(\.path).joined(separator: ", ")
            let suffix = coreHits.count > 3 ? ", …" : ""
            flags.append(RiskFlag(
                kind: .coreFilesTouched,
                message: "Core/shared files touched: \(names)\(suffix)."
            ))
        }

        // 3. Source changed but no tests alongside.
        let touchedSource = files.contains { isSourceFile($0.path) }
        let touchedTests = files.contains { isTestFile($0.path) }
        if touchedSource && !touchedTests {
            flags.append(RiskFlag(
                kind: .noTestsAlongsideSource,
                message: "Source files changed with no test files added or modified alongside."
            ))
        }

        return flags
    }
}
