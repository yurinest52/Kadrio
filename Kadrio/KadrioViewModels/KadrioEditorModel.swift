import SwiftUI
import Combine

@MainActor
final class KadrioEditorModel: ObservableObject {
    enum PreviewLoadState {
        case idle, loading, success, failure
    }

    struct FrameSettings: Equatable {
        var color: KadrioColor
        var thickness: Double
    }

    struct Snapshot: Equatable {
        var state: KadrioEditState
        var tool: KadrioTool
        var sourceIDs: [UUID]
        var placementsBySourceID: [UUID: KadrioPlacement] = [:]
        var frameSettings: [KadrioFrame: FrameSettings] = [:]

        mutating func storeActiveSettings() {
            for (index, id) in sourceIDs.enumerated() where state.placements.indices.contains(index) {
                placementsBySourceID[id] = state.placements[index]
            }
            frameSettings[state.frame] = FrameSettings(color: state.frameColor, thickness: state.thickness)
        }
    }

    @Published var selectedCollageSourceID: UUID?
    private var dividerGesture: (divider: KadrioCollageDivider, geometry: KadrioCollageGeometry, split: KadrioCollageSplit, spacing: Double, layout: KadrioCollageLayout)?
    @Published private(set) var sources: [KadrioSource]
    @Published private var snapshot: Snapshot
    @Published private(set) var preview: UIImage?
    @Published private(set) var previewState: KadrioEditState?
    @Published private(set) var previewCropSourceSize = CGSize.zero
    @Published private(set) var previewDisplaySize = CGSize.zero
    @Published private(set) var previewSourceIDs: [UUID] = []
    @Published private(set) var comparisonPreview: UIImage?
    @Published private(set) var thumbnails: [KadrioFilter: UIImage] = [:]
    @Published private(set) var layoutThumbnails: [KadrioCollageLayout: UIImage] = [:]
    @Published private(set) var frameThumbnails: [KadrioFrame: UIImage] = [:]
    private var frameThumbnailKeys: [KadrioFrame: KadrioRenderKey] = [:]
    private struct ThumbnailRenderKey: Equatable {
        let sourceIDs: [UUID]
        let state: KadrioEditState
    }
    private struct ThumbnailBatchKey: Equatable {
        let layouts: [ThumbnailRenderKey]
        let filter: ThumbnailRenderKey
        let frames: [KadrioRenderKey]
    }
    private var scheduledThumbnailKey: ThumbnailBatchKey?
    private var thumbnailGeneration = 0
    private var layoutThumbnailKeys: [KadrioCollageLayout: ThumbnailRenderKey] = [:]
    private var layoutThumbnailTask: Task<Void, Never>?
    @Published private(set) var undoStates: [Snapshot] = []
    @Published private(set) var redoStates: [Snapshot] = []
    @Published private(set) var isRenderingPreview = false
    @Published private(set) var hasPreviewFailure = false
    @Published var renderError: String?
    @Published private(set) var correctionRevision = 0
    private var previewTask: Task<Void, Never>?
    private var initialState: KadrioEditState
    private var savedSnapshot: Snapshot
    @Published private(set) var hasSuccessfulSave = false
    private var revision = 0
    private var sliderEditing = false
    private var gestureEditing = false
    private var filterThumbnailKey: ThumbnailRenderKey?
    private static let historyLimit = 60
    private var continuousEditStart: Snapshot?
    private var cropPanning = false
    private var cropZoomStart: Double?
    private var lastCropTranslation = CGSize.zero
    private var freeCropStart: (ratio: Double, size: CGSize)?
    private var collageGestureContext: CollageGestureContext?

    private struct CollageGestureContext {
        let geometry: KadrioCollageGeometry
        let index: Int
        let sourceSize: CGSize
        let initialZoom: Double
        var placement: KadrioPlacement
        var translation = CGSize.zero
        var magnification: Double = 1
        var zoomAnchor: CGPoint?
    }

