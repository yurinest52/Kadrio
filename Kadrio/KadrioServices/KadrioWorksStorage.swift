import Foundation

actor KadrioWorksStorage {
    let directory: URL
    private var ledger: KadrioLedger?
    private var ledgerURL: URL { directory.appendingPathComponent("KadrioWorksLedger.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("KadrioWorks", isDirectory: true)
    }

    func load() throws -> KadrioLedger {
        if let ledger { return ledger }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let value: KadrioLedger
        if FileManager.default.fileExists(atPath: ledgerURL.path) {
            value = try JSONDecoder().decode(KadrioLedger.self, from: Data(contentsOf: ledgerURL))
            guard value.tokens >= 0 else { throw KadrioError.storage }
        } else {
            value = KadrioLedger()
        }
        ledger = value
        let retained = Set(value.works.flatMap { [$0.fileName, $0.thumbnailName] } + [ledgerURL.lastPathComponent])
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where !retained.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
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
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(work.fileName))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(work.thumbnailName))
    }

    func delete(_ work: KadrioWork) throws -> KadrioLedger {
        var value = try load()
        value.works.removeAll { $0.id == work.id }
        try write(value)
        discard(work)
        return value
    }

    func clear() throws -> KadrioLedger {
        let previous = try load()
        let value = KadrioLedger()
        try write(value)
        for work in previous.works { discard(work) }
        return value
    }

    func url(for work: KadrioWork, thumbnail: Bool = false) -> URL {
        directory.appendingPathComponent(thumbnail ? work.thumbnailName : work.fileName)
    }
}
