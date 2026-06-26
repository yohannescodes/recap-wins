import Testing
@testable import RecapCore

@Suite("Risk heuristics")
struct RiskHeuristicsTests {
    @Test("flags large diffs over threshold")
    func largeDiff() {
        let files = [FileChange(path: "App.swift", insertions: 800, deletions: 300, status: "M")]
        let flags = RiskHeuristics.evaluate(files: files)
        #expect(flags.contains { $0.kind == .largeDiff })
    }

    @Test("does not flag small diffs")
    func smallDiff() {
        let files = [
            FileChange(path: "App.swift", insertions: 10, deletions: 2, status: "M"),
            FileChange(path: "AppTests.swift", insertions: 8, deletions: 0, status: "A"),
        ]
        let flags = RiskHeuristics.evaluate(files: files)
        #expect(!flags.contains { $0.kind == .largeDiff })
    }

    @Test("flags core/shared files")
    func coreFiles() {
        let files = [FileChange(path: "Sources/core/Engine.swift", insertions: 5, deletions: 1, status: "M")]
        let flags = RiskHeuristics.evaluate(files: files)
        #expect(flags.contains { $0.kind == .coreFilesTouched })
    }

    @Test("flags source change with no tests alongside")
    func noTests() {
        let files = [FileChange(path: "Sources/Feature.swift", insertions: 20, deletions: 0, status: "A")]
        let flags = RiskHeuristics.evaluate(files: files)
        #expect(flags.contains { $0.kind == .noTestsAlongsideSource })
    }

    @Test("no missing-tests flag when tests are present")
    func testsPresent() {
        let files = [
            FileChange(path: "Sources/Feature.swift", insertions: 20, deletions: 0, status: "A"),
            FileChange(path: "Tests/FeatureTests.swift", insertions: 15, deletions: 0, status: "A"),
        ]
        let flags = RiskHeuristics.evaluate(files: files)
        #expect(!flags.contains { $0.kind == .noTestsAlongsideSource })
    }

    @Test("docs-only changes are not flagged as untested source")
    func docsOnly() {
        let files = [FileChange(path: "README.md", insertions: 30, deletions: 5, status: "M")]
        let flags = RiskHeuristics.evaluate(files: files)
        #expect(!flags.contains { $0.kind == .noTestsAlongsideSource })
    }
}
