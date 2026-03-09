import Foundation

/// Shared, pre-configured `JSONEncoder` and `JSONDecoder` instances.
///
/// `JSONEncoder.encode()` and `JSONDecoder.decode()` are safe to call
/// from any thread because each call creates its own internal state.
/// The top-level encoder/decoder objects are stateless after initial
/// configuration, so sharing them avoids redundant allocations.
enum JSONCoding {

    // MARK: - ISO 8601 Date Strategy

    /// Encoder with ISO 8601 dates, pretty-printed with sorted keys.
    ///
    /// Equivalent to:
    /// ```swift
    /// let encoder = JSONEncoder()
    /// encoder.dateEncodingStrategy = .iso8601
    /// encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    /// ```
    static let iso8601PrettyEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// Encoder with ISO 8601 dates, pretty-printed (no sorted keys).
    static let iso8601PrettyUnsortedEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()

    /// Encoder with ISO 8601 dates, compact output.
    static let iso8601Encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Decoder with ISO 8601 date strategy.
    static let iso8601Decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Epoch (Seconds Since 1970) Date Strategy

    /// Encoder with epoch dates, pretty-printed with sorted keys.
    static let epochPrettyEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// Encoder with epoch dates, compact output.
    static let epochEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    /// Decoder with epoch date strategy.
    static let epochDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}
