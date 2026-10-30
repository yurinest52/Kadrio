import SwiftUI
import Combine

@MainActor
final class KadrioEditorModel: ObservableObject {
    @Published var sources: [KadrioSource]
    @Published var tool: KadrioTool
    @Published var state: KadrioEditState
    @Published private(set) var preview: UIImage?
    @Published private(set) var original: UIImage?
    @Published private(set) var thumbnails: [KadrioFilter: UIImage] = [:]
    @Published private(set) var undoStates: [KadrioEditState] = []
    @Published private(set) var redoStates: [KadrioEditState] = []
    @Published private(set) var rendering = false
    @Published var renderError: String?
    private var previewTask: Task<Void, Never>?
    private var initialState: KadrioEditState
    private var savedState: KadrioEditState
    private var revision = 0

    init(request: KadrioEditorRequest) {
        sources = request.sources
        tool = request.tool
        var value = KadrioEditState()
        value.sourceCount = request.sources.count
        value.layout = KadrioCollageLayout.initial(for: request.sources.count).rawValue
        value.collage = request.tool == .collage && request.sources.count >= 2
        if let source = request.sources.first { value.freeRatio = value.collage ? 0.8 : Double(source.pixelWidth) / Double(source.pixelHeight) }
        state = value
        initialState = value
        savedState = value
    }

    var dirty: Bool { state != savedState }

    func checkpoint() {
        if undoStates.last != state { undoStates.append(state) }
        if undoStates.count > 60 { undoStates.removeFirst() }
        redoStates.removeAll()
    }

    func change(_ action: (inout KadrioEditState) -> Void) {
        checkpoint()
        action(&state)
        updatePreview()
    }

    func undo() {
        guard let previous = undoStates.popLast() else { return }
        redoStates.append(state)
        state = previous
        updatePreview()
    }

    func redo() {
        guard let next = redoStates.popLast() else { return }
        undoStates.append(state)
        state = next
        updatePreview()
    }

    func resetCrop() {
        change { value in
            value.crop = KadrioPlacement()
            value.ratio = .free
            value.turns = 0
            value.flipped = false
            value.freeRatio = value.collage ? 0.8 : initialState.freeRatio
        }
    }

    func markSaved() { savedState = state }

    func updatePreview() {
        revision += 1
        let currentRevision = revision
        previewTask?.cancel()
        let sources = sources
        let state = state
        rendering = true
        previewTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(35))
                try Task.checkCancellation()
                let image = try await KadrioImageProcessing.shared.preview(sources: sources, state: state)
                guard !Task.isCancelled, revision == currentRevision else { return }
                preview = image
                rendering = false
                var originalState = state
                originalState.filter = .original
                let originalImage = try await KadrioImageProcessing.shared.preview(sources: sources, state: originalState)
                guard !Task.isCancelled, revision == currentRevision else { return }
                original = originalImage
            } catch {
                if !Task.isCancelled, revision == currentRevision { rendering = false; renderError = kadrioText("error.image") }
            }
        }
    }

    func loadThumbnails() async {
        for filter in KadrioFilter.allCases where thumbnails[filter] == nil {
            guard !Task.isCancelled else { return }
            var value = initialState
            value.filter = filter
            value.intensity = 1
            if let image = try? await KadrioImageProcessing.shared.preview(sources: sources, state: value) {
                let thumb = await Task.detached { image.preparingThumbnail(of: CGSize(width: 90, height: 110)) }.value
                thumbnails[filter] = thumb ?? image
            }
        }
    }

    func addSources(_ additions: [KadrioSource]) {
        sources += additions.prefix(max(0, 4 - sources.count))
        change { value in
            value.sourceCount = sources.count
            value.layout = KadrioCollageLayout.initial(for: sources.count).rawValue
            value.collage = true
            value.freeRatio = 0.8
            value.ratio = .free
            value.crop = KadrioPlacement()
        }
        tool = .collage
    }

    func finish() {
        previewTask?.cancel()
        let sources = sources
        Task { await KadrioImageProcessing.shared.clean(sources) }
    }
}
