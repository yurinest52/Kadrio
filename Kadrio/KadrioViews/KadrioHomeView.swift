import AVFoundation
import PhotosUI
import SwiftUI

private enum KadrioPhotoSourceChoice {
    case camera, library
}

struct KadrioHomeView: View {
    @EnvironmentObject private var app: KadrioAppState
    @State private var addPhoto = false
    @State private var photoSourceChoice: KadrioPhotoSourceChoice?
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var settings = false
    @State private var returnHomeAfterPaywall = false
    @State private var loading = false
    @State private var selectedTool: KadrioTool = .filters
    @State private var carouselTool: KadrioTool? = .collage
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var editor: KadrioEditorRequest?
    @State private var viewedWork: KadrioWork?
    @State private var deletedWork: KadrioWork?
    @State private var confirmDelete = false
    @State private var savedBanner = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button {
                            app.showPaywall = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("\(app.ledger.tokens)").fontWeight(.semibold)
                            }.font(.system(size: 15)).padding(.horizontal, 14).frame(height: 36).background(
                                .white, in: Capsule())
                        }.accessibilityIdentifier("KadrioHomeTokens").accessibilityLabel(
                            kadrioFormat("tokens.remaining", app.ledger.tokens))
                        Spacer()
                        KadrioCircleButton(symbol: "gearshape", label: kadrioText("settings")) { settings = true }
                            .accessibilityIdentifier("KadrioHomeSettings")
                    }.padding(.horizontal, 24).padding(.top, 10)
                    Text(kadrioText("appTitle")).font(.system(size: 27, weight: .bold)).tracking(-0.7).padding(
                        .horizontal, 24
                    ).padding(.top, 10)
                    carousel(width: geometry.size.width).padding(.top, 20)
                    VStack(spacing: 4) {
                        Text(kadrioText("myWorks")).font(.system(size: 20, weight: .bold))
                        Text(kadrioText("recentEdits")).font(.system(size: 12)).foregroundStyle(Color.kadrioSecondary)
                    }.frame(maxWidth: .infinity).padding(.top, 15).padding(.bottom, 18)
                    if app.ledger.works.isEmpty {
                        VStack(spacing: 11) {
                            Image(systemName: "photo").font(.system(size: 27)).foregroundStyle(.gray.opacity(0.65))
                            Text(kadrioText("works.empty")).font(.system(size: 16, weight: .semibold))
                            Text(kadrioText("works.emptyMessage")).font(.system(size: 12)).foregroundStyle(
                                Color.kadrioSecondary
                            ).multilineTextAlignment(.center).frame(maxWidth: 210)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 70)
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                                spacing: 12
                            ) {
                                ForEach(app.ledger.works) { work in
                                    Button {
                                        viewedWork = work
                                    } label: {
                                        KadrioFileImage(url: app.workURL(work, thumbnail: true)).aspectRatio(
                                            1, contentMode: .fit
                                        ).clipShape(RoundedRectangle(cornerRadius: 15))
                                    }.buttonStyle(.plain).accessibilityLabel(kadrioText("works.open"))
                                        .contextMenu {
                                            Button {
                                                saveExisting(work)
                                            } label: {
                                                Label(kadrioText("saveToPhotos"), systemImage: "square.and.arrow.down")
                                            }
                                            ShareLink(item: app.workURL(work)) {
                                                Label(kadrioText("share"), systemImage: "square.and.arrow.up")
                                            }
                                            Button(role: .destructive) {
                                                Task {
                                                    try? await Task.sleep(for: .milliseconds(350))
                                                    deletedWork = work
                                                    confirmDelete = true
                                                }
                                            } label: {
                                                Label(kadrioText("delete"), systemImage: "trash")
                                            }
                                        }
                                }
                            }.padding(.horizontal, 24).padding(.bottom, 100)
                        }.scrollIndicators(.hidden)
                    }
                }
                .overlay(alignment: .bottom) {
                    Button {
                        selectedTool = .filters
                        addPhoto = true
                    } label: {
                        Image(systemName: "plus").font(.system(size: 24, weight: .light)).foregroundStyle(.white).frame(
                            width: 62, height: 62
                        ).background(.black, in: Circle()).shadow(color: .black.opacity(0.22), radius: 8, y: 5)
                    }.accessibilityIdentifier("KadrioHomeAddPhoto").accessibilityLabel(kadrioText("addPhoto")).padding(
                        .bottom, 23)
                }
                .overlay {
                    if loading {
                        Color.black.opacity(0.1).ignoresSafeArea().overlay {
                            ProgressView(kadrioText("loading")).padding(25).background(
                                .regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }
                .overlay(alignment: .top) {
                    if savedBanner {
                        Label(kadrioText("savedToPhotos"), systemImage: "checkmark.circle.fill").font(
                            .system(size: 14, weight: .semibold)
                        ).padding().background(.white, in: Capsule()).shadow(radius: 8).padding(.top, 8)
                    }
                }
            }
            .photosPicker(
                isPresented: $showLibrary, selection: $photoItems, maxSelectionCount: selectedTool == .collage ? 4 : 1,
                matching: .images, preferredItemEncoding: .current
            )
            .background(Color.kadrioBackground)
            .navigationDestination(isPresented: $settings) { KadrioSettingsView() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .modifier(KadrioScreenEntrance())
        .overlay {
            Color.black.opacity(addPhoto ? 0.14 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .animation(.easeInOut(duration: 0.22), value: addPhoto)
        }
        .sheet(isPresented: $addPhoto, onDismiss: openSelectedPhotoSource) { photoSourceSheet }
        .fullScreenCover(isPresented: $showCamera) {
            KadrioCameraView { image in if let image { importCamera(image) } }.ignoresSafeArea()
        }
        .fullScreenCover(item: $editor) { request in KadrioEditorView(request: request) }
        .sheet(item: $viewedWork) { KadrioWorkPreviewView(work: $0) }
        .fullScreenCover(
            isPresented: Binding(get: { app.showPaywall && editor == nil }, set: { app.showPaywall = $0 }),
            onDismiss: {
                if returnHomeAfterPaywall {
                    settings = false
                    returnHomeAfterPaywall = false
                }
            }
        ) {
            KadrioPaywallView {
                returnHomeAfterPaywall = true
                app.showPaywall = false
            }
        }
        .modifier(KadrioErrorModifier(app: app, active: editor == nil && !app.showPaywall))
        .alert(kadrioText("delete.title"), isPresented: $confirmDelete, presenting: deletedWork) { work in
            Button(kadrioText("cancel"), role: .cancel) { confirmDelete = false }
            Button(kadrioText("delete"), role: .destructive) {
                confirmDelete = false
                Task { await app.delete(work) }
            }
        } message: { _ in
            Text(kadrioText("delete.message"))
        }
        .onChange(of: photoItems) { _, items in if !items.isEmpty { importPhotos(items) } }
    }

    private func carousel(width: CGFloat) -> some View {
        VStack(spacing: 13) {
            ScrollView(.horizontal) {
                HStack(spacing: -2) {
                    ForEach(KadrioTool.allCases) { tool in
                        Button {
                            selectedTool = tool
                            addPhoto = true
                        } label: {
                            Image(tool.asset).resizable().scaledToFill().frame(
                                width: (max(240, width) - 20) / 3, height: (max(240, width) - 20) / 3 * 1.32
                            ).clipped()
                                .overlay {
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom
                                    ).mask(Image(tool.asset).resizable().scaledToFill())
                                }
                                .overlay(alignment: .bottom) {
                                    Text(tool.title).font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                                        .padding(.bottom, 15).padding(.horizontal, 3).minimumScaleFactor(0.65)
                                        .lineLimit(1)
                                }.clipShape(RoundedRectangle(cornerRadius: 17)).rotationEffect(
                                    .degrees(tool == .collage ? -3 : tool == .filters ? 3 : 0))
                        }.buttonStyle(.plain).accessibilityIdentifier("KadrioHomeTool-" + tool.rawValue).id(tool)
                    }
                }.scrollTargetLayout().padding(.vertical, 10)
            }.contentMargins(.horizontal, 32, for: .scrollContent)
                .scrollClipDisabled()
                .scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned).scrollPosition(id: $carouselTool)
            HStack(spacing: 5) {
                ForEach(KadrioTool.allCases) { tool in
                    Capsule().fill(carouselTool == tool ? .black : .gray.opacity(0.25)).frame(
                        width: carouselTool == tool ? 22 : 7, height: 4)
                }
            }.accessibilityHidden(true)
        }
    }

    private var photoSourceSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(kadrioText("addPhoto")).font(.system(size: 20, weight: .bold))
                HStack(spacing: 14) {
                    sourceButton(title: "camera", subtitle: "camera.subtitle", symbol: "camera") {
                        photoSourceChoice = .camera
                        addPhoto = false
                    }
                    sourceButton(title: "photoLibrary", subtitle: "library.subtitle", symbol: "photo.on.rectangle") {
                        photoSourceChoice = .library
                        addPhoto = false
                    }
                }
            }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(kadrioText("cancel")) {
                photoSourceChoice = nil
                addPhoto = false
            }
            .font(.system(size: 15)).foregroundStyle(Color.kadrioSecondary).frame(maxWidth: .infinity).frame(height: 44)
            .accessibilityIdentifier("KadrioSourceCancel")
            .padding(.horizontal, 24).padding(.bottom, 12).background(.white)
        }
        .presentationDetents([.height(330)]).presentationDragIndicator(.visible).presentationCornerRadius(27)
    }

    private func sourceButton(title: String, subtitle: String, symbol: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(.white).frame(width: 40, height: 40)
                    .background(.black, in: Circle()).padding(.bottom, 4)
                Text(kadrioText(title)).font(.system(size: 15, weight: .semibold))
                Text(kadrioText(subtitle)).font(.system(size: 10)).foregroundStyle(Color.kadrioSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(
                Color.kadrioBackground, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier("KadrioSource-" + title)
    }

    private func openSelectedPhotoSource() {
        guard let choice = photoSourceChoice else { return }
        photoSourceChoice = nil
        switch choice {
        case .camera: Task { await openCamera() }
        case .library:
            Task { @MainActor in
                await Task.yield()
                showLibrary = true
            }
        }
    }

    private func openCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            app.present(KadrioError.cameraUnavailable)
            return
        }
        let authorized = await AVCaptureDevice.requestAccess(for: .video)
        if authorized { showCamera = true } else { app.present(KadrioError.cameraAccess) }
    }

    private func importCamera(_ image: UIImage) {
        loading = true
        Task {
            defer { loading = false }
            do {
                let source = try await KadrioImageProcessing.shared.importCamera(image)
                editor = KadrioEditorRequest(sources: [source], tool: selectedTool)
            } catch { app.present(error) }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        loading = true
        let tool = selectedTool
        Task {
            var sources: [KadrioSource] = []
            defer {
                loading = false
                photoItems = []
            }
            do {
                guard tool != .collage || items.count >= 2 else { throw KadrioError.collageCount }
                for item in items {
                    guard let file = try await item.loadTransferable(type: KadrioImportFile.self) else {
                        throw KadrioError.invalidImage
                    }
                    defer { try? FileManager.default.removeItem(at: file.url) }
                    sources.append(try await KadrioImageProcessing.shared.importSource(url: file.url))
                }
                editor = KadrioEditorRequest(sources: sources, tool: tool)
            } catch {
                await KadrioImageProcessing.shared.clean(sources)
                app.present(error)
            }
        }
    }

    private func saveExisting(_ work: KadrioWork) {
        Task {
            do {
                try await KadrioPhotoLibrary.save(app.workURL(work))
                withAnimation { savedBanner = true }
                try? await Task.sleep(for: .seconds(3))
                withAnimation { savedBanner = false }
            } catch { app.present(error) }
        }
    }
}

struct KadrioWorkPreviewView: View {
    let work: KadrioWork
    @EnvironmentObject private var app: KadrioAppState
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var saved = false
    var body: some View {
        NavigationStack {
            KadrioFileImage(url: app.workURL(work), maxPixel: 2000, mode: .fit).padding(20).background(
                Color.kadrioBackground
            )
            .navigationTitle(kadrioText("myWorks")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(kadrioText("done")) { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        saving = true
                        Task {
                            defer { saving = false }
                            do {
                                try await KadrioPhotoLibrary.save(app.workURL(work))
                                saved = true
                            } catch { app.present(error) }
                        }
                    } label: {
                        Label(kadrioText("saveToPhotos"), systemImage: "square.and.arrow.down")
                    }.disabled(saving)
                    Spacer()
                    ShareLink(item: app.workURL(work)) {
                        Label(kadrioText("share"), systemImage: "square.and.arrow.up")
                    }
                }
            }
            .alert(kadrioText("savedToPhotos"), isPresented: $saved) { Button(kadrioText("ok"), role: .cancel) {} }
            .modifier(KadrioErrorModifier(app: app))
        }
    }
}
