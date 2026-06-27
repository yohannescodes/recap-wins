import Testing
import Foundation
import RecapCore
@testable import SemanticKit

@Suite("Equivalence table")
struct EquivalenceTableTests {
    @Test("ships with the canonical Apple↔Google pairs")
    func builtIns() {
        let pairs = EquivalenceTable.appleGoogle
        let apple = pairs.map(\.a)
        let google = pairs.map(\.b)
        // A few load-bearing pairs that the FRD calls out specifically.
        #expect(apple.contains("Apple Pay") && google.contains("Google Pay"))
        #expect(apple.contains("Sign in with Apple") && google.contains("Google Sign-In"))
        #expect(apple.contains("StoreKit") && google.contains("Play Billing"))
        #expect(apple.contains("HealthKit") && google.contains("Health Connect"))
        #expect(apple.contains("APNs") && google.contains("FCM"))
        // All entries carry a note — auditability of equivalence decisions.
        #expect(pairs.allSatisfy { $0.note != nil })
    }

    @Test("merging prefers product-curated entries on the same pair")
    func mergePrefersProduct() {
        let curated = [
            ParityEntry(a: "Apple Pay", b: "Google Pay",
                        note: "we wrap both behind a Stripe abstraction"),
            ParityEntry(a: "Custom A", b: "Custom B", note: "product-only"),
        ]
        let merged = EquivalenceTable.merged(with: curated)
        // The product's Apple Pay note wins over the built-in note.
        let applePay = merged.first { $0.a == "Apple Pay" && $0.b == "Google Pay" }
        #expect(applePay?.note == "we wrap both behind a Stripe abstraction")
        // Product-only entries are kept; built-in is intact.
        #expect(merged.contains { $0.a == "Custom A" && $0.b == "Custom B" })
        #expect(merged.count == EquivalenceTable.appleGoogle.count + 1)
    }

    @Test("merging is case-insensitive on the (a, b) tuple")
    func mergeCaseInsensitive() {
        let curated = [
            ParityEntry(a: "apple pay", b: "google pay", note: "lowercased dup"),
        ]
        let merged = EquivalenceTable.merged(with: curated)
        // No phantom duplicate from the case difference.
        let count = merged.filter { $0.a.lowercased() == "apple pay" }.count
        #expect(count == 1)
    }
}

@Suite("Align matcher (prompt + response parsing)")
struct AlignMatcherTests {
    private let ledgerA = LedgerSnapshot(
        portName: "ios", repositoryPath: "/tmp/a", ref: "main",
        headSHA: "aaaaaaa", since: "v1.0", sinceSHA: "0000",
        features: [
            LedgerFeature(id: "f1", title: "Apple Pay checkout",
                          scope: nil, origin: .declared,
                          sha: "1111111", date: Date(timeIntervalSince1970: 0)),
            LedgerFeature(id: "f2", title: "Onboarding tour",
                          scope: nil, origin: .declared,
                          sha: "2222222", date: Date(timeIntervalSince1970: 1)),
        ])
    private let ledgerB = LedgerSnapshot(
        portName: "android", repositoryPath: "/tmp/b", ref: "main",
        headSHA: "bbbbbbb", since: "v1.0", sinceSHA: "0000",
        features: [
            LedgerFeature(id: "g1", title: "Google Pay checkout",
                          scope: nil, origin: .declared,
                          sha: "3333333", date: Date(timeIntervalSince1970: 0)),
            LedgerFeature(id: "g2", title: "Widget on home screen",
                          scope: nil, origin: .declared,
                          sha: "4444444", date: Date(timeIntervalSince1970: 1)),
        ])

    @Test("prompt carries both ledgers, equivalence table, and the JSON schema")
    func promptShape() {
        let req = PromptBuilder.alignMatch(
            ledgerA: ledgerA, ledgerB: ledgerB,
            equivalences: EquivalenceTable.appleGoogle,
            productName: "Ledgerly")
        // System prompt sets the anti-overclaim rules.
        #expect(req.system.contains("paired"))
        #expect(req.system.contains("equivalent"))
        #expect(req.system.contains("gap_on_a"))
        #expect(req.system.contains("gap_on_b"))
        #expect(req.system.contains("ambiguous"))
        // The disclaimer / overclaim rule MUST be in the prompt.
        #expect(req.system.contains("NEVER assert authoritative parity"))
        #expect(req.system.contains("\"ambiguous\""))
        #expect(req.system.contains("Ledgerly"))
        // User message has both ledgers + equivalence table.
        let user = req.messages.first?.text ?? ""
        #expect(user.contains("Apple Pay checkout"))
        #expect(user.contains("Google Pay checkout"))
        #expect(user.contains("Onboarding tour"))
        #expect(user.contains("Widget on home screen"))
        #expect(user.contains("A: Apple Pay  ↔  B: Google Pay"))
        // Origin marker is exposed so the matcher can weight inferred lower.
        #expect(user.contains("[declared]"))
    }

