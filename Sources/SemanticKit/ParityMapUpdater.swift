import Foundation

/// Appends `[[product.parity.equivalent]]` blocks to a `testthese.toml` so
/// confirmed equivalences (FRD §6 `--confirm`) stop showing up as gaps or
/// ambiguous items on the next align run.
///
/// Intentionally narrow scope: we *append* to the file (preserving comments
/// and whitespace) rather than re-serializing the whole TOML. Re-serialization
/// would require a full TOML library and would smash the human formatting
/// users carefully maintain; appending keeps it boring and safe.
public enum ParityMapUpdater {
    /// Result of an append attempt — so the CLI can report meaningfully.
    public enum Outcome: Sendable, Equatable {
        /// Block written. The file now contains a new equivalence entry.
        case appended
        /// The exact (a, b) pair was already present; nothing changed.
        case alreadyPresent
    }

    /// Append a `[[product.parity.equivalent]]` entry for `productId` to
    /// `configPath`. Idempotent on the (a, b) tuple (case-insensitive).
    ///
    /// - Throws: file IO errors and `ParityMapError` for shape problems
    ///   (e.g. config doesn't define the product yet).
    public static func append(
        a: String, b: String, note: String?,
        productId: String, configPath: String
    ) throws -> Outcome {
        let original: String
        if FileManager.default.fileExists(atPath: configPath) {
            original = try String(contentsOfFile: configPath, encoding: .utf8)
        } else {
            // No config yet — we'd need to invent the [[product]] header,
            // and the user almost certainly wants to write it themselves.
            throw ParityMapError.configMissing(path: configPath)
        }

        // The product must already exist in config — confirming equivalences
        // for a product `rw` doesn't know about would be wrong silently.
        let config = try Config.parse(original)
        guard let product = config.product(productId) else {
            throw ParityMapError.productNotInConfig(id: productId)
        }

        // Idempotency: skip if the pair is already there (any direction,
        // any case). This makes re-runs after confirming all matches a
        // no-op, which is the "running the same script twice should be
        // safe" rule users rely on.
        let normA = a.lowercased()
        let normB = b.lowercased()
        for entry in product.parityEquivalent {
            if entry.a.lowercased() == normA && entry.b.lowercased() == normB {
                return .alreadyPresent
            }
        }

        // Build the block. We attach a trailing comment so a future reader
        // can tell at a glance which entries came from --confirm vs. were
        // hand-curated.
        var block = "\n"
        block += "[[product.parity.equivalent]]\n"
        block += "a = \"\(escapeTOML(a))\"\n"
        block += "b = \"\(escapeTOML(b))\"\n"
        if let note, !note.isEmpty {
            block += "note = \"\(escapeTOML(note))\"\n"
        }
        block += "# added by `rw align --confirm`\n"

        let updated = original.hasSuffix("\n") ? original + block : original + "\n" + block
        try updated.write(toFile: configPath, atomically: true, encoding: .utf8)
        return .appended
    }

    /// TOML strings are quoted; backslashes and quotes need escaping. Our
    /// parser is hand-rolled and doesn't support multiline literals, so we
    /// also collapse interior newlines to spaces — the matcher never returns
    /// multi-line equivalences anyway, but better safe than malformed TOML.
    private static func escapeTOML(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

/// Errors specific to the parity-map writer.
public enum ParityMapError: Error, CustomStringConvertible, Equatable {
    /// The config file doesn't exist yet — confirming an equivalence is a
    /// no-op without one. The user should `cp testthese.toml.example
    /// testthese.toml` first.
    case configMissing(path: String)
    /// The product id isn't in the config. Confirming for a product `rw`
    /// can't see would create dangling state.
    case productNotInConfig(id: String)

    public var description: String {
        switch self {
        case let .configMissing(path):
            return "No testthese.toml at \(path). Copy testthese.toml.example "
                + "to testthese.toml and configure the product first."
        case let .productNotInConfig(id):
            return "Product '\(id)' isn't in testthese.toml. Add a [[product]] "
                + "block for it before confirming equivalences."
        }
    }
}
