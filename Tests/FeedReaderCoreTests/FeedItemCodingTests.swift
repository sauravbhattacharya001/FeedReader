//
//  FeedItemCodingTests.swift
//  FeedReaderCoreTests
//
//  Tests that exercise the under-covered surface of `FeedItem`:
//
//    1. `NSSecureCoding` round-trip via `NSKeyedArchiver` / Unarchiver.
//       The class declares `supportsSecureCoding` and ships explicit
//       `encode(with:)` / `init?(coder:)` overrides, but the existing
//       suite (in FeedReaderCoreTests.swift) only covers in-memory
//       construction. A bridging bug here (e.g. `String` → `NSString`
//       coercion regressing) would silently break persisted feed lists
//       across app upgrades.
//
//    2. Identifier / equality / hash invariants: identifier is the
//       lowercased URL, equality is identifier-based, and `hash` must
//       be consistent with equality (Hashable contract).
//
//    3. Preset feeds: must be unique by identifier, must all parse to
//       valid http(s) URLs (presets ship in the binary and the user
//       cannot edit them — a typo here is shipped).
//

import XCTest
@testable import FeedReaderCore

final class FeedItemCodingTests: XCTestCase {

    // MARK: - NSSecureCoding round-trip

    /// Archives a FeedItem with secure coding enabled and decodes it
    /// back. Returns nil if either step fails so individual tests can
    /// assert a meaningful failure message.
    private func archiveAndUnarchive(_ feed: FeedItem) -> FeedItem? {
        let data: Data
        do {
            data = try NSKeyedArchiver.archivedData(
                withRootObject: feed,
                requiringSecureCoding: true
            )
        } catch {
            XCTFail("Archiving failed: \(error)")
            return nil
        }

        do {
            let decoded = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: FeedItem.self,
                from: data
            )
            return decoded
        } catch {
            XCTFail("Unarchiving failed: \(error)")
            return nil
        }
    }

    func testSecureCodingRoundTripPreservesAllFields() {
        let original = FeedItem(
            name: "BBC World News",
            url: "https://feeds.bbci.co.uk/news/world/rss.xml",
            isEnabled: true
        )

        guard let decoded = archiveAndUnarchive(original) else { return }

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.url, original.url)
        XCTAssertEqual(decoded.isEnabled, original.isEnabled)
    }

    func testSecureCodingRoundTripPreservesDisabledFlag() {
        // The encode/decode path uses `decodeBool(forKey:)`, which
        // returns `false` when the key is missing. Make sure a value
        // that was explicitly archived as `false` reads back as `false`
        // (not because of a missing key, but because it really was
        // archived false).
        let original = FeedItem(
            name: "Disabled Feed",
            url: "https://example.com/feed.xml",
            isEnabled: false
        )

        guard let decoded = archiveAndUnarchive(original) else { return }
        XCTAssertFalse(decoded.isEnabled)
    }

    func testSecureCodingRoundTripPreservesUnicodeName() {
        // Many of the BBC / NPR / international presets use non-ASCII
        // names in localized lists. Verify NSString bridging keeps full
        // fidelity through the archiver pipeline.
        let original = FeedItem(
            name: "Café — Résumé — 日本語 🗞",
            url: "https://example.com/intl.xml",
            isEnabled: true
        )

        guard let decoded = archiveAndUnarchive(original) else { return }
        XCTAssertEqual(decoded.name, "Café — Résumé — 日本語 🗞")
        XCTAssertEqual(decoded.url, "https://example.com/intl.xml")
    }

    func testSecureCodingRoundTripPreservesEquality() {
        let original = FeedItem(
            name: "Round-trip Equality",
            url: "https://example.com/rss",
            isEnabled: true
        )
        guard let decoded = archiveAndUnarchive(original) else { return }
        // Equality is identifier-based — original and decoded share a URL.
        XCTAssertEqual(original, decoded)
        XCTAssertEqual(original.hash, decoded.hash)
    }

    func testSecureCodingProducesNonEmptyArchive() {
        // Sanity: a properly archived FeedItem should occupy more than
        // a trivial number of bytes. Catches the degenerate case where
        // archiving silently produces an empty/header-only blob.
        let feed = FeedItem(name: "Sanity", url: "https://example.com/x")
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: feed,
                requiringSecureCoding: true
            )
            XCTAssertGreaterThan(data.count, 32)
        } catch {
            XCTFail("Archiving failed: \(error)")
        }
    }

    // MARK: - Identifier semantics

    func testIdentifierIsCaseInsensitive() {
        let a = FeedItem(name: "A", url: "https://Example.COM/Feed")
        let b = FeedItem(name: "B", url: "https://example.com/feed")
        XCTAssertEqual(a.identifier, b.identifier)
    }

    func testIdentifierIsURLOnly_NotName() {
        // Two items with different names but the same URL must share
        // an identifier (and therefore an equality bucket).
        let a = FeedItem(name: "Display Alpha", url: "https://x.com/rss")
        let b = FeedItem(name: "Display Beta",  url: "https://x.com/rss")
        XCTAssertEqual(a.identifier, b.identifier)
    }

    func testIdentifierPreservesPathCase_AfterLowercase() {
        // Path components in the URL are lowercased as part of the
        // identifier, so any consumer using identifier as a dedup key
        // is treating `/A` and `/a` as the same feed. Pin this contract
        // so the behavior doesn't silently change.
        let feed = FeedItem(name: "Path", url: "https://x.com/A/B/C.xml")
        XCTAssertEqual(feed.identifier, "https://x.com/a/b/c.xml")
    }

    // MARK: - Equality / hash contract

    func testEqualityIsReflexive() {
        let feed = FeedItem(name: "R", url: "https://x.com/feed")
        XCTAssertEqual(feed, feed)
    }

    func testEqualityIsSymmetric() {
        let a = FeedItem(name: "A", url: "https://x.com/feed")
        let b = FeedItem(name: "B", url: "HTTPS://X.COM/FEED")
        XCTAssertEqual(a, b)
        XCTAssertEqual(b, a)
    }

    func testEqualHashesForEqualItems() {
        // Hashable contract: a == b ⇒ a.hashValue == b.hashValue.
        let a = FeedItem(name: "A", url: "https://x.com/feed")
        let b = FeedItem(name: "B", url: "https://X.com/Feed") // case differs
        XCTAssertEqual(a, b, "Precondition: items must be equal")
        XCTAssertEqual(a.hash, b.hash)
    }

    func testNotEqualToDifferentType() {
        let feed = FeedItem(name: "F", url: "https://x.com/feed")
        // NSObject.isEqual(_:) on a non-FeedItem must return false,
        // never crash.
        XCTAssertFalse(feed.isEqual("https://x.com/feed"))
        XCTAssertFalse(feed.isEqual(NSObject()))
        XCTAssertFalse(feed.isEqual(nil))
    }

    func testNotEqualForDifferentURLs() {
        let a = FeedItem(name: "Same Name", url: "https://x.com/one")
        let b = FeedItem(name: "Same Name", url: "https://x.com/two")
        XCTAssertNotEqual(a, b)
    }

    func testEqualItemsDedupeInNSSet() {
        // A practical consequence of the equality + hash contract:
        // duplicate-URL items collapse when added to an NSSet, which
        // is used by some of the FeedReader managers.
        let a = FeedItem(name: "A", url: "https://x.com/feed")
        let b = FeedItem(name: "B", url: "https://X.COM/Feed")
        let set = NSSet(array: [a, b])
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - Presets

    func testPresetsHaveUniqueIdentifiers() {
        // Shipping two presets with the same URL would cause confusing
        // dedup behavior in the subscriptions UI.
        let identifiers = FeedItem.presets.map { $0.identifier }
        XCTAssertEqual(
            identifiers.count,
            Set(identifiers).count,
            "Preset identifiers must be unique; duplicates: " +
            "\(Dictionary(grouping: identifiers, by: { $0 }).filter { $0.value.count > 1 }.keys)"
        )
    }

    func testPresetsHaveNonEmptyNames() {
        for preset in FeedItem.presets {
            XCTAssertFalse(
                preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Preset has empty display name: \(preset.url)"
            )
        }
    }

    func testPresetsHaveHTTPOrHTTPSURLs() {
        // Defense in depth — these URLs are baked into the binary, so a
        // typo (`htps://`, `ftp://`, etc.) would survive code review
        // unnoticed until a user tried to subscribe.
        for preset in FeedItem.presets {
            let scheme = URL(string: preset.url)?.scheme?.lowercased()
            XCTAssertTrue(
                scheme == "https" || scheme == "http",
                "Preset URL has invalid scheme: \(preset.url)"
            )
        }
    }

    func testPresetsParseAsValidURLs() {
        for preset in FeedItem.presets {
            let url = URL(string: preset.url)
            XCTAssertNotNil(url, "Preset URL is unparseable: \(preset.url)")
            XCTAssertNotNil(url?.host, "Preset URL has no host: \(preset.url)")
        }
    }

    func testPresetsAllowedFirstEntryEnabled() {
        // The first preset (BBC World News) is intentionally created
        // with `isEnabled: true` so a fresh install has at least one
        // active feed. Lock that behavior so a future refactor doesn't
        // silently flip it.
        guard let first = FeedItem.presets.first else {
            XCTFail("Presets array is empty")
            return
        }
        XCTAssertTrue(first.isEnabled, "First preset should be enabled by default")
    }
}
