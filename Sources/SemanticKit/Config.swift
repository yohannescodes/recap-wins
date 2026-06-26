import Foundation

/// A product profile (PRD §8): voice and links the semantic layer renders in.
public struct ProductProfile: Sendable, Equatable {
    public var id: String
    public var name: String
    public var voice: String
    public var links: [String]

    public init(id: String, name: String, voice: String, links: [String]) {
        self.id = id
        self.name = name
        self.voice = voice
        self.links = links
    }
}

/// Repo configuration (PRD §8). Per-repo, human-readable, no global state.
///
/// This pass reads the keys the core semantic slice needs: `base`, `model`, an
/// optional `api_key`, and `[[product]]` profiles. Limit manifests and target
/// caps (§6.1) land with the store-targets follow-up.
public struct Config: Sendable, Equatable {
    public var base: String
    public var model: String
    /// Optional key from config; env var takes precedence (see ModelConfig).
    public var apiKey: String?
    public var products: [ProductProfile]

    public static let defaultModel = "claude-sonnet-4-6"

    public init(
        base: String = "main",
        model: String = Config.defaultModel,
        apiKey: String? = nil,
        products: [ProductProfile] = []
    ) {
        self.base = base
        self.model = model
        self.apiKey = apiKey
        self.products = products
    }

    /// Look up a product profile by id.
    public func product(_ id: String) -> ProductProfile? {
        products.first { $0.id == id }
    }

    /// Load config from a repo directory. Searches for `testthese.toml` then
    /// `.testtheserc`. Returns defaults if no config file is present — the tool
    /// must work in a bare repo with no config.
    public static func load(fromRepo repoPath: String) throws -> Config {
        let candidates = ["testthese.toml", ".testtheserc"]
        let fm = FileManager.default
        for name in candidates {
            let path = (repoPath as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: path) {
                let text = try String(contentsOfFile: path, encoding: .utf8)
                return try parse(text)
            }
        }
        return Config()
    }

    /// Parse the supported subset of the TOML config. A focused reader rather
    /// than a TOML dependency, matching the file shape in PRD §8.
    public static func parse(_ toml: String) throws -> Config {
        var config = Config()
        var products: [ProductProfile] = []
        var current: [String: TOMLValue]? = nil
        var inProductTable = false

        func flushProduct() {
            guard inProductTable, let table = current else { return }
            guard let id = table["id"]?.string, let name = table["name"]?.string else { return }
            products.append(ProductProfile(
                id: id,
                name: name,
                voice: table["voice"]?.string ?? "",
                links: table["links"]?.stringArray ?? []
            ))
        }

        for rawLine in toml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // Table header.
            if line == "[[product]]" {
                flushProduct()
                current = [:]
                inProductTable = true
                continue
            }
            if line.hasPrefix("[") {
                // Any other table (e.g. [limits_manifest]) — flush product and
                // ignore the rest in this pass.
                flushProduct()
                current = nil
                inProductTable = false
                continue
            }

            // key = value
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let valueText = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            let value = TOMLValue(parsing: valueText)

            if inProductTable {
                current?[key] = value
            } else {
                // Top-level scalars.
                switch key {
                case "base": if let s = value.string { config.base = s }
                case "model": if let s = value.string { config.model = s }
                case "api_key": config.apiKey = value.string
                default: break
                }
            }
        }
        flushProduct()
        config.products = products
        return config
    }

    /// Remove an unquoted `#` comment from a line, preserving `#` inside strings.
    private static func stripComment(_ line: String) -> String {
        var inString = false
        var result = ""
        for ch in line {
            if ch == "\"" { inString.toggle() }
            if ch == "#" && !inString { break }
            result.append(ch)
        }
        return result
    }
}

/// Minimal TOML value: the scalar/array forms the config uses.
private struct TOMLValue {
    let raw: String

    init(parsing text: String) { self.raw = text }

    /// A quoted string, unquoted.
    var string: String? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 else { return nil }
        return String(t.dropFirst().dropLast())
    }

    /// An inline array of quoted strings, e.g. `["a", "b"]`.
    var stringArray: [String]? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("[") && t.hasSuffix("]") else { return nil }
        let inner = t.dropFirst().dropLast()
        if inner.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        return inner.split(separator: ",").compactMap {
            TOMLValue(parsing: String($0)).string
        }
    }
}
