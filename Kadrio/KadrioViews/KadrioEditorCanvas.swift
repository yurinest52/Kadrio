import SwiftUI

struct KadrioEditorCanvas: View {
    @ObservedObject var model: KadrioEditorModel
    @State private var draggedImage: UIImage?
    @GestureState private var dividerActive = false
    @State private var comparing = false
    @State private var draggedSourceID: UUID?
    @State private var dropTarget: Int?
    @State private var dragLocation = CGPoint.zero
    @GestureState private var reordering = false
    @GestureState private var cropPanActive = false
    @GestureState private var cropZoomActive = false
    @GestureState private var freeCropActive = false
    @GestureState private var collageGestureActive = false

    var body: some View {
        GeometryReader { geometry in
            if let image = comparing ? model.comparisonPreview ?? model.preview : model.preview {
                let imageSize = model.previewDisplaySize == .zero ? image.size : model.previewDisplaySize
                let scale = max(
                    0,
                    min(
                        max(0, geometry.size.width) / max(1, imageSize.width),
                        max(0, geometry.size.height) / max(1, imageSize.height)))
                let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                ZStack(alignment: .center) {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFit().frame(width: size.width, height: size.height)
                        .clipped()
                    if model.tool == .crop {
                        cropGrid(size: size)
                            .contentShape(Rectangle())
                            .gesture(panGesture(size: size))
                            .simultaneousGesture(zoomGesture())
                        if model.state.ratio == .free {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").font(
                                .system(size: 15, weight: .bold)
                            ).padding(10).background(.white, in: Circle()).shadow(radius: 3)
                                .offset(x: size.width / 2 - 19, y: size.height / 2 - 19)
                                .gesture(
                                    DragGesture(minimumDistance: 1).updating($freeCropActive) { _, active, _ in active = true }.onChanged { value in
                                        model.updateFreeCrop(translation: value.translation, previewSize: size)
                                    }.onEnded { _ in model.endFreeCrop() }
                                )
                        }
                    } else if model.tool == .collage, let state = model.previewState,
                              state.collage, model.activeSourceCount >= 2,
                              model.previewSourceIDs == model.activeSources.map(\.id) {
                        let geometry = KadrioCollageGeometry(state: state, count: model.activeSourceCount, previewSize: size)
                        Color.clear.contentShape(Rectangle()).frame(width: size.width, height: size.height)
                            .gesture(collageInteraction(geometry: geometry, size: size))
                            .simultaneousGesture(collageSelection(geometry: geometry))
                            .accessibilityLabel(kadrioText("collage"))
                            .accessibilityHint(kadrioText("collage.gesture"))
                            .overlay(alignment: .topLeading) {
                                collageOverlay(geometry: geometry, size: size)
                                    .frame(width: size.width, height: size.height).clipped()
                                    .animation(.easeOut(duration: 0.12), value: dropTarget)
                                    .animation(.easeOut(duration: 0.12), value: draggedSourceID)
                                    .transaction { $0.disablesAnimations = false }
                            }
                            .coordinateSpace(name: "KadrioCollageCanvas")
                    } else if model.tool == .filters {
                        Color.clear.contentShape(Rectangle()).frame(width: size.width, height: size.height)
                            .onLongPressGesture(
                                minimumDuration: 0.05, maximumDistance: 50, pressing: { comparing = $0 }, perform: {})
                    }
                }.frame(width: size.width, height: size.height).position(
                    x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
            } else {
                Group {
                    switch model.previewLoadState {
                    case .loading:
                        ProgressView()
                    case .failure:
                        VStack(spacing: 14) {
                            Text(kadrioText("preview.renderFailed"))
                                .font(.system(size: 15)).foregroundStyle(Color.kadrioSecondary)
                                .multilineTextAlignment(.center)
                            Button(kadrioText("retry"), action: model.retryPreview)
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 20).frame(minHeight: 44)
                                .background(.black, in: Capsule())
                                .disabled(model.isRenderingPreview)
                        }.padding(20)
                    case .idle, .success:
                        Color.clear
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            Color.clear.contentShape(Rectangle()).onTapGesture { model.selectedCollageSourceID = nil }
        }
        .onChange(of: dividerActive) { _, active in
            if !active { model.endCollageDivider() }
        }
        .onChange(of: collageGestureActive) { _, active in
            if !active { model.endCollageGesture() }
        }
        .onChange(of: reordering) { _, active in
            if !active { draggedSourceID = nil; draggedImage = nil; dropTarget = nil }
        }
        .onChange(of: cropPanActive || cropZoomActive || freeCropActive) { _, active in
            if !active { model.endCropGestures() }
        }
    }

    private func cellPath(_ index: Int, geometry: KadrioCollageGeometry) -> Path {
        Path(roundedRect: geometry.cells[index], cornerRadius: KadrioGeometry.collageCornerRadius(KadrioGeometry.collageSize(preview: true)))
            .applying(geometry.canvasToView)
    }

    private func collageContentMask(_ geometry: KadrioCollageGeometry) -> Path {
        Path(roundedRect: geometry.contentRect, cornerRadius: geometry.contentRadius)
            .applying(geometry.outputToView)
    }

    @ViewBuilder
    private func collageOverlay(geometry: KadrioCollageGeometry, size: CGSize) -> some View {
        if let id = model.selectedCollageSourceID,
           let index = model.activeSources.firstIndex(where: { $0.id == id }), geometry.cells.indices.contains(index) {
            cellPath(index, geometry: geometry).stroke(.black.opacity(0.85), lineWidth: 3)
                .overlay { cellPath(index, geometry: geometry).stroke(.white, lineWidth: 1) }
                .mask { collageContentMask(geometry) }
                .allowsHitTesting(false)
        }
        if let id = draggedSourceID,
           let index = model.activeSources.firstIndex(where: { $0.id == id }), geometry.cells.indices.contains(index) {
            cellPath(index, geometry: geometry).fill(.black.opacity(0.15))
                .mask { collageContentMask(geometry) }.allowsHitTesting(false)
        }
        if let target = dropTarget, geometry.cells.indices.contains(target) {
            cellPath(target, geometry: geometry).fill(.white.opacity(0.2))
                .overlay { cellPath(target, geometry: geometry).stroke(.black.opacity(0.9), lineWidth: 5) }
                .overlay { cellPath(target, geometry: geometry).stroke(.white, lineWidth: 2) }
                .mask { collageContentMask(geometry) }
                .allowsHitTesting(false)
        }
        if draggedSourceID == nil {
            ForEach(KadrioCollageDivider.allCases) { divider in
                if let canvasPoint = geometry.dividerPoint(divider) {
                    let point = canvasPoint.applying(geometry.canvasToView)
                    if geometry.containsContent(point) {
                        dividerHandle(divider, geometry: geometry).position(point)
                    }
                }
            }
        }
        if let draggedImage {
            Image(uiImage: draggedImage).resizable().scaledToFit()
                .frame(width: 72, height: 88).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8)).shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                .position(dragLocation).allowsHitTesting(false)
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }
    }

