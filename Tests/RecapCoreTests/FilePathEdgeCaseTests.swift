import Testing
import Foundation
@testable import RecapCore

@Suite("File-path edge cases")
struct FilePathEdgeCaseTests {
    // MARK: - normalizeRenamePath (unit)

    @Test("plain paths pass through unchanged")
    func plainPath() {
        #expect(ChangeReportBuilder.normalizeRenamePath("a/b/c.swift") == "a/b/c.swift")
        #expect(ChangeReportBuilder.normalizeRenamePath("file.txt") == "file.txt")
    }

    @Test("simple rename resolves to the new path")
    func simpleRename() {
        #expect(ChangeReportBuilder.normalizeRenamePath("old.swift => new.swift") == "new.swift")
        #expect(ChangeReportBuilder.normalizeRenamePath("a/old.swift => a/new.swift") == "a/new.swift")
    }

    @Test("braced rename resolves to the new path")
    func bracedRename() {
        #expect(ChangeReportBuilder.normalizeRenamePath("src/{old => new}/mod.swift") == "src/new/mod.swift")
        #expect(ChangeReportBuilder.normalizeRenamePath("{a => b}/x.swift") == "b/x.swift")
        // Moving up a level: pre/{sub => }/file → pre/file (no doubled slash).
        #expect(ChangeReportBuilder.normalizeRenamePath("pre/{old => }/file.swift") == "pre/file.swift")
    }

    // MARK: - Integration (against real git)

    @Test("non-ASCII filenames come through as UTF-8, not octal-escaped")
    func nonASCIIPath() throws {
        let f = try GitFixture()
        try f.write("base.txt", "x\n")
        try f.commit("chore: base")
        try f.checkout(newBranch: "work")
        try f.write("café.swift", "y\n")
        try f.commit("feat: add unicode-named file")

        let report = try ChangeReportBuilder(git: f.git).build(base: "main", head: "HEAD")
        #expect(report.files.map(\.path).contains("café.swift"))
        // No octal-escaped, quote-wrapped path leaked through.
        #expect(!report.files.contains { $0.path.contains("\\303") })
    }

    @Test("a rename reads as the new path with status R")
    func renameIntegration() throws {
        let f = try GitFixture()
        try f.write("original.swift", "1\n2\n3\n4\n")
        try f.commit("chore: base")
        try f.checkout(newBranch: "work")
        try f.git.run(["mv", "original.swift", "renamed.swift"])
        try f.commit("chore: rename")

        let report = try ChangeReportBuilder(git: f.git).build(base: "main", head: "HEAD")
        let renamed = try #require(report.files.first)
        #expect(renamed.path == "renamed.swift")
        #expect(renamed.status == "R")
        #expect(!renamed.path.contains("=>"))
    }
}
