import Foundation

/// Hand-rolled Google Gemini client over URLSession, behind the same
/// `ModelClient` protocol as `AnthropicClient`.
///
/// Calls the Generative Language API's `generateContent` endpoint. Zero
/// dependencies, mirroring the Anthropic client — lives in SemanticKit, never in
/// RecapCore. Selected via `--provider gemini` / `provider = "gemini"`.
public struct GeminiClient: ModelClient {
    public let apiKey: String
    public let model: String
    /// Base endpoint up to (and including) `/models`. The model + `:generateContent`
    /// and the API key are appended per request.
    public let baseURL: URL
    private let session: URLSession

    /// Pinned GA model, not the `-latest` alias — aliases can resolve to
    /// experimental endpoints with tighter rate limits and unstable availability.
    public static let defaultModel = "gemini-3.5-flash"

    public init(
        apiKey: String,
        model: String,
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.session = session
    }

    public func complete(_ request: ModelRequest) async throws -> String {
        // Endpoint: {base}/{model}:generateContent?key=API_KEY
        let url = baseURL
            .appendingPathComponent("\(model):generateContent")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let finalURL = components?.url else {
            throw ModelError.malformedResponse("could not build Gemini request URL")
        }

        var httpRequest = URLRequest(url: finalURL)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        // Gemini: system_instruction is its own field; the conversation goes in
        // `contents` with role + parts. Map assistant → "model" (Gemini's name).
        let contents = request.messages.map { message in
            GenerateContentBody.Content(
                role: message.role == .assistant ? "model" : "user",
                parts: [GenerateContentBody.Part(text: message.text)]
            )
        }
        let body = GenerateContentBody(
            systemInstruction: request.system.isEmpty
                ? nil
                : GenerateContentBody.Content(role: nil, parts: [.init(text: request.system)]),
            contents: contents,
            generationConfig: .init(
                temperature: request.temperature,
                maxOutputTokens: request.maxTokens
            )
        )
        return try JSONEncoder().encode(body)
    }

    private func decodeText(from data: Data) throws -> String {
        let decoded: GenerateContentResponse
        do {
            decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        } catch {
            throw ModelError.malformedResponse(error.localizedDescription)
        }
        let text = decoded.candidates?
            .first?.content?.parts?
            .compactMap(\.text)
            .joined() ?? ""
        guard !text.isEmpty else {
            throw ModelError.malformedResponse("no text content in Gemini response")
        }
        return text
    }
}

// Wire models for the generateContent API. Private to the client.

private struct GenerateContentBody: Encodable {
    struct Part: Encodable { let text: String }
    struct Content: Encodable {
        let role: String?
        let parts: [Part]
    }
    struct GenerationConfig: Encodable {
        let temperature: Double
        let maxOutputTokens: Int
    }
    let systemInstruction: Content?
    let contents: [Content]
    let generationConfig: GenerationConfig

    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
        case generationConfig
    }
}

private struct GenerateContentResponse: Decodable {
    struct Part: Decodable { let text: String? }
    struct Content: Decodable { let parts: [Part]? }
    struct Candidate: Decodable { let content: Content? }
    let candidates: [Candidate]?
}
