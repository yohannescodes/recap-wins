import Foundation
import RecapCore

/// Runs the semantic commands: takes a deterministic `ChangeReport`, prompts the
/// model, and returns prose. Generic over `ModelClient` so production uses the
/// live Anthropic client and tests inject a mock — no network in the test path.
public struct SemanticEngine: Sendable {
    public let client: any ModelClient

    public init(client: any ModelClient) {
        self.client = client
    }

    /// `rw new` — list the new user-facing features in the change set.
    public func newFeatures(_ report: ChangeReport) async throws -> String {
        let request = PromptBuilder.newFeatures(report)
        return try await client.complete(request).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `rw notes --pr` — write a PR description for the change set.
    public func pullRequestNote(_ report: ChangeReport) async throws -> String {
        let request = PromptBuilder.pullRequestNote(report)
        return try await client.complete(request).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
