import Foundation

/// A product profile (PRD §8): voice, links, target platform, and soft editorial
/// length targets the semantic layer renders in.
public struct ProductProfile: Sendable, Equatable {
    public var id: String
    public var name: String
    public var voice: String
    public var links: [String]
    /// Mobile platform this product ships on — drives the `--what-new` cap.
    public var platform: Platform
    /// Soft editorial char targets the model AIMS for, per target (PRD §8). Keyed
    /// by the target's config name ("asc_update", "gp_update", "what_new").
    public var targets: [String: Int]

    public init(
        id: String,
        name: String,
        voice: String,
        links: [String],
        platform: Platform = .iOS,
        targets: [String: Int] = [:]
    ) {
        self.id = id
        self.name = name
        self.voice = voice
        self.links = links
        self.platform = platform
        self.targets = targets
    }

    /// The soft target (chars) for a note target, or nil if none configured.
    public func softTarget(for target: NoteTarget) -> Int? {
        switch target {
        case .ascUpdate: return targets["asc_update"]
        case .gpUpdate: return targets["gp_update"]
        case .whatNew: return targets["what_new"]
        case .pr, .ascReviewer: return nil
        }
    }
}

/// Repo configuration (PRD §8). Per-repo, human-readable, no global state.
public struct Config: Sendable, Equatable {
    public var base: String
    public var model: String
    /// Optional key from config; env var takes precedence (see ModelConfig).
    public var apiKey: String?
    public var products: [ProductProfile]
    /// Optional limits-manifest URL (PRD §6.1): published caps fetched + cached.
    public var limitsManifestURL: String?
    /// Manifest cache TTL, e.g. "30d". Defaults to 30 days when unset.
    public var limitsManifestTTL: String?
    /// Baked-in offline fallback ceilings from `[review_notes.limits]`.
    public var reviewNoteLimits: ReviewNoteLimits
    /// Which backend renders prose. Default `anthropic`; `--provider` overrides.
    public var provider: Provider

    public static let defaultModel = "claude-sonnet-4-6"

    public init(
        base: String = "main",
        model: String = Config.defaultModel,
        apiKey: String? = nil,
        products: [ProductProfile] = [],
        limitsManifestURL: String? = nil,
        limitsManifestTTL: String? = nil,
        reviewNoteLimits: ReviewNoteLimits = .fallback,
        provider: Provider = .anthropic
    ) {
        self.base = base
        self.model = model
        self.apiKey = apiKey
        self.products = products
        self.limitsManifestURL = limitsManifestURL
        self.limitsManifestTTL = limitsManifestTTL
        self.reviewNoteLimits = reviewNoteLimits
        self.provider = provider
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

    /// Which table the parser is currently inside.
    private enum Table {
        case top
        case product
        case limitsManifest
        case reviewNoteLimits
        case other
    }

    /// Parse the supported subset of the TOML config. A focused reader rather
    /// than a TOML dependency, matching the file shape in PRD §8.
    public static func parse(_ toml: String) throws -> Config {
        var config = Config()
        var products: [ProductProfile] = []
        var table: Table = .top
        var current: [String: TOMLValue] = [:]

        func flushProduct() {
            guard let id = current["id"]?.string, let name = current["name"]?.string else { return }
            let platform: Platform = current["platform"]?.string.flatMap(Platform.init(rawValue:)) ?? .iOS
            products.append(ProductProfile(
                id: id,
                name: name,
                voice: current["voice"]?.string ?? "",
                links: current["links"]?.stringArray ?? [],
                platform: platform,
                targets: current["targets"]?.intTable ?? [:]
            ))
        }

        for rawLine in toml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // Table header.
            if line.hasPrefix("[") {
                if table == .product { flushProduct() }
                current = [:]
                switch line {
                case "[[product]]": table = .product
                case "[limits_manifest]": table = .limitsManifest
                case "[review_notes.limits]": table = .reviewNoteLimits
                default: table = .other
                }
                continue
            }

            // key = value
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let valueText = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            let value = TOMLValue(parsing: valueText)

            switch table {
            case .product:
                current[key] = value
            case .limitsManifest:
                switch key {
                case "url": config.limitsManifestURL = value.string
                case "ttl": config.limitsManifestTTL = value.string
                default: break
                }
            case .reviewNoteLimits:
                guard let n = value.int else { break }
                switch key {
                case "pr": config.reviewNoteLimits.pr = n
                case "asc_reviewer": config.reviewNoteLimits.ascReviewer = n
                case "what_new_ios": config.reviewNoteLimits.whatNewIOS = n
                case "what_new_android": config.reviewNoteLimits.whatNewAndroid = n
                case "asc_update": config.reviewNoteLimits.ascUpdate = n
                case "gp_update": config.reviewNoteLimits.gpUpdate = n
                default: break
                }
            case .top:
                switch key {
                case "base": if let s = value.string { config.base = s }
                case "model": if let s = value.string { config.model = s }
                case "api_key": config.apiKey = value.string
                case "provider":
                    if let s = value.string, let p = Provider(rawValue: s) { config.provider = p }
                default: break
                }
            case .other:
                break
            }
        }
        if table == .product { flushProduct() }
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

    /// A bare integer, e.g. `500`.
    var int: Int? {
        Int(raw.trimmingCharacters(in: .whitespaces))
    }

    /// An inline table of integers, e.g. `{ asc_update = 300, gp_update = 250 }`.
    var intTable: [String: Int]? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("{") && t.hasSuffix("}") else { return nil }
        let inner = t.dropFirst().dropLast()
        var table: [String: Int] = [:]
        for pair in inner.split(separator: ",") {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let k = pair[..<eq].trimmingCharacters(in: .whitespaces)
            let v = Int(pair[pair.index(after: eq)...].trimmingCharacters(in: .whitespaces))
            if let v { table[k] = v }
        }
        return table
    }
}
