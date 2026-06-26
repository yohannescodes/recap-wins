import Foundation
@testable import SemanticKit

/// A model client that returns canned responses and records the requests it saw,
/// so semantic logic can be tested without network or an API key.
final class MockModelClient: ModelClient, @unchecked Sendable {
    /// The text every `complete` call returns.
    var response: String
    /// Requests captured in call order, for asserting prompt content.
    private(set) var requests: [ModelRequest] = []
    /// If set, `complete` throws this instead of returning.
    var errorToThrow: Error?

    init(response: String = "stubbed response") {
        self.response = response
    }

    func complete(_ request: ModelRequest) async throws -> String {
        requests.append(request)
        if let error = errorToThrow { throw error }
        return response
    }
}