    init(request: KadrioEditorRequest) {
        sources = request.sources
        var value = KadrioEditState()
        value.collage = request.tool == .collage && request.sources.count >= 2
        value.sourceCount = value.collage ? min(4, request.sources.count) : min(1, request.sources.count)
        value.collageLayout = KadrioCollageLayout.initial(for: value.sourceCount)
        if let source = request.sources.first { value.freeRatio = value.collage ? 0.8 : Double(source.pixelWidth) / Double(source.pixelHeight) }
        var initial = Snapshot(state: value, tool: request.tool == .collage && !value.collage ? .crop : request.tool,
                               sourceIDs: request.sources.prefix(value.sourceCount).map(\.id))
        initial.storeActiveSettings()
        snapshot = initial
        initialState = value
        savedSnapshot = initial
    }

    private(set) var state: KadrioEditState {
        get { snapshot.state }
        set {
            var next = snapshot
            next.state = newValue
            next.storeActiveSettings()
            snapshot = next
        }
    }

    var tool: KadrioTool {
        get { snapshot.tool }
        set {
            guard newValue != .collage || state.collage else { return }
            guard newValue != snapshot.tool else { return }
            endContinuousEditing()
            selectedCollageSourceID = nil
            snapshot.tool = newValue
        }
    }

    var activeSources: [KadrioSource] {
        snapshot.sourceIDs.compactMap { id in sources.first { $0.id == id } }
    }

    var activeSourceCount: Int { snapshot.sourceIDs.count }

    var dirty: Bool {
        state != savedSnapshot.state || snapshot.sourceIDs != savedSnapshot.sourceIDs
            || snapshot.placementsBySourceID != savedSnapshot.placementsBySourceID
            || snapshot.frameSettings != savedSnapshot.frameSettings
    }

    var isCurrentResultSaved: Bool {
        hasSuccessfulSave
            && KadrioRenderKey(state: state, sourceIDs: snapshot.sourceIDs)
                == KadrioRenderKey(state: savedSnapshot.state, sourceIDs: savedSnapshot.sourceIDs)
    }

    func checkpoint() {
        endContinuousEditing()
        recordUndo(snapshot)
    }

    private func recordUndo(_ previous: Snapshot) {
        if undoStates.last != previous { undoStates.append(previous) }
        if undoStates.count > Self.historyLimit { undoStates.removeFirst() }
        redoStates.removeAll()
    }

    func change(_ action: (inout KadrioEditState) -> Void) {
        var next = state
        action(&next)
        guard next != state else { return }
        if continuousEditStart == nil { checkpoint() }
        state = next
        updatePreview()
    }

    func beginContinuousEditing() {
        guard continuousEditStart == nil else { return }
        continuousEditStart = snapshot
    }

    func endContinuousEditing() {
        guard let initial = continuousEditStart else { return }
        continuousEditStart = nil
        guard initial != snapshot else { return }
        recordUndo(initial)
    }

    func editingBinding<Value: Equatable>(for keyPath: WritableKeyPath<KadrioEditState, Value>) -> Binding<Value> {
        Binding(get: { self.state[keyPath: keyPath] }, set: { value in
            self.beginContinuousEditing()
            self.change { $0[keyPath: keyPath] = value }
        })
    }

    func selectCropRatio(_ ratio: KadrioCropRatio) {
        change {
            $0.ratio = ratio
            $0.cropRatioInverted = false
            $0.crop = KadrioPlacement()
        }
    }

    func selectFilter(_ filter: KadrioFilter) { change { $0.filter = filter } }

    func selectTool(_ selected: KadrioTool) { tool = selected }

    func selectFrame(_ frame: KadrioFrame) {
        let next = stateSelectingFrame(frame)
        change { $0 = next }
    }

    private func stateSelectingFrame(_ frame: KadrioFrame) -> KadrioEditState {
        var value = state.selectingFrame(frame)
        if let settings = snapshot.frameSettings[frame] {
            value.frameColor = settings.color
            value.thickness = settings.thickness
        }
        return value
    }

    func selectFrameColor(_ color: KadrioColor) { change { $0.frameColor = color } }

