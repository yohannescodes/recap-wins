import Testing
import Foundation
import RecapCore
@testable import SemanticKit

@Suite("Skill-mode envelope")
struct SkillEnvelopeTests {
    private func report() -> ChangeReport {
        let commits = [
            Commit(sha: "a", shortSHA: "a", authorName: "T", authorEmail: "t@t.co",
                   date: Date(timeIntervalSince1970: 0), subject: "feat: add CSV export",
                   type: .feat, scope: nil, breaking: false, isMerge: false, ticket: nil),
        ]
        let files = [FileChange(path: "Export.swift", insertions: 40, deletions: 2, status: "A")]
        let vitals = Vitals(features: 1, fixes: 0, chores: 0, filesChanged: 1,
                            insertions: 40, deletions: 2, contributors: [], branchCount: 1, hotspots: files)
        return ChangeReport(
            range: ChangeRange(base: "main", head: "HEAD", baseSHA: "b", headSHA: "h", mergeBaseSHA: "b"),
            commits: commits, files: files, branches: [], vitals: vitals, riskFlags: [])
    }

    private let ledgerly = ProductProfile(
        id: "led", name: "Ledgerly", voice: "clear, trustworthy",
        links: [], platform: .android, targets: ["gp_update": 250])

    @Test("new envelope carries the prompt and the grounded report")
    func newEnvelope() throws {
        let env = SkillEnvelope.forNewFeatures(report())
        #expect(env.command == "new")
        #expect(env.target == nil)
        #expect(env.system.contains("NEW USER-FACING FEATURES"))
        #expect(env.user.contains("add CSV export"))
        // The host agent gets the full deterministic report for grounding.
        #expect(env.report.vitals.features == 1)
        #expect(env.ceilingChars == 0)
    }

    @Test("note envelope carries target, voice, and resolved caps")
    func noteEnvelope() throws {
        let limit = ResolvedLimit(ceiling: 500, softTarget: 250)
        let env = SkillEnvelope.forNote(report(), target: .gpUpdate, product: ledgerly, limit: limit)
        #expect(env.command == "notes")
        #expect(env.target == "gpUpdate")
        #expect(env.ceilingChars == 500)
        #expect(env.softTargetChars == 250)
        #expect(env.system.contains("clear, trustworthy"))
        #expect(env.instruction.contains("500 characters"))
    }

    @Test("envelope round-trips through JSON")
    func roundTrip() throws {
        let env = SkillEnvelope.forNewFeatures(report())
        let data = Data(try env.jsonString().utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SkillEnvelope.self, from: data)
        #expect(decoded == env)
    }

    @Test("uncapped target leaves no char instruction in the envelope")
    func uncapped() {
        let env = SkillEnvelope.forNote(
            report(), target: .pr, product: nil, limit: ResolvedLimit(ceiling: 0, softTarget: nil))
        #expect(env.ceilingChars == 0)
        #expect(!env.instruction.contains("characters"))
    }
}
