import Foundation

/// A single message in a model exchange.
public struct ChatMessage: Sendable, Equatable {
    public enum Role: String, Sendable { case user, assistant }
    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// A model request: system prompt + conversation + sampling controls.
public struct ModelRequest: Sendable {
    public var system: String
    public var messages: [ChatMessage]
    public var maxTokens: Int
    public var temperature: Double

    public init(system: String, messages: [ChatMessage], maxTokens: Int = 1024, temperature: Double = 0.4) {
        self.system = system
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

/// Abstraction over the chat-completion call. The semantic commands depend on
/// this protocol, never on a concrete client — so tests inject a mock and CI
/// stays offline, while production uses `AnthropicClient`.
public protocol ModelClient: Sendable {
    /// Send a request and return the assistant's text response.
    func complete(_ request: ModelRequest) async throws -> String
}

/// Errors from the Anthropic transport.
public enum ModelError: Error, CustomStringConvertible, Equatable {
    case missingAPIKey
    case requestFailed(status: Int, body: String)
    case malformedResponse(String)
    case transport(String)

    public var description: String {
        switch self {
        case .missingAPIKey:
            return "No Anthropic API key. Set ANTHROPIC_API_KEY or configure it in testthese.toml."
        case let .requestFailed(status, body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Anthropic API request failed (HTTP \(status))\(detail.isEmpty ? "" : ": \(detail)")"
        case let .malformedResponse(detail):
            return "Could not parse Anthropic API response: \(detail)"
        case let .transport(detail):
            return "Network error talking to Anthropic API: \(detail)"
        }
    }
}

/// Hand-rolled Anthropic Messages API client over URLSession.
///
/// PRD §9: there's no official Anthropic Swift SDK, and the repo keeps a
/// zero-dependency stance, so CLI-mode calls go through a small URLSession POST
/// rather than a community package. Lives in SemanticKit, never in RecapCore —
/// the deterministic core must stay offline.
public struct AnthropicClient: ModelClient {
    public let apiKey: String
    public let model: String
    public let baseURL: URL
    public let apiVersion: String
    private let session: URLSession

    public init(
        apiKey: String,
        model: String,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        apiVersion: String = "2023-06-01",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.apiVersion = apiVersion
        self.session = session
    }

    public func complete(_ request: ModelRequest) async throws -> String {
        var httpRequest = URLRequest(url: baseURL)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        httpRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        httpRequest.httpBody = try encodeBody(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: httpRequest)
        } catch {
            throw ModelError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ModelError.malformedResponse("response was not HTTP")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ModelError.requestFailed(
                status: http.statusCode,
                body: String(decoding: data, as: UTF8.self)
            )
        }
        return try decodeText(from: data)
    }

    // MARK: - Wire format

    private func encodeBody(_ request: ModelRequest) throws -> Data {
        let body = MessagesRequestBody(
            model: model,
            maxTokens: request.maxTokens,
            temperature: request.temperature,
            system: request.system,
            messages: request.messages.map {
                MessagesRequestBody.Message(role: $0.role.rawValue, content: $0.text)
            }
        )
        return try JSONEncoder().encode(body)
    }

    private func decodeText(from data: Data) throws -> String {
        let decoded: MessagesResponseBody
        do {
            decoded = try JSONDecoder().decode(MessagesResponseBody.self, from: data)
        } catch {
            throw ModelError.malformedResponse(error.localizedDescription)
        }
        let text = decoded.content
            .filter { $0.type == "text" }
            .map(\.text)
            .joined()
        guard !text.isEmpty else {
            throw ModelError.malformedResponse("no text content in response")
        }
        return text
    }
}

// Wire models for the Messages API. Private to the client.

private struct MessagesRequestBody: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let maxTokens: Int
    let temperature: Double
    let system: String
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model, temperature, system, messages
        case maxTokens = "max_tokens"
    }
}

private struct MessagesResponseBody: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String
    }
    let content: [Block]
}