    func correctionBinding(for keyPath: WritableKeyPath<KadrioEditState, Double>, revision: Int) -> Binding<Double> {
        let binding = editingBinding(for: keyPath)
        return Binding(get: { binding.wrappedValue }, set: { value in
            guard revision == self.correctionRevision else { return }
            binding.wrappedValue = value
        })
    }

    func correctionEditingChanged(_ editing: Bool, revision: Int) {
        guard revision == correctionRevision else { return }
        sliderEditingChanged(editing)
    }

    func resetCorrections() {
        let wasEditing = sliderEditing
        let needsReset = state.brightness != 0 || state.contrast != 1
        correctionRevision += 1
        endContinuousEditing()
        sliderEditing = false
        change { $0.brightness = 0; $0.contrast = 1 }
        if wasEditing && !needsReset { updatePreview() }
    }

    func perform(_ action: KadrioCropAction) {
        switch action {
        case .rotate: rotateClockwise()
        case .flip: flipHorizontally()
        case .reset: resetCrop()
        }
    }

    func undo() {
        endContinuousEditing()
        guard let previous = undoStates.popLast() else { return }
        redoStates.append(snapshot)
        snapshot = previous
        selectedCollageSourceID = nil
        updatePreview()
    }

    func redo() {
        endContinuousEditing()
        guard let next = redoStates.popLast() else { return }
        undoStates.append(snapshot)
        snapshot = next
        if let selectedCollageSourceID, !next.sourceIDs.contains(selectedCollageSourceID) { self.selectedCollageSourceID = nil }
        updatePreview()
    }

    func rotateClockwise() {
        change { value in
            let rotationStep = value.flipped ? -1 : 1
            value.turns = (value.turns + rotationStep + 4) % 4
            value.crop = KadrioPlacement(zoom: value.crop.zoom, x: -value.crop.y, y: value.crop.x)
            value.cropRatioInverted.toggle()
        }
    }

    func flipHorizontally() {
        change { value in
            value.flipped.toggle()
            value.crop.x = -value.crop.x
        }
    }

    func resetCrop() {
        change { value in
            value.crop = KadrioPlacement()
            value.ratio = .free
            value.cropRatioInverted = false
            value.turns = 0
            value.flipped = false
            value.freeRatio = value.collage ? 0.8 : initialState.freeRatio
        }
    }

    func snapshotForSaving() -> Snapshot { snapshot }

    func markSaved(_ saved: Snapshot? = nil) {
        savedSnapshot = saved ?? snapshot
        hasSuccessfulSave = true
    }

    func sliderEditingChanged(_ editing: Bool) {
        if editing { beginContinuousEditing() } else { endContinuousEditing() }
        sliderEditing = editing
        updatePreview()
    }

    func gestureEditingChanged(_ editing: Bool) {
        guard gestureEditing != editing else { return }
        gestureEditing = editing
        if !editing { updatePreview() }
    }

    func updateCropPan(translation: CGSize, previewSize: CGSize) {
        if !cropPanning {
            beginContinuousEditing()
            cropPanning = true
            lastCropTranslation = .zero
            gestureEditingChanged(true)
        }
        guard previewCropSourceSize.width > 0, previewCropSourceSize.height > 0 else { return }
        let delta = CGSize(width: translation.width - lastCropTranslation.width,
                           height: translation.height - lastCropTranslation.height)
        lastCropTranslation = translation
        change { $0.crop = KadrioGeometry.pannedCrop($0.crop, sourceSize: previewCropSourceSize,
            previewSize: previewSize, state: $0, translation: delta) }
    }

    func updateCropZoom(magnification: Double) {
        if cropZoomStart == nil {
            beginContinuousEditing()
            cropZoomStart = state.crop.zoom
            gestureEditingChanged(true)
        }
        let zoom = KadrioGeometry.clampedZoom((cropZoomStart ?? 1) * magnification)
        change {
            $0.crop.zoom = zoom
            if previewCropSourceSize.width > 0, let preview {
                $0.crop = KadrioGeometry.pannedCrop($0.crop, sourceSize: previewCropSourceSize,
                    previewSize: preview.size, state: $0, translation: .zero)
            }
        }
    }

