import Foundation

/// The built-in Apple↔Google parity table the matcher uses as its starting
/// floor (FRD §6). These are platform-native substitutes that count as parity
/// *achieved*, not gaps — Apple Pay is the Apple-platform equivalent of
/// Google Pay, not a missing feature on Android.
///
/// Per-product `[[product.parity.equivalent]]` entries from config (FRD §8)
/// extend this table at match time; nothing here is hard-coded into the
/// matcher's classification — it's a hint the model trusts heavily but can
/// still mark `ambiguous` when the surrounding context contradicts.
///
/// Side `a` is conventionally the Apple side, side `b` the Google side. The
/// matcher checks both directions so the table works regardless of which port
/// is configured as A or B.
public enum EquivalenceTable {
    /// The canonical pairs that ship with `rw`. Curated, intentionally narrow:
    /// only platform-native substitutes whose equivalence is unambiguous. App
    /// vendors layer their own confirmed equivalences on top via config.
    public static let appleGoogle: [ParityEntry] = [
        ParityEntry(a: "Apple Pay",            b: "Google Pay",
                    note: "platform-native payment"),
        ParityEntry(a: "Sign in with Apple",   b: "Google Sign-In",
                    note: "platform-native auth provider"),
        ParityEntry(a: "StoreKit",             b: "Play Billing",
                    note: "platform-native in-app purchases / subscriptions"),
        ParityEntry(a: "Keychain",             b: "Keystore",
                    note: "platform-native secure credential storage"),
        ParityEntry(a: "HealthKit",            b: "Health Connect",
                    note: "platform-native health-data integration"),
        ParityEntry(a: "APNs",                 b: "FCM",
                    note: "platform-native push notifications"),
        ParityEntry(a: "iCloud",               b: "Google Drive",
                    note: "platform-native cloud storage"),
        ParityEntry(a: "WidgetKit",            b: "Glance",
                    note: "platform-native home-screen widgets"),
        ParityEntry(a: "SwiftUI",              b: "Jetpack Compose",
                    note: "platform-native declarative UI framework"),
        ParityEntry(a: "Core Data",            b: "Room",
                    note: "platform-native persistence layer"),
        ParityEntry(a: "Combine",              b: "Kotlin Flow",
                    note: "platform-native reactive streams"),
        ParityEntry(a: "TestFlight",           b: "Play Internal Testing",
                    note: "platform-native beta distribution"),
    ]

    /// Merge the built-in pairs with per-product curated entries, preferring
    /// the product's note if both define the same pair (the product's wording
    /// usually has more context). De-duplication is case-insensitive on
    /// the (a, b) tuple — small typos shouldn't create phantom duplicates.
    public static func merged(with productEntries: [ParityEntry]) -> [ParityEntry] {
        var seen = Set<String>()
        var merged: [ParityEntry] = []
        for entry in productEntries + appleGoogle {
            let key = "\(entry.a.lowercased())|\(entry.b.lowercased())"
            if seen.contains(key) { continue }
            seen.insert(key)
            merged.append(entry)
        }
        return merged
    }
}
