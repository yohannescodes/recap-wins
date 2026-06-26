import Testing
import Foundation
import RecapCore
@testable import SemanticKit

@Suite("Notes targets & cap enforcement")
struct NoteTargetTests {
    private func report() -> ChangeReport {
        let files = [FileChange(path: "Sources/Export.swift", insertions: 80, deletions: 4, status: "M")]
        let vitals = Vitals(features: 1, fixes: 0, chores: 0, filesChanged: 1,
                            insertions: 80, deletions: 4, contributors: [], branchCount: 1, hotspots: files)
        return ChangeReport(
            range: ChangeRange(base: "main", head: "HEAD", baseSHA: "b", headSHA: "h", mergeBaseSHA: "b"),
            commits: [], files: files, branches: [], vitals: vitals, riskFlags: [])
    }

    private let ledgerly = ProductProfile(
        id: "ledgerly", name: "Ledgerly",
        voice: "clear, trustworthy, private-by-default",
        links: [], platform: .iOS, targets: ["asc_update": 300])

    @Test("voice targets need a product, internal ones don't")
    func voiceFlags() {
        #expect(NoteTarget.ascUpdate.usesProductVoice)
        #expect(NoteTarget.gpUpdate.usesProductVoice)
        #expect(NoteTarget.whatNew.usesProductVoice)
        #expect(!NoteTarget.pr.usesProductVoice)
        #expect(!NoteTarget.ascReviewer.usesProductVoice)
    }

    @Test("store-update prompt carries product voice and length aim")
    func storePrompt() {
        let limit = ResolvedLimit(ceiling: 4000, softTarget: 300)
        let req = PromptBuilder.note(report(), target: .ascUpdate, product: ledgerly, limit: limit)
        #expect(req.system.contains("clear, trustworthy"))
        #expect(req.system.contains("Ledgerly"))
        #expect(req.system.contains("300 characters"))
        #expect(req.system.contains("4000 characters"))
    }

    @Test("app-review prompt is voice-neutral and mentions reviewer")
    func reviewerPrompt() {
        let req = PromptBuilder.note(report(), target: .ascReviewer, product: nil,
                                     limit: ResolvedLimit(ceiling: 0, softTarget: nil))
        #expect(req.system.contains("App Review"))
        #expect(!req.system.contains("voice:"))
    }

    @Test("engine warns (does not truncate) when output overflows ceiling")
    func overflowWarns() async throws {
        let long = String(repeating: "x", count: 600)
        let engine = SemanticEngine(client: MockModelClient(response: long))
        let result = try await engine.note(
            report(), target: .gpUpdate, product: ledgerly,
            limit: ResolvedLimit(ceiling: 500, softTarget: 250))
        #expect(result.text.count == 600)         // not truncated
        #expect(result.overflowWarning != nil)
        #expect(result.overflowWarning?.contains("500") == true)
    }

    @Test("engine has no warning when within the ceiling")
    func withinCeiling() async throws {
        let engine = SemanticEngine(client: MockModelClient(response: "short note"))
        let result = try await engine.note(
            report(), target: .ascUpdate, product: ledgerly,
            limit: ResolvedLimit(ceiling: 4000, softTarget: 300))
        #expect(result.overflowWarning == nil)
    }
}