    func updateFreeCrop(translation: CGSize, previewSize: CGSize) {
        if freeCropStart == nil {
            beginContinuousEditing()
            freeCropStart = (state.cropAspectRatio, previewSize)
            gestureEditingChanged(true)
        }
        guard let start = freeCropStart else { return }
        let width = max(60, start.size.width + translation.width)
        let height = max(60, start.size.height + translation.height)
        let ratio = min(3, max(0.25, start.ratio * (width / max(1, start.size.width)) / (height / max(1, start.size.height))))
        change { $0.freeRatio = $0.cropRatioInverted ? 1 / ratio : ratio }
    }

    func endCropPan() {
        cropPanning = false
        lastCropTranslation = .zero
        finishCropInteraction()
    }

    func endCropZoom() {
        cropZoomStart = nil
        finishCropInteraction()
    }

    func endFreeCrop() {
        freeCropStart = nil
        finishCropInteraction()
    }

    func endCropGestures() {
        cropPanning = false
        cropZoomStart = nil
        lastCropTranslation = .zero
        freeCropStart = nil
        finishCropInteraction()
    }

    private func finishCropInteraction() {
        let active = cropPanning || cropZoomStart != nil || freeCropStart != nil
        if !active { endContinuousEditing() }
        gestureEditingChanged(active)
    }

    func updateCollageGesture(geometry: KadrioCollageGeometry, previewSize: CGSize, panStart: CGPoint?,
                              translation: CGSize?, magnification: Double?, zoomStart: CGPoint?) {
        guard dividerGesture == nil else { return }
        if collageGestureContext == nil {
            guard state.collage, activeSourceCount >= 2,
                  KadrioCollageGeometry(state: state, count: activeSourceCount, previewSize: previewSize) == geometry,
                  let point = zoomStart ?? panStart, let index = geometry.photo(at: point),
                  activeSources.indices.contains(index), state.placements.indices.contains(index) else { return }
            let source = activeSources[index]
            beginContinuousEditing()
            gestureEditingChanged(true)
            collageGestureContext = CollageGestureContext(geometry: geometry, index: index,
                sourceSize: CGSize(width: source.pixelWidth, height: source.pixelHeight),
                initialZoom: state.placements[index].zoom, placement: state.placements[index])
        }
        guard var context = collageGestureContext else { return }
        let translation = translation ?? context.translation
        let delta = CGSize(width: translation.width - context.translation.width,
                           height: translation.height - context.translation.height)
        context.translation = translation
        let canvasDelta = context.geometry.canvasTranslation(delta)
        if let magnification, let zoomStart {
            if context.zoomAnchor == nil {
                let anchor = zoomStart.applying(context.geometry.canvasToView.inverted())
                context.zoomAnchor = CGPoint(x: anchor.x - canvasDelta.width, y: anchor.y - canvasDelta.height)
            }
            context.magnification = magnification
        }
        let cell = context.geometry.cells[context.index]
        let zoom = KadrioGeometry.clampedZoom(context.initialZoom * context.magnification)
        let placement = context.geometry.placement(index: context.index, sourceSize: context.sourceSize,
            start: context.placement, translation: delta, magnification: zoom / context.placement.zoom,
            anchor: context.zoomAnchor ?? CGPoint(x: cell.midX, y: cell.midY))
        context.placement = placement
        if let anchor = context.zoomAnchor {
            context.zoomAnchor = CGPoint(x: anchor.x + canvasDelta.width, y: anchor.y + canvasDelta.height)
        }
        collageGestureContext = context
        change { $0.placements[context.index] = placement }
    }

    func endCollageGesture() {
        guard collageGestureContext != nil else { return }
        collageGestureContext = nil
        endContinuousEditing()
        gestureEditingChanged(false)
    }

