import Foundation
import Testing
@testable import Persistence

private struct Fixture: Codable, Equatable {
    var name: String
    var count: Int
}

@MainActor
final class JSONFileStoreTests {
    private let directory: URL
    private let fileURL: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("fixture.json")
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(debounce: Duration = .milliseconds(500)) -> JSONFileStore<Fixture> {
        JSONFileStore(url: fileURL, debounceInterval: debounce)
    }

    @Test func writesAndReadsBackTheSameValue() {
        let store = makeStore()
        let value = Fixture(name: "shelf", count: 3)
        store.save(value)
        store.flush()

        let reloaded = makeStore().load()
        #expect(reloaded == value)
    }

    @Test func missingFileLoadsAsNil() {
        #expect(makeStore().load() == nil)
    }

    @Test func corruptFileIsQuarantinedAndLoadsAsNil() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        let loaded = makeStore().load()
        #expect(loaded == nil)

        let siblings = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(siblings.contains { $0.hasPrefix("fixture.corrupt-") && $0.hasSuffix(".json") })
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func severalSavesFollowedByFlushWriteOnlyTheLastValue() {
        let store = makeStore(debounce: .seconds(30))
        store.save(Fixture(name: "first", count: 1))
        store.save(Fixture(name: "second", count: 2))
        store.save(Fixture(name: "third", count: 3))
        store.flush()

        let reloaded = makeStore().load()
        #expect(reloaded == Fixture(name: "third", count: 3))
    }

    @Test func savingIntoAMissingDirectoryCreatesIt() {
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let store = makeStore()
        store.save(Fixture(name: "new", count: 0))
        store.flush()
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    /// Every other test drives the write through `flush()`. This one lets the debounce actually
    /// fire on its own background queue, so the async write path itself is exercised, not just
    /// the synchronous flush path.
    @Test func debouncedWriteFiresOnceOnItsOwnAfterTheInterval() async throws {
        let store = makeStore(debounce: .milliseconds(20))
        store.save(Fixture(name: "first", count: 1))
        store.save(Fixture(name: "second", count: 2))
        store.save(Fixture(name: "third", count: 3))

        try await Task.sleep(for: .milliseconds(200))

        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(Fixture.self, from: data)
        #expect(decoded == Fixture(name: "third", count: 3))
    }
}
