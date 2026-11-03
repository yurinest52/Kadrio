import Foundation

actor KadrioWorksStorage {
    struct PendingSave: Codable, Sendable {
        enum Stage: String, Codable, Sendable {
            case prepared, savingToPhotos, photosConfirmed, committed
        }

        let work: KadrioWork
        let state: KadrioEditState
        let sourceIDs: [UUID]
        var stage: Stage
        var photoIdentifier: String?

        init(work: KadrioWork, state: KadrioEditState, sourceIDs: [UUID]) {
            self.work = work
            self.state = state
            self.sourceIDs = sourceIDs
            stage = .prepared
        }

        private enum CodingKeys: String, CodingKey {
            case work, state, sourceIDs, stage, photoIdentifier
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            work = try values.decode(KadrioWork.self, forKey: .work)
            state = try values.decode(KadrioEditState.self, forKey: .state)
            sourceIDs = try values.decode([UUID].self, forKey: .sourceIDs)
            stage = try values.decodeIfPresent(Stage.self, forKey: .stage) ?? .photosConfirmed
            photoIdentifier = try values.decodeIfPresent(String.self, forKey: .photoIdentifier)
        }
    }
    nonisolated let directory: URL
    private var ledger: KadrioLedger?
    private var ledgerURL: URL { directory.appendingPathComponent("KadrioWorksLedger.json") }
    private var pendingURL: URL { directory.appendingPathComponent("KadrioPendingSave.json") }

    func pendingSave() throws -> PendingSave? {
        do {
            return try JSONDecoder().decode(PendingSave.self, from: Data(contentsOf: pendingURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    func validatePendingFiles(_ pending: PendingSave) throws {
        for name in [pending.work.fileName, pending.work.thumbnailName] {
            guard FileManager.default.isReadableFile(atPath: directory.appendingPathComponent(name).path) else {
                throw KadrioError.pendingFilesMissing
            }
        }
    }

    func recordPendingSave(_ pending: PendingSave) throws {
        if let existing = try pendingSave(), existing.work.id != pending.work.id { throw KadrioError.storage }
        try Self.writePendingSave(pending, to: pendingURL)
    }

    private nonisolated static func writePendingSave(_ pending: PendingSave, to url: URL) throws {
        try JSONEncoder().encode(pending).write(to: url, options: .atomic)
    }

    func photoIdentifierRecorder(for pending: PendingSave) -> @Sendable (String) -> Void {
        let url = pendingURL
        return { identifier in
            var identified = pending
            identified.photoIdentifier = identifier
            try? Self.writePendingSave(identified, to: url)
        }
    }

    func cancelPreparedSave(_ pending: PendingSave) throws {
        guard let existing = try pendingSave(), existing.work.id == pending.work.id,
              existing.stage == .prepared else { throw KadrioError.saveUncertain }
        try FileManager.default.removeItem(at: pendingURL)
        discard(existing.work)
    }

    func finishPendingSave(_ pending: PendingSave) throws -> KadrioLedger {
        guard pending.stage == .photosConfirmed || pending.stage == .committed else { throw KadrioError.saveUncertain }
        try recordPendingSave(pending)
        let value = try commit(pending.work)
        var completed = pending
        completed.stage = .committed
        do {
            try recordPendingSave(completed)
            try FileManager.default.removeItem(at: pendingURL)
        } catch {}
        return value
    }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("KadrioWorks", isDirectory: true)
    }

    func load() throws -> KadrioLedger {
        if let ledger { return ledger }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let value: KadrioLedger
        do {
            value = try JSONDecoder().decode(KadrioLedger.self, from: Data(contentsOf: ledgerURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            guard try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).isEmpty else {
                throw KadrioError.storage
            }
            value = KadrioLedger()
            try write(value)
        }
        guard value.tokens >= 0 else { throw KadrioError.storage }
        ledger = value
        do {
            let pending = try pendingSave()
            if let pending { try validatePendingFiles(pending) }
            let retained = Set(value.works.flatMap { [$0.fileName, $0.thumbnailName] }
                + (pending.map { [$0.work.fileName, $0.work.thumbnailName] } ?? [])
                + [ledgerURL.lastPathComponent, pendingURL.lastPathComponent])
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where !retained.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {}
        return value
    }

    private func write(_ value: KadrioLedger) throws {
        try JSONEncoder().encode(value).write(to: ledgerURL, options: .atomic)
        ledger = value
    }

    func topUp() throws -> KadrioLedger {
        var value = try load()
        guard value.tokens <= Int.max - 3 else { throw KadrioError.storage }
        value.tokens += 3
        try write(value)
        return value
    }

    func stage(exportURL: URL, thumbnailURL: URL, tool: KadrioTool) throws -> KadrioWork {
        let value = try load()
        guard try pendingSave() == nil else { throw KadrioError.saveUncertain }
        guard value.tokens > 0 else { throw KadrioError.noTokens }
        let id = UUID()
        let work = KadrioWork(id: id, fileName: "KadrioWork-\(id).jpg", thumbnailName: "KadrioThumbnail-\(id).jpg", createdAt: Date(), tool: tool)
        do {
            try FileManager.default.copyItem(at: exportURL, to: directory.appendingPathComponent(work.fileName))
            try FileManager.default.copyItem(at: thumbnailURL, to: directory.appendingPathComponent(work.thumbnailName))
        } catch {
            discard(work)
            throw error
        }
        return work
    }

    func commit(_ work: KadrioWork) throws -> KadrioLedger {
        var value = try load()
        guard !value.works.contains(where: { $0.id == work.id }) else { return value }
        guard value.tokens > 0 else { throw KadrioError.noTokens }
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(work.fileName).path), FileManager.default.fileExists(atPath: directory.appendingPathComponent(work.thumbnailName).path) else { throw KadrioError.storage }
        value.tokens -= 1
        value.works.insert(work, at: 0)
        try write(value)
        return value
    }

    func discard(_ work: KadrioWork) {
        do {
            guard try pendingSave()?.work.id != work.id else { return }
        } catch { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(work.fileName))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(work.thumbnailName))
    }

    func delete(_ work: KadrioWork) throws -> KadrioLedger {
        var value = try load()
        guard try pendingSave()?.work.id != work.id else { throw KadrioError.saveUncertain }
        value.works.removeAll { $0.id == work.id }
        try write(value)
        discard(work)
        return value
    }

    func clear() throws -> KadrioLedger {
        let previous = try load()
        guard try pendingSave() == nil else { throw KadrioError.saveUncertain }
        let value = KadrioLedger()
        try write(value)
        for work in previous.works { discard(work) }
        return value
    }

    nonisolated func url(for work: KadrioWork, thumbnail: Bool = false) -> URL {
        directory.appendingPathComponent(thumbnail ? work.thumbnailName : work.fileName)
    }
}