    func updateCollageDivider(_ divider: KadrioCollageDivider, translation: CGSize, geometry: KadrioCollageGeometry) {
        if dividerGesture == nil {
            guard state.collage,
                  KadrioCollageGeometry(state: state, count: activeSourceCount, previewSize: geometry.previewSize) == geometry else { return }
            endCollageGesture()
            beginContinuousEditing()
            gestureEditingChanged(true)
            dividerGesture = (divider, geometry, state.collageSplit, state.spacing, state.collageLayout)
        }
        guard let context = dividerGesture, context.divider == divider else { return }
        let delta = context.geometry.canvasTranslation(translation)
        let size = KadrioGeometry.collageSize(preview: true)
        let gap = min(size.width, size.height) * context.spacing
        var split = context.split
        if divider == .vertical {
            split.x = min(0.8, max(0.2, split.x + delta.width / (size.width - 3 * gap)))
        } else {
            split.y = min(0.8, max(0.2, split.y - delta.height / (size.height - 3 * gap)))
        }
        change {
            var splits = $0.collageSplits ?? [:]
            splits[context.layout.rawValue] = split == KadrioCollageSplit() ? nil : split
            $0.collageSplits = splits.isEmpty ? nil : splits
        }
    }

    func endCollageDivider() {
        guard dividerGesture != nil else { return }
        dividerGesture = nil
        endContinuousEditing()
        gestureEditingChanged(false)
    }

    var previewLoadState: PreviewLoadState {
        if isRenderingPreview { return .loading }
        if hasPreviewFailure { return .failure }
        return preview == nil ? .idle : .success
    }

    func retryPreview() {
        guard previewTask == nil else { return }
        updatePreview()
    }

    func updatePreview() {
        revision += 1
        hasPreviewFailure = false
        renderError = nil
        isRenderingPreview = true
        guard previewTask == nil else { return }
        previewTask = Task(priority: .userInitiated) {
            defer {
                previewTask = nil
                isRenderingPreview = false
                if !Task.isCancelled { refreshLayoutThumbnails() }
            }
            while !Task.isCancelled {
                let currentRevision = revision
                let sources = activeSources
                let state = state
                let interactive = sliderEditing || gestureEditing
                do {
                    let frame = try await KadrioImageProcessing.shared.previewFrame(
                        sources: sources, state: state, maxPixel: KadrioImageQuality.previewMaxPixel)
                    guard !Task.isCancelled else { return }
                    if revision != currentRevision {
                        continue
                    }
                    previewState = state
                    previewCropSourceSize = frame.cropSourceSize
                    let cropSize = KadrioGeometry.cropSize(frame.cropSourceSize, ratio: state.cropAspectRatio)
                    previewDisplaySize = KadrioGeometry.frameBounds(cropSize, state: state).size
                    previewSourceIDs = sources.map(\.id)
                    preview = frame.image
                    if interactive || gestureEditing { return }
                    var comparisonState = state
                    comparisonState.filter = .original
                    comparisonState.brightness = 0
                    comparisonState.contrast = 1
                    if comparisonState == state {
                        comparisonPreview = frame.image
                        return
                    }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    if revision != currentRevision { continue }
                    let comparisonImage = try await KadrioImageProcessing.shared.preview(sources: sources, state: comparisonState)
                    guard !Task.isCancelled else { return }
                    if revision != currentRevision { continue }
                    comparisonPreview = comparisonImage
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    if revision != currentRevision { continue }
                    hasPreviewFailure = true
                    renderError = kadrioText("preview.renderFailed")
                    return
                }
            }
        }
    }

    private var currentFilterThumbnailKey: ThumbnailRenderKey {
        var value = state
        value.filter = .original
        value.intensity = 1
        let key = KadrioRenderKey(state: value, sourceIDs: activeSources.map(\.id))
        return ThumbnailRenderKey(sourceIDs: key.sourceIDs, state: key.state)
    }

    func loadThumbnails() async {
        let key = currentFilterThumbnailKey
        guard filterThumbnailKey != key else { return }
        let photos = activeSources
        var result: [KadrioFilter: UIImage] = [:]
        for filter in KadrioFilter.allCases {
            if let previewTask { await previewTask.value }
            guard !Task.isCancelled, currentFilterThumbnailKey == key else { return }
            var value = key.state
            value.filter = filter
            value.intensity = 1
            guard let image = try? await KadrioImageProcessing.shared.preview(sources: photos, state: value, maxPixel: KadrioImageQuality.filterThumbnailMaxPixel),
                  !Task.isCancelled, currentFilterThumbnailKey == key else { return }
            result[filter] = image
        }
        guard !Task.isCancelled, currentFilterThumbnailKey == key else { return }
        thumbnails = result
        filterThumbnailKey = key
    }

