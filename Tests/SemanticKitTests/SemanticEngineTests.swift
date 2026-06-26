import Testing
import Foundation
import RecapCore
@testable import SemanticKit

@Suite("Semantic engine + prompts")
struct SemanticEngineTests {
    /// A small hand-built report so prompt tests don't need a git repo.
    private func sampleReport() -> ChangeReport {
        let commits = [
            Commit(sha: "a", shortSHA: "a", authorName: "Alice", authorEmail: "a@x.com",
                   date: Date(timeIntervalSince1970: 0), subject: "add CSV export",
                   type: .feat, scope: "export", breaking: false, isMerge: false, ticket: "NOV-1"),
            Commit(sha: "b", shortSHA: "b", authorName: "Alice", authorEmail: "a@x.com",
                   date: Date(timeIntervalSince1970: 1), subject: "tidy imports",
                   type: .chore, scope: nil, breaking: false, isMerge: false, ticket: nil),
        ]
        let files = [FileChange(path: "Sources/Export.swift", insertions: 80, deletions: 4, status: "M")]
        let vitals = Vitals(
            features: 1, fixes: 0, chores: 1, filesChanged: 1,
            insertions: 80, deletions: 4,
            contributors: [Contributor(name: "Alice", email: "a@x.com", commitCount: 2)],
            branchCount: 1, hotspots: files
        )
        return ChangeReport(
            range: ChangeRange(base: "main", head: "HEAD", baseSHA: "b0", headSHA: "h0", mergeBaseSHA: "b0"),
            commits: commits, files: files, branches: [], vitals: vitals, riskFlags: []
        )
    }

    @Test("context block carries the report's hard facts")
    func contextFacts() {
        let block = PromptBuilder.contextBlock(sampleReport())
        #expect(block.contains("1 features, 0 fixes, 1 chores"))
        #expect(block.contains("+80/-4"))
        #expect(block.contains("add CSV export"))
        #expect(block.contains("NOV-1"))
        #expect(block.contains("Sources/Export.swift"))
    }

    @Test("new-features prompt instructs feature filtering")
    func newPrompt() {
        let req = PromptBuilder.newFeatures(sampleReport())
        #expect(req.system.contains("NEW USER-FACING FEATURES"))
        #expect(req.messages.first?.text.contains("add CSV export") == true)
    }

    @Test("PR-note prompt asks for the required sections")
    func prPrompt() {
        let req = PromptBuilder.pullRequestNote(sampleReport())
        #expect(req.system.contains("PULL REQUEST DESCRIPTION"))
        #expect(req.system.contains("Areas to review"))
    }

    @Test("engine returns the model's text and sends one request")
    func engineNew() async throws {
        let mock = MockModelClient(response: "- CSV export")
        let engine = SemanticEngine(client: mock)
        let out = try await engine.newFeatures(sampleReport())
        #expect(out == "- CSV export")
        #expect(mock.requests.count == 1)
    }

    @Test("engine trims whitespace around model output")
    func engineTrims() async throws {
        let mock = MockModelClient(response: "\n\n  ## Summary\nDoes a thing.\n\n")
        let engine = SemanticEngine(client: mock)
        let out = try await engine.pullRequestNote(sampleReport())
        #expect(out == "## Summary\nDoes a thing.")
    }

    @Test("engine propagates model errors")
    func engineError() async {
        let mock = MockModelClient()
        mock.errorToThrow = ModelError.missingAPIKey
        let engine = SemanticEngine(client: mock)
        await #expect(throws: ModelError.self) {
            _ = try await engine.newFeatures(sampleReport())
        }
    }
}
