import SwiftUI
import Combine

@MainActor
final class KadrioAppState: ObservableObject {
    @Published private(set) var ledger = KadrioLedger()
    @Published private(set) var initialized = false
    @Published private(set) var saving = false
    @Published var errorMessage: String?
    @Published var showPaywall = false
    @Published var accessDenied = false
    let storage: KadrioWorksStorage
    let worksDirectory: URL

    init(storage: KadrioWorksStorage = KadrioWorksStorage()) {
        self.storage = storage
        worksDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("KadrioWorks")
    }

    func initialize() async {
        do { ledger = try await storage.load(); initialized = true }
        catch { errorMessage = kadrioText("error.storage") }
    }

    @discardableResult
    func replenish() async -> Bool {
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
        do { ledger = try await storage.clear() }
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
        guard ledger.tokens > 0 else { showPaywall = true; return nil }
        saving = true
        defer { saving = false }
        var staged: KadrioWork?
        var temporary: [URL] = []
        do {
            try await KadrioPhotoLibrary.authorize()
            let export = try await KadrioImageProcessing.shared.export(sources: sources, state: state)
            temporary.append(export)
            let thumbnail = export.deletingLastPathComponent().appendingPathComponent("KadrioThumbnail-\(UUID()).jpg")
            temporary.append(thumbnail)
            try await KadrioImageProcessing.shared.thumbnail(from: export, to: thumbnail)
            let work = try await storage.stage(exportURL: export, thumbnailURL: thumbnail, tool: tool)
            staged = work
            try await KadrioPhotoLibrary.save(export)
            ledger = try await storage.commit(work)
            for url in temporary { try? FileManager.default.removeItem(at: url) }
            return work
        } catch {
            if let staged { await storage.discard(staged) }
            for url in temporary { try? FileManager.default.removeItem(at: url) }
            present(error)
            return nil
        }
    }
}

extension KadrioError: Equatable {}
