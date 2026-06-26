import Testing
import Foundation
@testable import RecapCore

@Suite("ChangeReportBuilder (against real git)")
struct ChangeReportBuilderTests {
    /// A linear feature branch: base on main, two feat + one fix + one chore.
    private func featureBranchFixture() throws -> GitFixture {
        let f = try GitFixture()
        try f.write("README.md", "# Project\n")
        try f.commit("chore: initial commit")          // on main, before branch
        try f.checkout(newBranch: "feature/login")
        try f.write("Sources/Login.swift", "// login\n")
        try f.commit("feat: add login screen")
        try f.write("Sources/Login.swift", "// login v2\n")
        try f.commit("feat(auth): wire up session")
        try f.write("Sources/Login.swift", "// login v2 fixed\n")
        try f.commit("fix: handle empty password")
        try f.write("Sources/Login.swift", "// login v2 fixed + cleanup\n")
        try f.commit("chore: tidy imports")
        return f
    }

    @Test("counts buckets from conventional commits, excluding base")
    func vitalsBuckets() throws {
        let f = try featureBranchFixture()
        let report = try ChangeReportBuilder(git: f.git).build(base: "main", head: "HEAD")
        #expect(report.vitals.features == 2)
        #expect(report.vitals.fixes == 1)
        #expect(report.vitals.chores == 1)   // the base "chore: initial" is excluded
        #expect(report.commits.count == 4)
    }

    @Test("range resolves base, head, and merge-base")
    func range() throws {
        let f = try featureBranchFixture()
        let report = try ChangeReportBuilder(git: f.git).build(base: "main", head: "HEAD")
        #expect(report.range.base == "main")
        #expect(!report.range.baseSHA.isEmpty)
        #expect(!report.range.headSHA.isEmpty)
        // The merge-base of a linear branch off main is main's tip.
        #expect(report.range.mergeBaseSHA == report.range.baseSHA)
    }

    @Test("file stats and hotspots reflect the diff")
    func fileStats() throws {
        let f = try featureBranchFixture()
        let report = try ChangeReportBuilder(git: f.git).build(base: "main", head: "HEAD")
        // Only Sources/Login.swift changed relative to main.
        #expect(report.vitals.filesChanged == 1)
        #expect(report.files.first?.path == "Sources/Login.swift")
        #expect(report.vitals.hotspots.first?.path == "Sources/Login.swift")
        #expect(report.vitals.insertions > 0)
    }

    @Test("contributors aggregate by author")
    func contributors() throws {
        let f = try GitFixture()
        try f.write("a.txt", "1\n")
        try f.commit("chore: base")
        try f.checkout(newBranch: "work")
        try f.write("b.swift", "x\n")
        try f.commit("feat: a", authorName: "Alice", authorEmail: "alice@example.com")
        try f.write("c.swift", "y\n")
        try f.commit("feat: b", authorName: "Alice", authorEmail: "alice@example.com")
        try f.write("d.swift", "z\n")
        try f.commit("fix: c", authorName: "Bob", authorEmail: "bob@example.com")

        let report = try ChangeReportBuilder(git: f.git).build(base: "main", head: "HEAD")
        #expect(report.vitals.contributors.count == 2)
        // Alice has the most commits, so she sorts first.
        #expect(report.vitals.contributors.first?.name == "Alice")
        #expect(report.vitals.contributors.first?.commitCount == 2)
    }

    @Test("merge commits are detected and excluded from work counts")
    func merges() throws {
        let f = try GitFixture()
        try f.write("a.txt", "1\n")
        try f.commit("chore: base")
        try f.checkout(newBranch: "side")
        try f.write("s.swift", "x\n")
        try f.commit("feat: side feature")
        try f.checkout("main")
        try f.write("m.swift", "y\n")
        try f.commit("feat: main feature")
        try f.merge("side")   // creates a merge commit on main

        let report = try ChangeReportBuilder(git: f.git).build(base: "side", head: "main")
        #expect(report.commits.contains { $0.isMerge })
        // The merge commit must not inflate feature counts.
        let workCommits = report.commits.filter { !$0.isMerge }
        #expect(report.vitals.features == workCommits.filter { $0.type == .feat }.count)
    }

    @Test("ticket references are detected when present")
    func tickets() throws {
        let f = try GitFixture()
        try f.write("a.txt", "1\n")
        try f.commit("chore: base")
        try f.checkout(newBranch: "work")
        try f.write("b.swift", "x\n")
        try f.commit("feat: thing (NOV-7)")
        let report = try ChangeReportBuilder(git: f.git).build(base: "main", head: "HEAD")
        #expect(report.commits.last?.ticket == "NOV-7")
    }

    @Test("empty change set yields zero vitals, not a crash")
    func emptyRange() throws {
        let f = try GitFixture()
        try f.write("a.txt", "1\n")
        try f.commit("chore: base")
        // base == head: no commits in range.
        let report = try ChangeReportBuilder(git: f.git).build(base: "HEAD", head: "HEAD")
        #expect(report.commits.isEmpty)
        #expect(report.vitals.features == 0)
        #expect(report.vitals.filesChanged == 0)
    }

    @Test("non-repository path throws notARepository")
    func notARepo() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let git = Git(repositoryPath: tmp.path)
        #expect(throws: GitError.self) {
            try ChangeReportBuilder(git: git).build(base: "main", head: "HEAD")
        }
    }

    @Test("report round-trips through JSON")
    func jsonRoundTrip() throws {
        let f = try featureBranchFixture()
        let report = try ChangeReportBuilder(git: f.git).build(base: "main", head: "HEAD")
        let data = try report.jsonData()
        let decoded = try JSONDecoder.recapDecoder().decode(ChangeReport.self, from: data)
        #expect(decoded == report)
    }
}

private extension JSONDecoder {
    static func recapDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
