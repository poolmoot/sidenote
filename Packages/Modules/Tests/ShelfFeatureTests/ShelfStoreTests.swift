import Foundation
import Testing
import Persistence
@testable import ShelfFeature

@MainActor
final class ShelfStoreTests {
    private let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShelfStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(resolver: FakeBookmarkResolver = FakeBookmarkResolver()) -> ShelfStore {
        let fileStore = JSONFileStore<ShelfDocument>(url: directory.appendingPathComponent("shelf.json"))
        return ShelfStore(store: fileStore, resolver: resolver)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/ShelfStoreTests/\(name)")
    }

    @Test func addingReturnsTheNumberAdded() {
        let store = makeStore()
        let added = store.add(urls: [url("a.txt"), url("b.txt")])
        #expect(added == 2)
        #expect(store.items.count == 2)
    }

    @Test func duplicateDropsAcrossCallsAreIgnored() {
        let store = makeStore()
        #expect(store.add(urls: [url("a.txt")]) == 1)
        #expect(store.add(urls: [url("a.txt")]) == 0)
        #expect(store.items.count == 1)
    }

    @Test func duplicatesWithinOneDropAreIgnored() {
        let store = makeStore()
        let added = store.add(urls: [url("a.txt"), url("a.txt"), url("b.txt")])
        #expect(added == 2)
        #expect(store.items.count == 2)
    }

    @Test func removeDeletesJustTheGivenIDs() {
        let store = makeStore()
        store.add(urls: [url("a.txt"), url("b.txt")])
        let keepID = store.items.first { $0.displayName == "b.txt" }!.id
        let removeID = store.items.first { $0.displayName == "a.txt" }!.id
        store.remove([removeID])
        #expect(store.items.map(\.id) == [keepID])
    }

    @Test func clearRemovesEverything() {
        let store = makeStore()
        store.add(urls: [url("a.txt"), url("b.txt")])
        store.clear()
        #expect(store.items.isEmpty)
    }

    @Test func consumeRemovesLikeRemove() {
        let store = makeStore()
        store.add(urls: [url("a.txt")])
        let id = store.items[0].id
        store.consume([id])
        #expect(store.items.isEmpty)
    }

    @Test func itemThatCannotBeResolvedCountsAsMissing() {
        let resolver = FakeBookmarkResolver()
        let store = makeStore(resolver: resolver)
        store.add(urls: [url("a.txt")])
        let id = store.items[0].id
        #expect(!store.isMissing(id))

        resolver.breakBookmark(for: url("a.txt"))
        #expect(store.isMissing(id))
        #expect(store.url(for: id) == nil)
    }

    @Test func staleBookmarkIsRefreshedAndSaved() {
        let resolver = FakeBookmarkResolver()
        let fileURL = directory.appendingPathComponent("shelf.json")
        let fileStore = JSONFileStore<ShelfDocument>(url: fileURL)
        let store = ShelfStore(store: fileStore, resolver: resolver)
        store.add(urls: [url("a.txt")])
        let id = store.items[0].id
        let originalBookmark = store.items[0].bookmark

        resolver.markStale(url("a.txt"))
        _ = store.url(for: id)

        #expect(store.items[0].bookmark != originalBookmark)
        #expect(!store.isMissing(id))

        fileStore.flush()
        let persisted = JSONFileStore<ShelfDocument>(url: fileURL).load()
        #expect(persisted?.items.first?.bookmark == store.items[0].bookmark)
    }

    @Test func staleBookmarkIsAlsoRefreshedWhenReconstructedFromDisk() {
        let resolver = FakeBookmarkResolver()
        let fileURL = directory.appendingPathComponent("shelf.json")
        let firstFileStore = JSONFileStore<ShelfDocument>(url: fileURL)
        let store = ShelfStore(store: firstFileStore, resolver: resolver)
        store.add(urls: [url("a.txt")])
        let originalBookmark = store.items[0].bookmark
        firstFileStore.flush()

        resolver.markStale(url("a.txt"))

        let secondFileStore = JSONFileStore<ShelfDocument>(url: fileURL)
        let reloadedStore = ShelfStore(store: secondFileStore, resolver: resolver)
        #expect(reloadedStore.items[0].bookmark != originalBookmark)
    }

    @Test func itemsSurviveAReloadThroughJSONFileStore() {
        let resolver = FakeBookmarkResolver()
        let fileURL = directory.appendingPathComponent("shelf.json")
        let firstFileStore = JSONFileStore<ShelfDocument>(url: fileURL)
        let store = ShelfStore(store: firstFileStore, resolver: resolver)
        store.add(urls: [url("a.txt"), url("b.txt")])
        store.flush()

        let secondFileStore = JSONFileStore<ShelfDocument>(url: fileURL)
        let reloaded = ShelfStore(store: secondFileStore, resolver: resolver)
        #expect(reloaded.items.map(\.displayName).sorted() == ["a.txt", "b.txt"])
    }

    @Test func orderIsNewestFirst() {
        let store = makeStore()
        store.add(urls: [url("first.txt")])
        store.add(urls: [url("second.txt")])
        #expect(store.items.map(\.displayName) == ["second.txt", "first.txt"])
    }
}
