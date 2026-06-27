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
    /// Optional port pair for `rw align` (FRD §8). When present, `rw align
    /// --product <id>` uses this to find side A and side B.
    public var ports: PortPair?
    /// Curated parity equivalences for `rw align` (FRD §6/§8). Entries the
    /// matcher should treat as already-aligned platform-native substitutes
    /// (Apple Pay ↔ Google Pay), so they stop showing up as gaps.
    public var parityEquivalent: [ParityEntry]

    public init(
        id: String,
        name: String,
        voice: String,
        links: [String],
        platform: Platform = .iOS,
        targets: [String: Int] = [:],
        ports: PortPair? = nil,
        parityEquivalent: [ParityEntry] = []
    ) {
        self.id = id
        self.name = name
        self.voice = voice
        self.links = links
        self.platform = platform
        self.targets = targets
        self.ports = ports
        self.parityEquivalent = parityEquivalent
    }

    /// The soft target (chars) for a note target, or nil if none configured.
    public func softTarget(for target: NoteTarget) -> Int? {
        switch target {
        case .ascUpdate: return targets["asc_update"]
        case .gpUpdate: return targets["gp_update"]
        case .whatNew: return targets["what_new"]
        case .changelog: return targets["changelog"] ?? 1500
        case .pr, .ascReviewer: return nil
        }
    }
}

/// One side of a port pair (FRD §8 `[product.ports]`). A pointer to where the
/// repo lives, what ref to read it at, and a stable name for the side.
public struct PortRef: Sendable, Equatable {
    /// Stable label for this side ("ios", "android"). Used in output and issue
    /// drafts to say which side a gap is on.
    public var name: String
    /// Filesystem path to the repository (absolute or relative to the config).
    public var path: String
    /// Ref to read the ledger at — typically a branch name. Default "main"
    /// matches the rest of the tool.
    public var base: String

    public init(name: String, path: String, base: String = "main") {
        self.name = name
        self.path = path
        self.base = base
    }
}

/// A configured port pair (FRD §8). `rw align --product <id>` reads this to
/// know which two repos to compare.
public struct PortPair: Sendable, Equatable {
    public var a: PortRef
    public var b: PortRef
    /// Baseline ref both ports use (e.g. a port-start tag like "v1.0"). When
    /// set, only features added since this baseline are considered — so old
    /// parity from before the second port even existed doesn't get re-surfaced
    /// every run (FRD §11 "Baseline choice").
    public var since: String?

    public init(a: PortRef, b: PortRef, since: String? = nil) {
        self.a = a
        self.b = b
        self.since = since
    }
}

/// One curated parity equivalence (FRD §6/§8): a feature on side A and the
/// platform-native substitute on side B that the matcher should treat as
/// parity *achieved*, not a gap. Extends the built-in Apple↔Google table.
public struct ParityEntry: Sendable, Equatable, Codable {
    /// Feature title (or canonical name) on side A.
    public var a: String
    /// Feature title (or canonical name) on side B.
    public var b: String
    /// Optional short note explaining why these are equivalent. Shown in the
    /// matcher's `equivalenceNote` field so users can audit decisions.
    public var note: String?

