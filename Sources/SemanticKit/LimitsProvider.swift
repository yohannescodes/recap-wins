import Foundation

/// Resolves the effective `ReviewNoteLimits`, fetching the published manifest
/// and caching it with a TTL (PRD §6.1). Falls back to the baked-in config
/// values when the manifest is unreachable, stale, or no URL is configured —
/// so the cap system degrades gracefully offline.
public struct LimitsProvider: Sendable {
    public let config: Config
    public let cacheURL: URL
    private let session: URLSession

    /// - Parameter cacheDirectory: where to persist the fetched manifest. Defaults
    ///   to a per-repo cache under the system caches directory.
    public init(config: Config, cacheDirectory: URL? = nil, session: URLSession = .shared) {
        self.config = config
        self.session = session
        let dir = cacheDirectory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("recap-wins", isDirectory: true)
        self.cacheURL = dir.appendingPathComponent("limits.json")
    }

    /// The effective ceilings. `forceRefresh` (from `--refresh-limits`) bypasses
    /// the TTL and refetches now.
    public func limits(forceRefresh: Bool = false) async -> ReviewNoteLimits {
        // No manifest configured → baked-in fallback.
        guard let urlString = config.limitsManifestURL,
              let url = URL(string: urlString) else {
            return config.reviewNoteLimits
        }

        // Use a fresh-enough cache unless forced.
        if !forceRefresh, let cached = loadCache(), !isStale(cached.fetchedAt) {
            return cached.manifest.reviewNoteLimits
        }

        // Try to fetch; on any failure fall back to cache (even if stale), then config.
        if let fetched = await fetch(url) {
            saveCache(CachedManifest(manifest: fetched, fetchedAt: Date()))
            return fetched.reviewNoteLimits
        }
        if let cached = loadCache() {
            return cached.manifest.reviewNoteLimits
        }
        return config.reviewNoteLimits
    }

    // MARK: - Fetch

    private func fetch(_ url: URL) async -> LimitsManifest? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(LimitsManifest.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Cache

    struct CachedManifest: Codable {
        var manifest: LimitsManifest
        var fetchedAt: Date
    }

    func loadCache() -> CachedManifest? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CachedManifest.self, from: data)
    }

    private func saveCache(_ cached: CachedManifest) {
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cached) {
            try? data.write(to: cacheURL)
        }
    }

    /// True if a cache fetched at `fetchedAt` is older than the configured TTL.
    func isStale(_ fetchedAt: Date) -> Bool {
        let ttl = Self.parseTTL(config.limitsManifestTTL) ?? Self.defaultTTL
        return Date().timeIntervalSince(fetchedAt) > ttl
    }

    /// Default TTL when none is configured: 30 days (PRD §8 example).
    static let defaultTTL: TimeInterval = 30 * 24 * 60 * 60

    /// Parse a duration like "30d", "12h", "45m", "90s" into seconds.
    static func parseTTL(_ string: String?) -> TimeInterval? {
        guard let s = string?.trimmingCharacters(in: .whitespaces), let unit = s.last else { return nil }
        guard let value = Double(s.dropLast()) else { return nil }
        switch unit {
        case "d": return value * 24 * 60 * 60
        case "h": return value * 60 * 60
        case "m": return value * 60
        case "s": return value
        default: return nil
        }
    }
}