    @Test("matcher decodes a clean JSON response into typed features + issues")
    func parsesCleanResponse() async throws {
        let response = """
        {
          "features": [
            {"id": "m1", "status": "equivalent",
             "descriptionA": "Apple Pay checkout",
             "descriptionB": "Google Pay checkout",
             "equivalenceNote": "platform-native payment", "confidence": 0.95},
            {"id": "m2", "status": "gap_on_b",
             "descriptionA": "Onboarding tour",
             "descriptionB": null, "confidence": 0.9},
            {"id": "m3", "status": "gap_on_a",
             "descriptionA": null,
             "descriptionB": "Widget on home screen", "confidence": 0.85}
          ],
          "issues": [
            {"side": "android", "title": "Port onboarding tour",
             "body": "iOS ships an onboarding tour. Android needs parity.",
             "sourceFeature": "Onboarding tour"},
            {"side": "ios", "title": "Add home-screen widget",
             "body": "Android has a widget. iOS needs WidgetKit equivalent.",
             "sourceFeature": "Widget on home screen"}
          ]
        }
        """
        let engine = SemanticEngine(client: MockModelClient(response: response))
        let result = try await engine.alignFeatures(
            ledgerA: ledgerA, ledgerB: ledgerB,
            equivalences: EquivalenceTable.appleGoogle,
            productName: "Ledgerly")
        #expect(result.features.count == 3)
        #expect(result.features[0].status == .equivalent)
        #expect(result.features[1].status == .gapOnB)
        #expect(result.features[2].status == .gapOnA)
        #expect(result.features[0].confidence == 0.95)
        #expect(result.issues.count == 2)
        #expect(result.issues[0].side == "android")
        #expect(result.issues[1].side == "ios")
    }

    @Test("matcher tolerates markdown fences and leading prose around the JSON")
    func tolerantParsing() async throws {
        let response = """
        Sure! Here's the match:

        ```json
        {
          "features": [
            {"id": "m1", "status": "paired",
             "descriptionA": "X", "descriptionB": "X", "confidence": 0.9}
          ],
          "issues": []
        }
        ```

        Let me know if you need anything else!
        """
        let engine = SemanticEngine(client: MockModelClient(response: response))
        let result = try await engine.alignFeatures(
            ledgerA: ledgerA, ledgerB: ledgerB,
            equivalences: [], productName: nil)
        #expect(result.features.count == 1)
        #expect(result.features[0].status == .paired)
    }

    @Test("missing confidence defaults to 0.5; out-of-range values clamp")
    func confidenceDefaultsAndClamps() async throws {
        let response = """
        {
          "features": [
            {"id": "m1", "status": "paired", "descriptionA": "A", "descriptionB": "A"},
            {"id": "m2", "status": "paired", "descriptionA": "B", "descriptionB": "B", "confidence": 1.7},
            {"id": "m3", "status": "paired", "descriptionA": "C", "descriptionB": "C", "confidence": -0.4}
          ]
        }
        """
        let engine = SemanticEngine(client: MockModelClient(response: response))
        let result = try await engine.alignFeatures(
            ledgerA: ledgerA, ledgerB: ledgerB,
            equivalences: [], productName: nil)
        #expect(result.features[0].confidence == 0.5)
        #expect(result.features[1].confidence == 1.0)
        #expect(result.features[2].confidence == 0.0)
    }

    @Test("unknown status strings degrade to ambiguous (never crash)")
    func unknownStatusDegrades() async throws {
        let response = """
        {"features": [
            {"id": "m1", "status": "definitely_paired", "descriptionA": "A",
             "descriptionB": "A", "confidence": 0.8}
        ], "issues": []}
        """
        let engine = SemanticEngine(client: MockModelClient(response: response))
        let result = try await engine.alignFeatures(
            ledgerA: ledgerA, ledgerB: ledgerB,
            equivalences: [], productName: nil)
        #expect(result.features[0].status == .ambiguous)
    }

    @Test("non-JSON response surfaces a clean ModelError, not a crash")
    func nonJSONFails() async throws {
        let engine = SemanticEngine(client: MockModelClient(response: "no json here"))
        await #expect(throws: ModelError.self) {
            try await engine.alignFeatures(
                ledgerA: ledgerA, ledgerB: ledgerB,
                equivalences: [], productName: nil)
        }
    }
}

@Suite("Align skill envelope")
struct AlignSkillEnvelopeTests {
    private let ledgerA = LedgerSnapshot(
        portName: "ios", repositoryPath: "/tmp/a", ref: "main",
        headSHA: "aaaaaaa", since: nil, sinceSHA: nil,
        features: [])
    private let ledgerB = LedgerSnapshot(
        portName: "android", repositoryPath: "/tmp/b", ref: "main",
        headSHA: "bbbbbbb", since: nil, sinceSHA: nil,
        features: [])

    @Test("envelope carries both ledgers, the equivalence table, and JSON-schema instruction")
    func envelopeShape() throws {
        let env = SkillEnvelope.forAlign(
            ledgerA: ledgerA, ledgerB: ledgerB,
            equivalences: EquivalenceTable.appleGoogle,
            product: nil, productId: "ledgerly", since: "v1.0")
        #expect(env.command == "align")
        #expect(env.product == "ledgerly")
        #expect(env.since == "v1.0")
        #expect(env.ledgerA.portName == "ios")
        #expect(env.ledgerB.portName == "android")
        #expect(env.equivalences.count == EquivalenceTable.appleGoogle.count)
        // Instruction explicitly asks for JSON-only output (no fences).
        #expect(env.instruction.contains("JSON"))
        #expect(env.instruction.contains("\"ambiguous\""))
        // System prompt is the same matcher prompt the API path uses.
        #expect(env.system.contains("gap_on_a"))
    }

    @Test("envelope round-trips through JSON without loss")
    func envelopeRoundTrips() throws {
        let env = SkillEnvelope.forAlign(
            ledgerA: ledgerA, ledgerB: ledgerB,
            equivalences: [
                ParityEntry(a: "X", b: "Y", note: "test"),
            ],
            product: nil, productId: nil, since: nil)
        let json = try env.jsonString()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AlignEnvelope.self, from: Data(json.utf8))
        #expect(decoded == env)
    }
}