    public init(a: String, b: String, note: String? = nil) {
        self.a = a
        self.b = b
        self.note = note
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
    /// Marketing-field ceilings from `[market.limits]` (PRD §8).
    public var marketLimits: MarketLimits
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
        marketLimits: MarketLimits = .fallback,
        provider: Provider = .anthropic
    ) {
        self.base = base
        self.model = model
        self.apiKey = apiKey
        self.products = products
        self.limitsManifestURL = limitsManifestURL
        self.limitsManifestTTL = limitsManifestTTL
        self.reviewNoteLimits = reviewNoteLimits
        self.marketLimits = marketLimits
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
    ///
    /// `productPorts` and `productParityEquivalent` attach to the most-recent
    /// `[[product]]` block — they're sub-tables of the current product, FRD §8.
    /// The parser keeps the in-flight product fields in `productFields` and
    /// accumulates ports/parity into local buffers until we flush the product.
    private enum Table {
        case top
        case product
        case productPorts
        case productParityEquivalent
        case limitsManifest
        case reviewNoteLimits
        case marketLimits
        case other
    }

    /// Mutable scratch state for the product being built. Keeps the parser's
    /// row-by-row pass simple while letting nested sub-tables (`[product.ports]`,
    /// `[[product.parity.equivalent]]`) attach to the right product.
    private struct ProductScratch {
        var fields: [String: TOMLValue] = [:]
        var portA: PortRef?
        var portB: PortRef?
        var portsSince: String?
        var parity: [ParityEntry] = []
        /// True once we've seen any data for the in-flight product — used to
        /// decide whether to flush. A bare `[[product]]` with nothing under it
        /// stays unflushed (and gets dropped at flush time anyway by the
        /// id/name guard).
        var isActive = false
    }

    /// Parse the supported subset of the TOML config. A focused reader rather
    /// than a TOML dependency, matching the file shape in PRD §8 + FRD §8.
    public static func parse(_ toml: String) throws -> Config {
        var config = Config()
        var products: [ProductProfile] = []
        var table: Table = .top
        var current: [String: TOMLValue] = [:]
        var product = ProductScratch()
        // The ports/parity tables are populated row-by-row, but a single
        // `[product.ports]` block has multiple a/b/since rows. Buffer the
        // current ports block's rows here.
        var portsRows: [String: TOMLValue] = [:]
        var parityRows: [String: TOMLValue] = [:]

        func flushPortsBlock() {
            // a = { name = "ios", path = "...", base = "main" }
            if let aTable = portsRows["a"]?.stringTable,
               let aName = aTable["name"], let aPath = aTable["path"] {
                product.portA = PortRef(
                    name: aName, path: aPath, base: aTable["base"] ?? "main")
            }
            if let bTable = portsRows["b"]?.stringTable,
               let bName = bTable["name"], let bPath = bTable["path"] {
                product.portB = PortRef(
                    name: bName, path: bPath, base: bTable["base"] ?? "main")
            }
            product.portsSince = portsRows["since"]?.string ?? product.portsSince
            portsRows = [:]
        }

        func flushParityBlock() {
            // a = "Apple Pay checkout"
            // b = "Google Pay checkout"
            // note = "platform-native payment"
            if let a = parityRows["a"]?.string, let b = parityRows["b"]?.string {
                product.parity.append(ParityEntry(
                    a: a, b: b, note: parityRows["note"]?.string))
            }
            parityRows = [:]
        }

        func flushProduct() {
            // Flush any pending sub-table rows that haven't been finalized.
            if !portsRows.isEmpty { flushPortsBlock() }
            if !parityRows.isEmpty { flushParityBlock() }
            guard let id = product.fields["id"]?.string,
                  let name = product.fields["name"]?.string else {
                // Reset scratch even if we drop this product, so the next one
                // doesn't inherit stale state.
                product = ProductScratch()
                return
            }
            let platform: Platform = product.fields["platform"]?.string
                .flatMap(Platform.init(rawValue:)) ?? .iOS
            // A valid pair needs both sides; if either is missing, ports are
            // dropped (a half-configured pair would just be confusing).
            let pair: PortPair?
            if let a = product.portA, let b = product.portB {
                pair = PortPair(a: a, b: b, since: product.portsSince)
            } else {
                pair = nil
            }
            products.append(ProductProfile(
                id: id,
                name: name,
                voice: product.fields["voice"]?.string ?? "",
                links: product.fields["links"]?.stringArray ?? [],
                platform: platform,
                targets: product.fields["targets"]?.intTable ?? [:],
                ports: pair,
                parityEquivalent: product.parity
            ))
            product = ProductScratch()
        }

        for rawLine in toml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // Table header.
            if line.hasPrefix("[") {
                // Sub-tables of the current product DON'T flush it; siblings do.
                switch line {
                case "[product.ports]":
                    // A new ports block flushes the previous (only one per product
                    // is meaningful — last one wins if a user repeats).
                    if !portsRows.isEmpty { flushPortsBlock() }
                    table = .productPorts
                    current = [:]
                    product.isActive = true
                    continue
                case "[[product.parity.equivalent]]":
                    // Each [[...]] starts a new entry — flush the previous.
                    if !parityRows.isEmpty { flushParityBlock() }
                    table = .productParityEquivalent
                    current = [:]
                    product.isActive = true
                    continue
                default:
                    break
                }
                // Anything else is a sibling — finalize the in-flight product.
                if product.isActive { flushProduct() }
                current = [:]
                switch line {
                case "[[product]]":
                    table = .product
                    product.isActive = true
                case "[limits_manifest]": table = .limitsManifest
                case "[review_notes.limits]": table = .reviewNoteLimits
                case "[market.limits]": table = .marketLimits
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
                product.fields[key] = value
            case .productPorts:
                portsRows[key] = value
            case .productParityEquivalent:
                parityRows[key] = value
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
            case .marketLimits:
                guard let n = value.int else { break }
                switch key {
                case "asc_promotional_text": config.marketLimits.ascPromotionalText = n
                case "asc_subtitle": config.marketLimits.ascSubtitle = n
                case "gp_short_description": config.marketLimits.gpShortDescription = n
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
            _ = current  // touched to keep the local around for parity with prior versions
        }
        // End of file: flush any in-flight ports/parity row buffers and the
        // current product, if any.
        if product.isActive { flushProduct() }
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

    /// An inline table of strings, e.g. `{ name = "ios", path = "../ios" }`.
    /// Tolerant: ignores unquoted keys, requires quoted string values. Used by
    /// the `[product.ports]` block to read the `a` and `b` port refs.
    var stringTable: [String: String]? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("{") && t.hasSuffix("}") else { return nil }
        let inner = t.dropFirst().dropLast()
        var table: [String: String] = [:]
        for pair in inner.split(separator: ",") {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let k = pair[..<eq].trimmingCharacters(in: .whitespaces)
            let v = TOMLValue(parsing: String(pair[pair.index(after: eq)...])).string
            if let v { table[k] = v }
        }
        return table
    }
}
