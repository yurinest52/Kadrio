import XCTest
@testable import Kadrio

final class KadrioWorksAndTokensTests: XCTestCase {
    private var directory: URL!
    private var storage: KadrioWorksStorage!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("KadrioTests-\(UUID())")
        storage = KadrioWorksStorage(directory: directory)
    }

    override func tearDown() async throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func stage(_ byte: UInt8 = 1) async throws -> KadrioWork {
        let original = FileManager.default.temporaryDirectory.appendingPathComponent("KadrioTestPhoto-\(UUID()).jpg")
        let thumbnail = FileManager.default.temporaryDirectory.appendingPathComponent("KadrioTestThumb-\(UUID()).jpg")
        try Data([byte, 2, 3, 4]).write(to: original)
        try Data([byte, 2]).write(to: thumbnail)
        defer { try? FileManager.default.removeItem(at: original); try? FileManager.default.removeItem(at: thumbnail) }
        return try await storage.stage(exportURL: original, thumbnailURL: thumbnail, tool: .filters)
    }

    func testInitialBalanceAndEmptyHistory() async throws {
        let value = try await storage.load()
        XCTAssertEqual(value.tokens, 3)
        XCTAssertTrue(value.works.isEmpty)
    }

    func testExactlyThreeSavesAndNoNegativeBalance() async throws {
        for remaining in stride(from: 2, through: 0, by: -1) {
            let work = try await stage()
            let result = try await storage.commit(work)
            XCTAssertEqual(result.tokens, remaining)
        }
        do { _ = try await stage(); XCTFail("A fourth save must require tokens") }
        catch { XCTAssertEqual(error as? KadrioError, .noTokens) }
        let loaded = try await storage.load()
        XCTAssertEqual(loaded.tokens, 0)
        XCTAssertEqual(loaded.works.count, 3)
    }

    func testCommitIsIdempotent() async throws {
        let work = try await stage()
        _ = try await storage.commit(work)
        let repeated = try await storage.commit(work)
        XCTAssertEqual(repeated.tokens, 2)
        XCTAssertEqual(repeated.works.count, 1)
    }

    func testCancelledSaveDoesNotSpendTokensOrAddWork() async throws {
        let work = try await stage()
        await storage.discard(work)
        let value = try await storage.load()
        XCTAssertEqual(value.tokens, 3)
        XCTAssertTrue(value.works.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(work.fileName).path))
    }

    func testMissingFileCannotConsumeToken() async throws {
        let work = try await stage()
        await storage.discard(work)
        do { _ = try await storage.commit(work); XCTFail("Missing file must fail") } catch {}
        let loaded = try await storage.load()
        XCTAssertEqual(loaded.tokens, 3)
    }

    func testPersistenceAndNewestFirst() async throws {
        let first = try await stage(1)
        _ = try await storage.commit(first)
        let second = try await stage(2)
        _ = try await storage.commit(second)
        let restored = try await KadrioWorksStorage(directory: directory).load()
        XCTAssertEqual(restored.works, [second, first])
        XCTAssertEqual(restored.tokens, 1)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(second.fileName)), Data([2, 2, 3, 4]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(first.thumbnailName).path))
    }

    func testDeletePersistsAndDoesNotRefund() async throws {
        let work = try await stage()
        _ = try await storage.commit(work)
        let deleted = try await storage.delete(work)
        XCTAssertEqual(deleted.tokens, 2)
        XCTAssertTrue(deleted.works.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(work.fileName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(work.thumbnailName).path))
        let restored = try await KadrioWorksStorage(directory: directory).load()
        XCTAssertEqual(restored, deleted)
    }

    func testClearResetsBalanceAndDeletesFiles() async throws {
        let work = try await stage()
        _ = try await storage.commit(work)
        _ = try await storage.topUp()
        let cleared = try await storage.clear()
        XCTAssertEqual(cleared, KadrioLedger())
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, ["KadrioWorksLedger.json"])
        let restored = try await KadrioWorksStorage(directory: directory).load()
        XCTAssertEqual(restored, cleared)
    }

    func testDemoTopUpPersists() async throws {
        let topped = try await storage.topUp()
        XCTAssertEqual(topped.tokens, 6)
        let restored = try await KadrioWorksStorage(directory: directory).load()
        XCTAssertEqual(restored.tokens, 6)
    }

    func testTopUpAlwaysAddsExactlyThree() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(KadrioLedger(tokens: 999)).write(to: directory.appendingPathComponent("KadrioWorksLedger.json"))
        let result = try await storage.topUp()
        XCTAssertEqual(result.tokens, 1002)
    }

    @MainActor func testEverySaveAtZeroBalancePresentsPaywallWithoutSpending() async throws {
        for _ in 0..<3 {
            let work = try await stage()
            _ = try await storage.commit(work)
        }
        let app = KadrioAppState(storage: storage)
        await app.initialize()
        for _ in 0..<2 {
            app.showPaywall = false
            let result = await app.save(sources: [], state: KadrioEditState(), tool: .filters)
            XCTAssertNil(result)
            XCTAssertTrue(app.showPaywall)
            XCTAssertEqual(app.ledger.tokens, 0)
            XCTAssertEqual(app.ledger.works.count, 3)
            XCTAssertFalse(app.saving)
        }
        await app.initialize()
        XCTAssertEqual(app.ledger.tokens, 0)
    }

    @MainActor func testPaywallTopUpPersistsThreeTokensAndDismisses() async throws {
        let app = KadrioAppState(storage: storage)
        await app.initialize()
        app.showPaywall = true
        let result = await app.replenish()
        XCTAssertTrue(result)
        XCTAssertFalse(app.showPaywall)
        XCTAssertEqual(app.ledger.tokens, 6)
        let restored = try await KadrioWorksStorage(directory: directory).load()
        XCTAssertEqual(restored.tokens, 6)
    }

    func testCorruptLedgerIsNeverSilentlyReset() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: directory.appendingPathComponent("KadrioWorksLedger.json"))
        do { _ = try await storage.load(); XCTFail("Corruption must be reported") } catch {}
    }

    func testWriteFailureKeepsPreviousBalance() async throws {
        _ = try await storage.load()
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("KadrioWorksLedger.json"), withIntermediateDirectories: true)
        do { _ = try await storage.topUp(); XCTFail("Write must fail") } catch {}
        let value = try await storage.load()
        XCTAssertEqual(value.tokens, 3)
    }
}
