import Testing
@testable import RecapCore

@Suite("Inference end-to-end (against real git)")
struct InferenceIntegrationTests {
    @Test("non-conventional commits get features recovered, marked inferred")
    func recoversFeatures() throws {
        // Mirrors the real-world Ledgerly case: no feat:/fix: prefixes.
        let f = try GitFixture()
        try f.write("README.md", "# app\n")
        try f.commit("Initial commit")
        try f.checkout(newBranch: "new-face")
        try f.write("Sources/NewFaceFeature.swift", "// feature\n")
        try f.commit("Ship the New Face behind a feature flag")
        try f.write("Sources/PlanTab.swift", "// plan\n")
        try f.commit("Make New Face the default")
        try f.write("project.pbxproj", "version 2.0\n")
        try f.commit("Bump marketing version 1.7 to 2.0")

        let report = try ChangeReportBuilder(git: f.git).build(base: "main", head: "HEAD")

        // Two feature-ish commits recovered, one chore (the version bump).
        #expect(report.vitals.features == 2)
        #expect(report.vitals.chores == 1)
        // All three came from inference, not declared prefixes.
        #expect(report.vitals.inferredCount == 3)
        // The parsed type is still .other — we never overwrote it.
        #expect(report.commits.allSatisfy { $0.type == .other })
        // And the commits carry their inferred bucket.
        let shipped = try #require(report.commits.first { $0.subject.contains("Ship") })
        #expect(shipped.inferredBucket == .feature)
        #expect(shipped.isInferred)
        #expect(shipped.effectiveBucket == .feature)
    }

    @Test("conventional commits stay authoritative, not inferred")
    func conventionalUnaffected() throws {
        let f = try GitFixture()
        try f.write("a.txt", "1\n")
        try f.commit("chore: base")
        try f.checkout(newBranch: "work")
        try f.write("Sources/X.swift", "x\n")
        try f.commit("feat: add X")
        try f.write("Sources/X.swift", "x2\n")
        try f.commit("fix: correct X")

        let report = try ChangeReportBuilder(git: f.git).build(base: "main", head: "HEAD")
        #expect(report.vitals.features == 1)
        #expect(report.vitals.fixes == 1)
        // Nothing inferred — both commits had declared prefixes.
        #expect(report.vitals.inferredCount == 0)
        #expect(report.commits.allSatisfy { !$0.isInferred })
    }

    @Test("a fix verb in a non-conventional commit infers a fix")
    func inferredFix() throws {
        let f = try GitFixture()
        try f.write("a.txt", "1\n")
        try f.commit("Initial")
        try f.checkout(newBranch: "work")
        try f.write("a.txt", "2\n")
        try f.commit("Fix the crash when the list is empty")

        let report = try ChangeReportBuilder(git: f.git).build(base: "main", head: "HEAD")
        #expect(report.vitals.fixes == 1)
        #expect(report.vitals.features == 0)
        #expect(report.vitals.inferredCount == 1)
    }
}
