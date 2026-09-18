import Foundation

// Decoding helpers every hand-written model in this app needs to read a
// PostgREST row — the closest iOS has to the web's generated
// `database.types.ts`. They live in `Runtime/` because the runtime module owns
// the contract (`docs/architecture/architecture.md`), so both `Games/` and
// `Platform/` can depend on them without depending on each other.

/// Postgres `timestamptz` as PostgREST prints it: `2026-08-15T12:00:00.123456+00:00`
/// — microsecond fractions, sometimes none, `+00:00` or `Z`. Kept as its own
/// parser so nothing depends on a Foundation formatter's tolerance for more
/// than three fractional digits.
enum PostgresTimestamp {
    struct Malformed: Error { let value: String }

    static func parse(_ value: String) throws -> Date {
        // Foundation's fractional-seconds parser is dependable at millisecond
        // precision; trim anything beyond it.
        let trimmed = value.replacingOccurrences(
            of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression
        )
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: trimmed) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: trimmed) { return date }
        throw Malformed(value: value)
    }
}

extension KeyedDecodingContainer {
    /// Postgres `numeric` arrives as a JSON number from PostgREST, but as a
    /// string from some paths (the web's `formatPoints` accepts both) — take
    /// either.
    func decodeNumericIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let number = try? decode(Double.self, forKey: key) { return number }
        let text = try decode(String.self, forKey: key)
        guard let number = Double(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not a number: \(text)")
        }
        return number
    }

    /// A `timestamptz` column, or `nil` when the row carries none.
    func decodeTimestampIfPresent(forKey key: Key) throws -> Date? {
        try decodeIfPresent(String.self, forKey: key).map { try PostgresTimestamp.parse($0) }
    }
}