    private func dividerHandle(_ divider: KadrioCollageDivider, geometry: KadrioCollageGeometry) -> some View {
        let transform = geometry.canvasToView
        let angle = divider == .vertical ? atan2(transform.b, transform.a) : atan2(transform.d, transform.c)
        return Image(systemName: "arrow.left.and.right").font(.system(size: 11, weight: .semibold))
            .rotationEffect(.radians(angle)).frame(width: 30, height: 24)
            .background(.white, in: Capsule()).overlay { Capsule().strokeBorder(.black.opacity(0.2), lineWidth: 1) }
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .accessibilityLabel(kadrioText("collage.resize"))
            .highPriorityGesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("KadrioCollageCanvas"))
                .updating($dividerActive) { _, active, _ in active = true }
                .onChanged { model.updateCollageDivider(divider, translation: $0.translation, geometry: geometry) }
                .onEnded { _ in model.endCollageDivider() })
    }

    private func dragThumbnail(index: Int, geometry: KadrioCollageGeometry) -> UIImage? {
        guard let image = model.preview?.cgImage else { return nil }
        let bounds = geometry.cells[index].applying(geometry.canvasToView)
            .intersection(CGRect(origin: .zero, size: geometry.previewSize))
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
        let rect = CGRect(x: bounds.minX * CGFloat(image.width) / geometry.previewSize.width,
                          y: bounds.minY * CGFloat(image.height) / geometry.previewSize.height,
                          width: bounds.width * CGFloat(image.width) / geometry.previewSize.width,
                          height: bounds.height * CGFloat(image.height) / geometry.previewSize.height).integral
        return image.cropping(to: rect).map { UIImage(cgImage: $0) }
    }

    private func cropGrid(size: CGSize) -> some View {
        Path { path in
            let rect = CGRect(origin: .zero, size: size)
            path.addRect(rect.insetBy(dx: 1, dy: 1))
            for step in 1...2 {
                let fraction = CGFloat(step) / 3
                path.move(to: CGPoint(x: size.width * fraction, y: 0))
                path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                path.move(to: CGPoint(x: 0, y: size.height * fraction))
                path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
            }
        }.stroke(.white.opacity(0.75), lineWidth: 1).frame(width: size.width, height: size.height)
    }

    private func collageSelection(geometry: KadrioCollageGeometry) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            guard !reordering, !collageGestureActive, !dividerActive else { return }
            let tappedSourceID = geometry.photo(at: value.location).flatMap { index in
                model.activeSources.indices.contains(index) ? model.activeSources[index].id : nil
            }
            model.selectedCollageSourceID = model.selectedCollageSourceID == tappedSourceID ? nil : tappedSourceID
        }
    }

    private func collageInteraction(geometry: KadrioCollageGeometry, size: CGSize) -> some Gesture {
        return collageReordering(geometry: geometry)
            .exclusively(before: collageManipulation(geometry: geometry, size: size))
    }

    private func collageReordering(geometry: KadrioCollageGeometry) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4, maximumDistance: 8)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($reordering) { value, active, _ in
                if case .second(true, _) = value { active = true }
            }
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if draggedSourceID == nil {
                    guard let index = geometry.photo(at: drag.startLocation), model.activeSources.indices.contains(index) else { return }
                    draggedSourceID = model.activeSources[index].id
                    draggedImage = dragThumbnail(index: index, geometry: geometry)
                    dragLocation = drag.location
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                dragLocation = drag.location
                dropTarget = geometry.photo(at: drag.location).flatMap { index in
                    model.activeSources.indices.contains(index) && model.activeSources[index].id != draggedSourceID ? index : nil
                }
            }.onEnded { value in
                if case .second(true, let drag?) = value,
                   let id = draggedSourceID ?? geometry.photo(at: drag.startLocation).flatMap({ index in
                       model.activeSources.indices.contains(index) ? model.activeSources[index].id : nil
                   }),
                   let target = geometry.photo(at: drag.location), model.activeSources.indices.contains(target) {
                    model.swapSources(id, model.activeSources[target].id)
                }
                draggedSourceID = nil
                draggedImage = nil
                dropTarget = nil
            }
    }

    private func collageManipulation(geometry: KadrioCollageGeometry, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .simultaneously(with: MagnifyGesture())
            .updating($collageGestureActive) { _, active, _ in active = true }
            .onChanged { value in
                let zoomStart = value.second.map { CGPoint(x: $0.startAnchor.x * size.width, y: $0.startAnchor.y * size.height) }
                model.updateCollageGesture(geometry: geometry, previewSize: size,
                    panStart: value.first?.startLocation, translation: value.first?.translation,
                    magnification: value.second.map { Double($0.magnification) }, zoomStart: zoomStart)
            }.onEnded { _ in model.endCollageGesture() }
    }

    private func panGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($cropPanActive) { _, active, _ in active = true }
            .onChanged { model.updateCropPan(translation: $0.translation, previewSize: size) }
            .onEnded { _ in model.endCropPan() }
    }

    private func zoomGesture() -> some Gesture {
        MagnificationGesture()
            .updating($cropZoomActive) { _, active, _ in active = true }
            .onChanged { model.updateCropZoom(magnification: Double($0)) }
            .onEnded { _ in model.endCropZoom() }
    }
}