    func missingSourceCount(for layout: KadrioCollageLayout) -> Int {
        max(0, layout.photoCount - sources.count)
    }

    private func loadFrameThumbnails() async {
        let photos = activeSources
        let ids = photos.map(\.id)
        for frame in KadrioFrame.allCases where frame != .none {
            guard !Task.isCancelled else { return }
            if let previewTask { await previewTask.value }
            guard !Task.isCancelled else { return }
            let candidate = stateSelectingFrame(frame)
            let key = KadrioRenderKey(state: candidate, sourceIDs: ids)
            guard frameThumbnailKeys[frame] != key else { continue }
            guard let image = try? await KadrioImageProcessing.shared.preview(
                sources: photos, state: candidate, maxPixel: KadrioImageQuality.filterThumbnailMaxPixel),
                !Task.isCancelled,
                key == KadrioRenderKey(state: stateSelectingFrame(frame), sourceIDs: activeSources.map(\.id)) else { return }
            frameThumbnails[frame] = image
            frameThumbnailKeys[frame] = key
        }
    }

    private func sourceIDs(for count: Int) -> [UUID] {
        let active = Set(snapshot.sourceIDs)
        return Array((snapshot.sourceIDs + sources.filter { !active.contains($0.id) }.map(\.id)).prefix(count))
    }

    private func apply(_ next: Snapshot) {
        var next = next
        next.storeActiveSettings()
        guard next != snapshot else { return }
        checkpoint()
        snapshot = next
        if let selectedCollageSourceID, !next.sourceIDs.contains(selectedCollageSourceID) { self.selectedCollageSourceID = nil }
        updatePreview()
    }

    func swapSources(_ first: UUID, _ second: UUID) {
        guard first != second, let a = snapshot.sourceIDs.firstIndex(of: first),
              let b = snapshot.sourceIDs.firstIndex(of: second) else { return }
        var next = snapshot
        next.sourceIDs.swapAt(a, b)
        next.state.placements.swapAt(a, b)
        apply(next)
    }

    @discardableResult
    func replaceSource(_ id: UUID, with source: KadrioSource) -> Bool {
        guard let index = snapshot.sourceIDs.firstIndex(of: id), !snapshot.sourceIDs.contains(source.id) else { return false }
        if !sources.contains(where: { $0.id == source.id }) { sources.append(source) }
        var next = snapshot
        next.sourceIDs[index] = source.id
        next.state.placements[index] = KadrioPlacement()
        apply(next)
        return true
    }

    private func placements(for ids: [UUID]) -> [KadrioPlacement] {
        let values = ids.map { id in
            snapshot.placementsBySourceID[id] ?? KadrioPlacement()
        }
        return values + Array(repeating: KadrioPlacement(), count: max(0, 4 - values.count))
    }

    private func layoutThumbnailRequest(_ layout: KadrioCollageLayout) -> ThumbnailRenderKey {
        let ids = sourceIDs(for: layout.photoCount)
        var value = KadrioEditState()
        value.collage = true
        value.sourceCount = ids.count
        value.collageLayout = layout
        if let split = state.collageSplits?[layout.rawValue] {
            value.collageSplits = [layout.rawValue: split]
        }
        value.spacing = state.spacing
        value.placements = placements(for: ids)
        value.filter = state.filter
        value.intensity = state.intensity
        value.brightness = state.brightness
        value.contrast = state.contrast
        return ThumbnailRenderKey(sourceIDs: ids, state: value)
    }

