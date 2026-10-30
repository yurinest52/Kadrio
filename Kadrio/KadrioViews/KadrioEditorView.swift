import SwiftUI
import PhotosUI

struct KadrioEditorView: View {
    @EnvironmentObject private var app: KadrioAppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: KadrioEditorModel
    @State private var discard = false
    @State private var returnHomeAfterPaywall = false
    @State private var comparing = false
    @State private var showColor = false
    @State private var showPicker = false
    @State private var pendingLayout: KadrioCollageLayout?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var savedWork: KadrioWork?
    @State private var savedBanner = false
    @State private var share: KadrioShareItem?
    @State private var gesturePlacement: KadrioPlacement?
    @State private var gestureZoom: Double?
    @State private var freeRatioStart: Double?
    @State private var freeSizeStart: CGSize?

    init(request: KadrioEditorRequest) { _model = StateObject(wrappedValue: KadrioEditorModel(request: request)) }

    var body: some View {
        VStack(spacing: 12) {
            header
            preview.padding(.horizontal, 20).accessibilityIdentifier("KadrioEditorPreview")
            controls.padding(.horizontal, 16)
            toolBar
        }
        .padding(.top, 5).background(Color.kadrioBackground)
        .interactiveDismissDisabled(model.dirty || app.saving)
        .sheet(isPresented: $showColor) { KadrioFrameColorView(color: Binding(get: { model.state.frameColor }, set: { model.state.frameColor = $0; model.updatePreview() })) }
        .fullScreenCover(isPresented: $app.showPaywall, onDismiss: {
            if returnHomeAfterPaywall { closeEditor() }
        }) {
            KadrioPaywallView {
                returnHomeAfterPaywall = true
                app.showPaywall = false
            }
        }
        .sheet(item: $share) { KadrioShareSheet(items: [$0.url]) }
        .photosPicker(isPresented: $showPicker, selection: $photoItems, maxSelectionCount: max(1, (pendingLayout?.photoCount ?? 4) - model.sources.count), matching: .images, preferredItemEncoding: .current)
        .alert(kadrioText("discard.title"), isPresented: $discard) {
            Button(kadrioText("keepEditing"), role: .cancel) {}
            Button(kadrioText("discard"), role: .destructive) { closeEditor() }
        } message: { Text(kadrioText("discard.message")) }
        .modifier(KadrioErrorModifier(app: app, active: !app.showPaywall))
        .overlay {
            if app.saving || importing { Color.black.opacity(0.12).ignoresSafeArea().overlay { ProgressView(kadrioText(app.saving ? "saving" : "loading")).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
        }
        .task { model.updatePreview(); await model.loadThumbnails() }
        .onChange(of: model.renderError) { _, message in if let message { app.errorMessage = message; model.renderError = nil } }
        .onChange(of: photoItems) { _, items in if !items.isEmpty { importMore(items) } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            KadrioCircleButton(symbol: "xmark", label: kadrioText("close")) { if model.dirty { discard = true } else { closeEditor() } }.accessibilityIdentifier("KadrioEditorClose")
            Spacer()
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 42, height: 44) }.disabled(model.undoStates.isEmpty).accessibilityLabel(kadrioText("undo"))
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 42, height: 44) }.disabled(model.redoStates.isEmpty).accessibilityLabel(kadrioText("redo"))
            Spacer()
            Button { save() } label: {
                ZStack {
                    Text(kadrioText("save")).opacity(model.rendering ? 0 : 1)
                    if model.rendering { ProgressView().tint(.white).accessibilityHidden(true) }
                }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 20).frame(height: 32).background(.black, in: Capsule()).frame(minHeight: 44)
            }.accessibilityLabel(kadrioText("save")).accessibilityIdentifier("KadrioEditorSave").disabled(app.saving || importing || model.preview == nil || model.rendering)
        }.padding(.horizontal, 16).disabled(app.saving)
    }

    private var preview: some View {
        GeometryReader { geometry in
            if let image = comparing ? model.original ?? model.preview : model.preview {
                let scale = max(0, min(max(0, geometry.size.width) / max(1, image.size.width), max(0, geometry.size.height) / max(1, image.size.height)))
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                ZStack(alignment: .center) {
                    Image(uiImage: image).resizable().scaledToFit().frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: model.state.frame == .none ? 10 : 3))
                    if model.tool == .crop {
                        cropGrid(size: size)
                            .contentShape(Rectangle())
                            .gesture(panGesture(index: nil, size: size))
                            .simultaneousGesture(zoomGesture(index: nil))
                        if model.state.ratio == .free {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 15, weight: .bold)).padding(10).background(.white, in: Circle()).shadow(radius: 3)
                                .offset(x: size.width / 2 - 19, y: size.height / 2 - 19)
                                .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                                    if freeRatioStart == nil { freeRatioStart = model.state.freeRatio; freeSizeStart = size; model.checkpoint() }
                                    let initial = freeSizeStart ?? size
                                    let width = max(60, initial.width + value.translation.width)
                                    let height = max(60, initial.height + value.translation.height)
                                    model.state.freeRatio = min(3, max(0.25, (freeRatioStart ?? 0.8) * (width / max(1, initial.width)) / (height / max(1, initial.height))))
                                    model.updatePreview()
                                }.onEnded { _ in freeRatioStart = nil; freeSizeStart = nil })
                        }
                    } else if model.tool == .collage, model.sources.count >= 2 {
                        let cells = KadrioGeometry.cells(count: model.state.sourceCount, layout: model.state.layout, size: size, spacing: model.state.spacing)
                        ForEach(Array(cells.enumerated()), id: \.offset) { index, rect in
                            Color.clear.contentShape(Rectangle()).frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .gesture(panGesture(index: index, size: rect.size))
                                .simultaneousGesture(zoomGesture(index: index))
                        }
                    } else if model.tool == .filters {
                        Color.clear.contentShape(Rectangle()).frame(width: size.width, height: size.height)
                            .onLongPressGesture(minimumDuration: 0.05, maximumDistance: 50, pressing: { comparing = $0 }, perform: {})
                    }
                }.frame(width: size.width, height: size.height).position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .overlay(alignment: .top) {
            if savedBanner {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kadrioText("savedToPhotos")).font(.system(size: 12, weight: .semibold))
                        Text(kadrioFormat("tokens.remaining", app.ledger.tokens)).font(.system(size: 10)).foregroundStyle(Color.kadrioSecondary)
                    }
                    Spacer()
                    Button(kadrioText("share")) { if let work = savedWork { share = KadrioShareItem(url: app.workURL(work)) } }.font(.system(size: 12, weight: .medium)).padding(9).background(Color.kadrioBackground, in: Capsule())
                }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 17)).shadow(color: .black.opacity(0.12), radius: 10, y: 4).padding(.top, 3).transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func cropGrid(size: CGSize) -> some View {
        Path { path in
            let rect = CGRect(origin: .zero, size: size)
            path.addRect(rect.insetBy(dx: 1, dy: 1))
            for step in 1...2 {
                let fraction = CGFloat(step) / 3
                path.move(to: CGPoint(x: size.width * fraction, y: 0)); path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                path.move(to: CGPoint(x: 0, y: size.height * fraction)); path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
            }
        }.stroke(.white.opacity(0.75), lineWidth: 1).frame(width: size.width, height: size.height)
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 12) {
            switch model.tool {
            case .collage: collageControls
            case .crop: cropControls
            case .filters: filterControls
            case .frames: frameControls
            }
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 23)).kadrioCardShadow().disabled(app.saving || importing)
    }

    private var collageControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(kadrioText("layout")).font(.system(size: 12)).foregroundStyle(Color.kadrioSecondary)
                Spacer()
            }
            HStack(spacing: 10) {
                ForEach(KadrioCollageLayout.allCases) { layout in
                    Button { selectLayout(layout) } label: {
                        KadrioLayoutIcon(layout: layout)
                            .frame(width: 30, height: 32)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundStyle(model.state.layout == layout.rawValue ? .black : .gray.opacity(0.5))
                            .background(model.state.layout == layout.rawValue ? .white : Color.kadrioBackground, in: RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(model.state.layout == layout.rawValue ? .black : .clear, lineWidth: 1.5) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kadrioFormat("layout.number", layout.rawValue + 1))
                    .accessibilityHint(kadrioText("collage.gesture"))
                }
                Button { pendingLayout = nil; showPicker = true } label: {
                    Image(systemName: "plus").font(.system(size: 20, weight: .light)).frame(maxWidth: .infinity).frame(height: 44).background(Color.kadrioBackground, in: RoundedRectangle(cornerRadius: 12))
                }.disabled(model.sources.count >= 4).accessibilityLabel(kadrioText("addPhoto"))
            }
            parameterSlider("spacing", value: $model.state.spacing, range: 0...0.08)
            if model.sources.count < 2 { Text(kadrioText("error.collageCount")).font(.system(size: 11)).foregroundStyle(Color.kadrioSecondary) }
        }
    }

    private var cropControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(KadrioCropRatio.allCases) { ratio in
                    Button { model.change { $0.ratio = ratio; $0.crop = KadrioPlacement() } } label: {
                        VStack(spacing: 6) {
                            Image(systemName: ratio == .free ? "viewfinder" : "rectangle").font(.system(size: 18)).frame(width: 38, height: 38).background(model.state.ratio == ratio ? .black : Color.kadrioBackground, in: Circle()).foregroundStyle(model.state.ratio == ratio ? .white : .gray)
                            Text(ratio.title).font(.system(size: 10)).foregroundStyle(model.state.ratio == ratio ? .black : .gray)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                cropAction("rotate", symbol: "rotate.left") { model.change { $0.turns = ($0.turns + 1) % 4; $0.crop = KadrioPlacement(); if $0.ratio == .free { $0.freeRatio = 1 / $0.freeRatio } } }
                cropAction("flip", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right") { model.change { $0.flipped.toggle() } }
                cropAction("reset", symbol: "arrow.counterclockwise") { model.resetCrop() }
            }
        }
    }

    private func cropAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(kadrioText(title), systemImage: symbol).font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).frame(height: 34).background(Color.kadrioBackground, in: Capsule()) }.buttonStyle(.plain)
    }

    private var filterControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(KadrioFilter.allCases) { filter in
                    Button { model.change { $0.filter = filter } } label: {
                        VStack(spacing: 6) {
                            Group {
                                if let image = model.thumbnails[filter] { Image(uiImage: image).resizable().scaledToFill() }
                                else { Color.kadrioBackground }
                            }.frame(width: 43, height: 43).clipShape(Circle()).padding(3).overlay(Circle().stroke(model.state.filter == filter ? .black : .clear, lineWidth: 1.5))
                            Text(filter.title).font(.system(size: 9)).foregroundStyle(model.state.filter == filter ? .black : .gray).lineLimit(1).minimumScaleFactor(0.7)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }
            parameterSlider("intensity", value: $model.state.intensity, range: 0...1)
        }
    }

    private var frameControls: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 13) {
                    ForEach(KadrioFrame.allCases) { frame in
                        Button {
                            model.change { value in
                                value.frame = frame
                                if frame == .black { value.frameColor = KadrioColor(red: 0.06, green: 0.06, blue: 0.06) }
                                else if frame == .white || frame == .polaroid { value.frameColor = KadrioColor() }
                            }
                        } label: {
                            VStack(spacing: 5) {
                                frameThumbnail(frame).frame(width: 43, height: 43).padding(3).overlay(RoundedRectangle(cornerRadius: 9).stroke(model.state.frame == frame ? .black : .clear, lineWidth: 1.5))
                                Text(frame.title).font(.system(size: 9)).foregroundStyle(model.state.frame == frame ? .black : .gray)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }.scrollIndicators(.hidden)
            HStack(spacing: 10) {
                ForEach(Array(KadrioFrameColorView.presets.prefix(6).enumerated()), id: \.offset) { _, color in
                    Button { model.change { $0.frameColor = color } } label: { Circle().fill(Color(red: color.red, green: color.green, blue: color.blue)).frame(width: 20, height: 20).overlay(Circle().stroke(.gray.opacity(0.25), lineWidth: 0.5)) }.accessibilityLabel(color.hex)
                }
                Button { model.checkpoint(); showColor = true } label: { Image(systemName: "paintpalette.fill").font(.system(size: 19)).foregroundStyle(.blue).frame(width: 32, height: 32) }.accessibilityLabel(kadrioText("frameColor"))
                Slider(value: $model.state.thickness, in: 0.01...0.14, onEditingChanged: { editing in if editing { model.checkpoint() } else { model.updatePreview() } }).onChange(of: model.state.thickness) { model.updatePreview() }.accessibilityLabel(kadrioText("thickness"))
            }
            Text(kadrioText("thickness")).font(.system(size: 10)).foregroundStyle(Color.kadrioSecondary).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func frameThumbnail(_ frame: KadrioFrame) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: frame == .rounded ? 10 : 5).fill(frame == .black ? .black : Color.kadrioBackground)
            if frame == .none { Image(systemName: "xmark").foregroundStyle(.gray) }
            else {
                Image(uiImage: model.thumbnails[.original] ?? model.preview ?? UIImage()).resizable().scaledToFill().frame(width: frame == .double ? 27 : 32, height: frame == .polaroid ? 26 : 32).clipped().clipShape(RoundedRectangle(cornerRadius: frame == .rounded ? 8 : 1)).offset(y: frame == .polaroid ? -3 : 0)
                if frame == .double { Rectangle().stroke(.black, lineWidth: 1).padding(5) }
            }
        }
    }

    private func parameterSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(format: kadrioText("parameter.value"), kadrioText(title), Int(value.wrappedValue * 100))).font(.system(size: 10)).foregroundStyle(Color.kadrioSecondary)
            Slider(value: value, in: range, onEditingChanged: { editing in if editing { model.checkpoint() } else { model.updatePreview() } }).onChange(of: value.wrappedValue) { model.updatePreview() }.accessibilityLabel(kadrioText(title))
        }
    }

    private var toolBar: some View {
        HStack {
            ForEach(KadrioTool.allCases) { tool in
                Button {
                    if tool == .collage, model.sources.count < 2 { pendingLayout = nil; showPicker = true }
                    withAnimation(.easeInOut(duration: 0.18)) { model.tool = tool }
                } label: {
                    VStack(spacing: 5) {
                        KadrioToolIcon(tool: tool)
                            .frame(width: 22, height: 22)
                            .frame(width: 42, height: 42)
                            .foregroundStyle(model.tool == tool ? .white : Color.kadrioSecondary)
                            .background(model.tool == tool ? .black : .clear, in: Circle())
                            .shadow(color: .black.opacity(model.tool == tool ? 0.16 : 0), radius: 5, y: 3)
                            .offset(y: model.tool == tool ? -5 : 0)
                        Text(tool.title).font(.system(size: 10)).foregroundStyle(model.tool == tool ? .black : .gray)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.plain).accessibilityIdentifier("KadrioEditorTool-" + tool.rawValue)
            }
        }.padding(.horizontal, 16).padding(.bottom, 8).background(Color.white.ignoresSafeArea(edges: .bottom)).disabled(app.saving || importing)
    }

    private func panGesture(index: Int?, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2).onChanged { value in
            if gesturePlacement == nil { model.checkpoint(); gesturePlacement = index.map { model.state.placements[$0] } ?? model.state.crop }
            var placement = gesturePlacement ?? KadrioPlacement()
            placement.x = max(-1, min(1, placement.x + value.translation.width / max(1, size.width) * 2))
            placement.y = max(-1, min(1, placement.y + value.translation.height / max(1, size.height) * 2))
            if let index { model.state.placements[index] = placement } else { model.state.crop = placement }
            model.updatePreview()
        }.onEnded { _ in gesturePlacement = nil }
    }

    private func zoomGesture(index: Int?) -> some Gesture {
        MagnificationGesture().onChanged { scale in
            if gestureZoom == nil { model.checkpoint(); gestureZoom = index.map { model.state.placements[$0].zoom } ?? model.state.crop.zoom }
            let zoom = min(6, max(1, (gestureZoom ?? 1) * scale))
            if let index { model.state.placements[index].zoom = zoom } else { model.state.crop.zoom = zoom }
            model.updatePreview()
        }.onEnded { _ in gestureZoom = nil }
    }

    private func selectLayout(_ layout: KadrioCollageLayout) {
        let missing = layout.photoCount - model.sources.count
        guard missing <= 0 else { pendingLayout = layout; showPicker = true; return }
        pendingLayout = nil
        guard model.state.layout != layout.rawValue || model.state.sourceCount < layout.photoCount else { return }
        model.change { $0.layout = layout.rawValue; $0.sourceCount = max($0.sourceCount, layout.photoCount); $0.placements = Array(repeating: KadrioPlacement(), count: 4) }
    }

    private func importMore(_ items: [PhotosPickerItem]) {
        importing = true
        Task {
            var sources: [KadrioSource] = []
            defer { importing = false; photoItems = [] }
            do {
                for item in items {
                    guard let file = try await item.loadTransferable(type: KadrioImportFile.self) else { throw KadrioError.invalidImage }
                    defer { try? FileManager.default.removeItem(at: file.url) }
                    sources.append(try await KadrioImageProcessing.shared.importSource(url: file.url))
                }
                model.addSources(sources)
                if let layout = pendingLayout {
                    let missing = layout.photoCount - model.state.sourceCount
                    if missing <= 0 { selectLayout(layout) }
                    else { pendingLayout = nil; app.errorMessage = kadrioFormat("collage.addPhotos", missing) }
                }
            } catch { await KadrioImageProcessing.shared.clean(sources); app.present(error) }
        }
    }

    private func closeEditor() {
        model.finish()
        dismiss()
    }

    private func save() {
        guard app.ledger.tokens > 0 else { app.showPaywall = true; return }
        if model.tool == .collage, model.sources.count < 2 { app.present(KadrioError.collageCount); return }
        Task {
            if let work = await app.save(sources: model.sources, state: model.state, tool: model.tool) {
                savedWork = work
                model.markSaved()
                withAnimation { savedBanner = true }
                try? await Task.sleep(for: .seconds(5))
                withAnimation { savedBanner = false }
            }
        }
    }
}

struct KadrioLayoutIcon: View {
    let layout: KadrioCollageLayout
    var body: some View {
        GeometryReader { geometry in
            let cells = KadrioGeometry.cells(count: layout.photoCount, layout: layout.rawValue, size: geometry.size, spacing: 0.075)
            ForEach(Array(cells.enumerated()), id: \.offset) { _, rect in
                RoundedRectangle(cornerRadius: 2).frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            }
        }
    }
}
