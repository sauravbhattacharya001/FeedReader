//
//  UserDefaultsCodableStoreTests.swift
//  FeedReaderTests
//
//  Tests for UserDefaultsCodableStore — the shared persistence helper
//  that eliminates duplicated JSONEncoder/JSONDecoder + UserDefaults
//  boilerplate across manager classes.
//

import XCTest
@testable import FeedReader

class UserDefaultsCodableStoreTests: XCTestCase {

    // Use a dedicated suite to avoid polluting the shared UserDefaults.
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "UserDefaultsCodableStoreTests")!
        testDefaults.removePersistentDomain(forName: "UserDefaultsCodableStoreTests")
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "UserDefaultsCodableStoreTests")
        super.tearDown()
    }

    // MARK: - Helpers

    /// A simple Codable struct for testing.
    struct Item: Codable, Equatable {
        let id: Int
        let name: String
    }

    /// A struct with a Date field.
    struct TimestampedItem: Codable, Equatable {
        let label: String
        let createdAt: Date
    }

    /// A nested struct for complex serialization.
    struct Nested: Codable, Equatable {
        let items: [Item]
        let count: Int
    }

    private func makeStore<T: Codable>(
        key: String = "test_key",
        dateStrategy: UserDefaultsCodableStore<T>.DateStrategy = .iso8601
    ) -> UserDefaultsCodableStore<T> {
        return UserDefaultsCodableStore<T>(
            key: key,
            dateStrategy: dateStrategy,
            defaults: testDefaults
        )
    }

    // MARK: - Basic Save/Load

    func testSaveAndLoadSingleItem() {
        let store: UserDefaultsCodableStore<Item> = makeStore()
        let item = Item(id: 1, name: "Widget")

        let saved = store.save(item)
        XCTAssertTrue(saved, "save should succeed")

        let loaded = store.load()
        XCTAssertEqual(loaded, item, "loaded item should match saved item")
    }

    func testSaveAndLoadArray() {
        let store: UserDefaultsCodableStore<[Item]> = makeStore()
        let items = [
            Item(id: 1, name: "Alpha"),
            Item(id: 2, name: "Beta"),
            Item(id: 3, name: "Gamma"),
        ]

        store.save(items)
        let loaded = store.load()
        XCTAssertEqual(loaded, items)
    }

    func testSaveAndLoadDictionary() {
        let store: UserDefaultsCodableStore<[String: Int]> = makeStore()
        let data = ["apples": 3, "bananas": 5, "cherries": 12]

        store.save(data)
        let loaded = store.load()
        XCTAssertEqual(loaded, data)
    }

    func testSaveAndLoadNested() {
        let store: UserDefaultsCodableStore<Nested> = makeStore()
        let nested = Nested(
            items: [Item(id: 10, name: "Deep")],
            count: 1
        )

        store.save(nested)
        let loaded = store.load()
        XCTAssertEqual(loaded, nested)
    }

    func testSaveAndLoadEmptyArray() {
        let store: UserDefaultsCodableStore<[Item]> = makeStore()
        store.save([])
        let loaded = store.load()
        XCTAssertEqual(loaded, [])
    }

    // MARK: - Load Missing Key

    func testLoadReturnsNilForMissingKey() {
        let store: UserDefaultsCodableStore<Item> = makeStore(key: "nonexistent")
        XCTAssertNil(store.load(), "load should return nil for missing key")
    }

    // MARK: - Overwrite

    func testSaveOverwritesPreviousValue() {
        let store: UserDefaultsCodableStore<Item> = makeStore()
        let first = Item(id: 1, name: "First")
        let second = Item(id: 2, name: "Second")

        store.save(first)
        store.save(second)

        let loaded = store.load()
        XCTAssertEqual(loaded, second, "should return the latest saved value")
    }

    // MARK: - Remove

    func testRemoveDeletesStoredValue() {
        let store: UserDefaultsCodableStore<Item> = makeStore()
        store.save(Item(id: 1, name: "temp"))

        store.remove()
        XCTAssertNil(store.load(), "load should return nil after remove")
    }

    func testRemoveOnMissingKeyIsNoOp() {
        let store: UserDefaultsCodableStore<Item> = makeStore(key: "never_written")
        store.remove()  // should not crash
        XCTAssertNil(store.load())
    }

    // MARK: - Exists

    func testExistsReturnsFalseForMissingKey() {
        let store: UserDefaultsCodableStore<Item> = makeStore(key: "missing")
        XCTAssertFalse(store.exists)
    }

    func testExistsReturnsTrueAfterSave() {
        let store: UserDefaultsCodableStore<Item> = makeStore()
        store.save(Item(id: 1, name: "present"))
        XCTAssertTrue(store.exists)
    }

    func testExistsReturnsFalseAfterRemove() {
        let store: UserDefaultsCodableStore<Item> = makeStore()
        store.save(Item(id: 1, name: "doomed"))
        store.remove()
        XCTAssertFalse(store.exists)
    }

    // MARK: - Date Strategy: ISO 8601

    func testISO8601DateRoundTrip() {
        let store: UserDefaultsCodableStore<TimestampedItem> = makeStore(
            dateStrategy: .iso8601
        )
        // Use a date with whole-second precision (ISO 8601 truncates sub-seconds)
        let date = Date(timeIntervalSince1970: 1700000000) // 2023-11-14T22:13:20Z
        let item = TimestampedItem(label: "iso", createdAt: date)

        store.save(item)
        let loaded = store.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.label, "iso")
        // ISO 8601 preserves whole seconds
        XCTAssertEqual(
            loaded?.createdAt.timeIntervalSince1970,
            date.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    // MARK: - Date Strategy: Deferred

    func testDeferredToDateRoundTrip() {
        let store: UserDefaultsCodableStore<TimestampedItem> = makeStore(
            dateStrategy: .deferredToDate
        )
        let date = Date(timeIntervalSince1970: 1700000000.123)
        let item = TimestampedItem(label: "deferred", createdAt: date)

        store.save(item)
        let loaded = store.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.label, "deferred")
        XCTAssertEqual(
            loaded?.createdAt.timeIntervalSince1970,
            date.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    // MARK: - Key Isolation

    func testDifferentKeysAreIsolated() {
        let storeA: UserDefaultsCodableStore<Item> = makeStore(key: "key_a")
        let storeB: UserDefaultsCodableStore<Item> = makeStore(key: "key_b")

        storeA.save(Item(id: 1, name: "A"))
        storeB.save(Item(id: 2, name: "B"))

        XCTAssertEqual(storeA.load()?.name, "A")
        XCTAssertEqual(storeB.load()?.name, "B")

        storeA.remove()
        XCTAssertNil(storeA.load())
        XCTAssertEqual(storeB.load()?.name, "B", "removing key_a should not affect key_b")
    }

    // MARK: - Type Mismatch

    func testLoadReturnsNilOnTypeMismatch() {
        // Save an Item, try to load as [Item]
        let itemStore: UserDefaultsCodableStore<Item> = makeStore(key: "mismatch")
        itemStore.save(Item(id: 1, name: "solo"))

        let arrayStore: UserDefaultsCodableStore<[Item]> = makeStore(key: "mismatch")
        XCTAssertNil(arrayStore.load(), "loading as wrong type should return nil, not crash")
    }

    // MARK: - Corrupt Data

    func testLoadReturnsNilOnCorruptData() {
        // Write raw garbage to the key
        testDefaults.set(Data([0xFF, 0xFE, 0x00, 0x01]), forKey: "corrupt")

        let store: UserDefaultsCodableStore<Item> = makeStore(key: "corrupt")
        XCTAssertNil(store.load(), "corrupt data should return nil, not crash")
    }

    // MARK: - Save Return Value

    func testSaveReturnsTrueOnSuccess() {
        let store: UserDefaultsCodableStore<Item> = makeStore()
        XCTAssertTrue(store.save(Item(id: 1, name: "ok")))
    }

    // MARK: - Large Collections

    func testSaveAndLoadLargeArray() {
        let store: UserDefaultsCodableStore<[Item]> = makeStore()
        let items = (0..<1000).map { Item(id: $0, name: "item_\($0)") }

        store.save(items)
        let loaded = store.load()
        XCTAssertEqual(loaded?.count, 1000)
        XCTAssertEqual(loaded?.first, items.first)
        XCTAssertEqual(loaded?.last, items.last)
    }

    // MARK: - Optional Values

    func testSaveAndLoadOptionalString() {
        let store: UserDefaultsCodableStore<String?> = makeStore()
        store.save(nil as String?)
        // nil encodes as JSON null, which decodes back to nil
        let loaded = store.load()
        XCTAssertNotNil(loaded, "Optional wrapper should exist")
    }

    // MARK: - Primitives

    func testSaveAndLoadInt() {
        let store: UserDefaultsCodableStore<Int> = makeStore()
        store.save(42)
        XCTAssertEqual(store.load(), 42)
    }

    func testSaveAndLoadString() {
        let store: UserDefaultsCodableStore<String> = makeStore()
        store.save("hello world")
        XCTAssertEqual(store.load(), "hello world")
    }

    func testSaveAndLoadBool() {
        let store: UserDefaultsCodableStore<Bool> = makeStore()
        store.save(true)
        XCTAssertEqual(store.load(), true)
    }

    // MARK: - Unicode / Special Characters

    func testSaveAndLoadUnicodeStrings() {
        let store: UserDefaultsCodableStore<Item> = makeStore()
        let item = Item(id: 1, name: "日本語テスト 🎉 émojis & ñ")

        store.save(item)
        let loaded = store.load()
        XCTAssertEqual(loaded, item)
    }

    // MARK: - Multiple Stores Same Defaults

    func testMultipleStoresSameDefaultsDifferentKeys() {
        let intStore: UserDefaultsCodableStore<Int> = makeStore(key: "int_key")
        let strStore: UserDefaultsCodableStore<String> = makeStore(key: "str_key")

        intStore.save(99)
        strStore.save("ninety-nine")

        XCTAssertEqual(intStore.load(), 99)
        XCTAssertEqual(strStore.load(), "ninety-nine")
    }
}