    private func refreshLayoutThumbnails() {
        let layouts = KadrioCollageLayout.allCases
        let requests = layouts.map { layoutThumbnailRequest($0) }
        let frames = KadrioFrame.allCases.filter { $0 != .none }
        let frameKeys = frames.map { KadrioRenderKey(state: stateSelectingFrame($0), sourceIDs: activeSources.map(\.id)) }
        let key = ThumbnailBatchKey(layouts: requests, filter: currentFilterThumbnailKey, frames: frameKeys)
        let complete = zip(layouts, requests).allSatisfy { layoutThumbnailKeys[$0.0] == $0.1 }
            && filterThumbnailKey == key.filter
            && zip(frames, frameKeys).allSatisfy { frameThumbnailKeys[$0.0] == $0.1 }
        guard !complete else { return }
        if scheduledThumbnailKey == key, let layoutThumbnailTask, !layoutThumbnailTask.isCancelled { return }
        layoutThumbnailTask?.cancel()
        thumbnailGeneration += 1
        let generation = thumbnailGeneration
        scheduledThumbnailKey = key
        layoutThumbnailTask = Task(priority: .utility) {
            defer {
                if thumbnailGeneration == generation { layoutThumbnailTask = nil }
            }
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            for (layout, request) in zip(layouts, requests) {
                if let previewTask { await previewTask.value }
                guard !Task.isCancelled, layoutThumbnailRequest(layout) == request else { return }
                guard layoutThumbnailKeys[layout] != request else { continue }
                let photos = request.sourceIDs.compactMap { id in sources.first { $0.id == id } }
                guard let image = try? await KadrioImageProcessing.shared.layoutThumbnail(sources: photos, state: request.state),
                      !Task.isCancelled, layoutThumbnailRequest(layout) == request else { return }
                layoutThumbnails[layout] = image
                layoutThumbnailKeys[layout] = request
            }
            await loadThumbnails()
            await loadFrameThumbnails()
        }
    }

    @discardableResult
    func selectLayout(_ layout: KadrioCollageLayout) -> Bool {
        let ids = sourceIDs(for: layout.photoCount)
        guard ids.count == layout.photoCount else { return false }
        guard state.collageLayout != layout || snapshot.sourceIDs != ids || !state.collage else {
            tool = .collage
            return true
        }
        var next = snapshot
        next.sourceIDs = ids
        next.state.sourceCount = ids.count
        next.state.collage = true
        next.state.collageLayout = layout
        next.state.placements = placements(for: ids)
        if !state.collage {
            next.state.freeRatio = 0.8
            next.state.ratio = .free
            next.state.cropRatioInverted = false
            next.state.crop = KadrioPlacement()
        }
        next.tool = .collage
        apply(next)
        return true
    }

    func addSources(_ additions: [KadrioSource], layout: KadrioCollageLayout? = nil) {
        let existing = layout.map { sourceIDs(for: $0.photoCount) } ?? snapshot.sourceIDs
        var selected = Set(existing)
        let additions = Array(additions.filter { selected.insert($0.id).inserted }
            .prefix(max(0, (layout?.photoCount ?? 4) - existing.count)))
        guard !additions.isEmpty else {
            if let layout { selectLayout(layout) }
            return
        }
        var retained = Set(sources.map(\.id))
        sources += additions.filter { retained.insert($0.id).inserted }
        var next = snapshot
        next.sourceIDs = existing + additions.map(\.id)
        next.state.sourceCount = next.sourceIDs.count
        let selectedLayout = layout.flatMap { $0.photoCount <= next.sourceIDs.count ? $0 : nil }
            ?? KadrioCollageLayout.initial(for: next.sourceIDs.count)
        next.state.collageLayout = selectedLayout
        next.state.collage = next.sourceIDs.count >= 2
        next.state.placements = placements(for: next.sourceIDs)
        next.state.freeRatio = 0.8
        next.state.ratio = .free
        next.state.cropRatioInverted = false
        next.state.crop = KadrioPlacement()
        next.tool = next.state.collage ? .collage : tool
        apply(next)
    }

    func finish() {
        previewTask?.cancel()
        layoutThumbnailTask?.cancel()
        let sources = sources
        Task { await KadrioImageProcessing.shared.clean(sources) }
    }
}
