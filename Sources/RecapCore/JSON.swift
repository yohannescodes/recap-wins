import Foundation

public extension ChangeReport {
    /// Canonical JSON encoder for `change_report.json`: stable key order,
    /// ISO-8601 dates, pretty-printed for human inspection.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Encode this report to pretty JSON.
    func jsonData() throws -> Data {
        try Self.makeEncoder().encode(self)
    }

    /// Encode this report to a UTF-8 JSON string.
    func jsonString() throws -> String {
        String(decoding: try jsonData(), as: UTF8.self)
    }
}
