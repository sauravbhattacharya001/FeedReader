//
//  UserDefaultsCodableStore.swift
//  FeedReader
//
//  Reusable persistence helper that eliminates the duplicated
//  JSONEncoder/JSONDecoder + UserDefaults boilerplate found across
//  16+ manager classes. Each manager used an identical save/load
//  pattern; this struct centralizes it with consistent date strategy
//  handling and error reporting.
//

import Foundation

/// A lightweight wrapper for persisting `Codable` values in `UserDefaults`.
///
/// Usage:
/// ```swift
/// private let store = UserDefaultsCodableStore<[ReadingChallenge]>(
///     key: "reading_challenges",
///     dateStrategy: .iso8601
/// )
///
/// // Save
/// store.save(challenges)
///
/// // Load
/// if let loaded = store.load() { challenges = loaded }
/// ```
struct UserDefaultsCodableStore<T: Codable> {

    /// Which `JSONEncoder.DateEncodingStrategy` / `JSONDecoder.DateDecodingStrategy` to use.
    enum DateStrategy {
        /// Encode/decode dates as ISO-8601 strings (`yyyy-MM-dd'T'HH:mm:ssZ`).
        case iso8601
        /// Use Foundation's default (double since reference date).
        case deferredToDate
    }

    /// The `UserDefaults` key under which data is stored.
    let key: String

    /// Date encoding/decoding strategy (default: `.iso8601`).
    let dateStrategy: DateStrategy

    /// The `UserDefaults` instance to use (default: `.standard`).
    let defaults: UserDefaults

    init(key: String,
         dateStrategy: DateStrategy = .iso8601,
         defaults: UserDefaults = .standard) {
        self.key = key
        self.dateStrategy = dateStrategy
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Encode `value` and write it to `UserDefaults`.
    /// Returns `true` on success.
    @discardableResult
    func save(_ value: T) -> Bool {
        let encoder = JSONEncoder()
        applyDateEncoding(encoder)
        guard let data = try? encoder.encode(value) else { return false }
        defaults.set(data, forKey: key)
        return true
    }

    /// Read and decode the stored value. Returns `nil` if the key is
    /// missing or the data cannot be decoded.
    func load() -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        applyDateDecoding(decoder)
        return try? decoder.decode(T.self, from: data)
    }

    /// Remove the stored value entirely.
    func remove() {
        defaults.removeObject(forKey: key)
    }

    /// Check whether a value is stored for this key.
    var exists: Bool {
        return defaults.data(forKey: key) != nil
    }

    // MARK: - Private

    private func applyDateEncoding(_ encoder: JSONEncoder) {
        switch dateStrategy {
        case .iso8601:
            encoder.dateEncodingStrategy = .iso8601
        case .deferredToDate:
            break  // Foundation default
        }
    }

    private func applyDateDecoding(_ decoder: JSONDecoder) {
        switch dateStrategy {
        case .iso8601:
            decoder.dateDecodingStrategy = .iso8601
        case .deferredToDate:
            break  // Foundation default
        }
    }
}
