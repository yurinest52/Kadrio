import SwiftUI
import Combine

@MainActor
final class KadrioAppState: ObservableObject {
    @Published private(set) var ledger = KadrioLedger()
    @Published private(set) var initialized = false
    @Published private(set) var isInitializing = false
    @Published private(set) var initializationError: String?
    @Published private(set) var saving = false
    @Published var errorMessage: String?
    @Published var showPaywall = false {
        didSet {
            if !showPaywall { isInitialPaywall = false }
        }
    }
    private var isInitialPaywall = false
    @Published var accessDenied = false
    let storage: KadrioWorksStorage
    let worksDirectory: URL
    private var pendingSave: KadrioWorksStorage.PendingSave?

    init(storage: KadrioWorksStorage = KadrioWorksStorage()) {
        self.storage = storage
        worksDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("KadrioWorks")
    }

    func initialize() async {
        guard !saving, !isInitializing else { return }
        isInitializing = true
        saving = true
        defer {
            saving = false
            isInitializing = false
        }
        do {
            ledger = try await storage.load()
        } catch {
            initialized = false
            initializationError = kadrioText("storageRecovery.message")
            return
        }
        do {
            pendingSave = try await storage.pendingSave()
            if pendingSave != nil {
                _ = try await resumePendingSave()
            }
        } catch {
            if pendingSave == nil { errorMessage = kadrioText("error.pendingRead") }
            else { reportSaveFailure(error) }
        }
        initializationError = nil
        initialized = true
    }

    func presentInitialPaywall() {
        isInitialPaywall = true
        showPaywall = true
    }

    @discardableResult
    func replenish() async -> Bool {
        if isInitialPaywall {
            showPaywall = false
            return true
        }
        do {
            ledger = try await storage.topUp()
            showPaywall = false
            return true
        } catch {
            present(error)
            return false
        }
    }

    func clearHistory() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            if pendingSave == nil { pendingSave = try await storage.pendingSave() }
            if let pendingSave {
                ledger = try await storage.finishPendingSave(pendingSave)
                self.pendingSave = nil
            }
            ledger = try await storage.clear()
        }
        catch { present(error) }
    }

    func delete(_ work: KadrioWork) async {
        guard !saving else { return }
        do { ledger = try await storage.delete(work) }
        catch { present(error) }
    }

    func workURL(_ work: KadrioWork, thumbnail: Bool = false) -> URL {
        worksDirectory.appendingPathComponent(thumbnail ? work.thumbnailName : work.fileName)
    }

    func present(_ error: Error) {
        if let error = error as? KadrioError, error == .photoAccess || error == .cameraAccess { accessDenied = true }
        else { errorMessage = (error as? KadrioError)?.localizedDescription ?? kadrioText("error.operation") }
    }

    func save(sources: [KadrioSource], state: KadrioEditState, tool: KadrioTool) async -> KadrioWork? {
        guard !saving else { return nil }
        saving = true
        defer { saving = false }
        var staged: KadrioWork?
        var temporary: [URL] = []
        defer { for url in temporary { try? FileManager.default.removeItem(at: url) } }
        do {
            if pendingSave == nil { pendingSave = try await storage.pendingSave() }
            if let pendingSave {
                let sameResult = KadrioRenderKey(state: pendingSave.state, sourceIDs: pendingSave.sourceIDs)
                    == KadrioRenderKey(state: state, sourceIDs: sources.map(\.id))
                if pendingSave.stage == .prepared, !sameResult {
                    try await storage.cancelPreparedSave(pendingSave)
                    self.pendingSave = nil
                } else if let completed = try await resumePendingSave(), sameResult {
                    return completed.work
                }
            }
            guard ledger.tokens > 0 else { showPaywall = true; return nil }
            try await KadrioPhotoLibrary.authorize()
            let export = try await KadrioImageProcessing.shared.export(sources: sources, state: state)
            temporary.append(export)
            let thumbnail = export.deletingLastPathComponent().appendingPathComponent("KadrioThumbnail-\(UUID()).jpg")
            temporary.append(thumbnail)
            try await KadrioImageProcessing.shared.thumbnail(from: export, to: thumbnail)
            let work = try await storage.stage(exportURL: export, thumbnailURL: thumbnail, tool: tool)
            staged = work
            let pending = KadrioWorksStorage.PendingSave(work: work, state: state, sourceIDs: sources.map(\.id))
            try await storage.recordPendingSave(pending)
            pendingSave = pending
            _ = try await resumePendingSave()
            return work
        } catch {
            if let staged, pendingSave?.work.id != staged.id { await storage.discard(staged) }
            reportSaveFailure(error)
            return nil
        }
    }

    private func resumePendingSave() async throws -> KadrioWorksStorage.PendingSave? {
        guard var pending = pendingSave else { return nil }
        try await storage.validatePendingFiles(pending)
        switch pending.stage {
        case .prepared:
            pending = try await savePreparedToPhotos(pending)
        case .savingToPhotos:
            if let recorded = try await storage.pendingSave(), recorded.work.id == pending.work.id {
                pending.photoIdentifier = recorded.photoIdentifier
            }
            guard let identifier = pending.photoIdentifier,
                  KadrioPhotoLibrary.containsAsset(with: identifier) else { throw KadrioError.saveUncertain }
            pending.stage = .photosConfirmed
            pendingSave = pending
            try await storage.recordPendingSave(pending)
        case .photosConfirmed, .committed:
            break
        }
        ledger = try await storage.finishPendingSave(pending)
        pendingSave = nil
        return pending
    }

    private func savePreparedToPhotos(_ prepared: KadrioWorksStorage.PendingSave) async throws -> KadrioWorksStorage.PendingSave {
        var pending = prepared
        pending.stage = .savingToPhotos
        try await storage.recordPendingSave(pending)
        pendingSave = pending
        let recordIdentifier = await storage.photoIdentifierRecorder(for: pending)
        let url = await storage.url(for: pending.work)
        do {
            try await KadrioPhotoLibrary.save(url, recordIdentifier: recordIdentifier)
        } catch {
            var retry = prepared
            retry.photoIdentifier = nil
            try await storage.recordPendingSave(retry)
            pendingSave = retry
            throw error
        }
        pending.stage = .photosConfirmed
        pendingSave = pending
        if let recorded = try? await storage.pendingSave(), recorded.work.id == pending.work.id {
            pending.photoIdentifier = recorded.photoIdentifier
        }
        pendingSave = pending
        try await storage.recordPendingSave(pending)
        return pending
    }

    private func reportSaveFailure(_ error: Error) {
        if let error = error as? KadrioError, error == .pendingFilesMissing {
            present(error)
            return
        }
        switch pendingSave?.stage {
        case .savingToPhotos:
            errorMessage = kadrioText("error.saveUncertain")
        case .photosConfirmed, .committed:
            errorMessage = kadrioText("error.saveFinalize")
        case .prepared, nil:
            present(error)
        }
    }
}

extension KadrioError: Equatable {}
