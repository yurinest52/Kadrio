import PhotosUI
import SwiftUI

struct KadrioEditorView: View {
    @EnvironmentObject private var app: KadrioAppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: KadrioEditorModel
    @State private var discard = false
    @State private var showPhotoLimit = false
    @State private var showColor = false
    @State private var showPicker = false
    @State private var pendingLayout: KadrioCollageLayout?
    @State private var replacementSourceID: UUID?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var savedWork: KadrioWork?
    @State private var savedBanner = false
    @State private var savingRequest = false
    @State private var saveSpinner = false
    @State private var share: KadrioShareItem?

    init(request: KadrioEditorRequest) { _model = StateObject(wrappedValue: KadrioEditorModel(request: request)) }

    var body: some View {
        NavigationStack {
            preview
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .accessibilityIdentifier("KadrioEditorPreview")
                .safeAreaInset(edge: .top, spacing: 0) {
                    header.padding(.top, 4).padding(.bottom, 4).background(Color.kadrioBackground)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 12) {
                        controls.padding(.horizontal, 16)
                        toolBar.padding(.bottom, 12).background(.white)
                    }.padding(.top, 4)
                }
                .background(Color.kadrioBackground.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
        }
        .modifier(KadrioScreenEntrance())
        .disabled(savingRequest || app.saving || importing)
        .interactiveDismissDisabled(model.dirty || app.saving || savingRequest)
        .sheet(isPresented: $showColor, onDismiss: model.endContinuousEditing) {
            KadrioFrameColorView(
                color: model.editingBinding(for: \.frameColor), editingChanged: model.sliderEditingChanged)
        }
        .fullScreenCover(isPresented: $app.showPaywall) {
            KadrioPaywallView {
                app.showPaywall = false
            }
        }
        .sheet(item: $share) { KadrioShareSheet(items: [$0.url]) }
        .photosPicker(
            isPresented: $showPicker, selection: $photoItems,
            maxSelectionCount: replacementSourceID == nil ? max(1, pendingLayout.map { model.missingSourceCount(for: $0) } ?? (4 - model.activeSourceCount)) : 1, matching: .images,
            preferredItemEncoding: .current
        )
        .alert(kadrioText("discard.title"), isPresented: $discard) {
            Button(kadrioText("keepEditing"), role: .cancel) {}
            Button(kadrioText("discard"), role: .destructive) { closeEditor() }
        } message: {
            Text(kadrioText("discard.message"))
        }
        .modifier(KadrioErrorModifier(app: app, active: !app.showPaywall))
        .overlay {
            if importing {
                Color.black.opacity(0.12).ignoresSafeArea().overlay {
                    ProgressView(kadrioText("loading")).padding(24).background(
                        .regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        .overlay {
            if showPhotoLimit {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                        .onTapGesture { showPhotoLimit = false }
                    VStack(spacing: 14) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 25, weight: .light))
                            .frame(width: 56, height: 56)
                            .background(Color.kadrioBackground, in: Circle())
                        Text(kadrioText("collage.limit.title"))
                            .font(.system(size: 20, weight: .bold))
                        Text(kadrioText("collage.limit.message"))
                            .font(.system(size: 14)).foregroundStyle(Color.kadrioSecondary)
                        KadrioPrimaryButton(title: kadrioText("ok")) { showPhotoLimit = false }
                            .padding(.top, 6)
                    }
                    .multilineTextAlignment(.center)
                    .padding(24).frame(maxWidth: 320)
                    .background(.white, in: RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
                    .padding(.horizontal, 24)
                    .accessibilityAddTraits(.isModal)
                }.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showPhotoLimit)
        .task {
            model.updatePreview()
        }
        .task(id: savingRequest) {
            guard savingRequest else { return }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard !Task.isCancelled, savingRequest else { return }
            saveSpinner = true
        }
        .task(id: savedWork?.id) {
            guard savedWork != nil else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation { savedBanner = false }
        }
        .onChange(of: model.renderError) { _, message in
            if let message {
                app.errorMessage = message
                model.renderError = nil
            }
        }
        .onChange(of: photoItems) { _, items in if !items.isEmpty { importMore(items) } }
    }

    private var header: some View {
        KadrioEditorHeader(model: model, isSaving: app.saving, isImporting: importing,
            isSaveRequested: savingRequest, showSaveSpinner: saveSpinner,
            close: { if model.dirty { discard = true } else { closeEditor() } }, save: save)
    }

    private var controls: some View {
        KadrioEditorControls(model: model, isBusy: app.saving || importing,
            onSelectLayout: selectLayout, onAddPhotos: addPhotos, onReplacePhoto: {
                guard !importing, !showPicker, let id = model.selectedCollageSourceID,
                      model.activeSources.contains(where: { $0.id == id }) else { return }
                photoItems = []
                replacementSourceID = id
                pendingLayout = nil
                showPicker = true
            }, onFrameColor: { showColor = true })
    }

    private var toolBar: some View {
        KadrioEditorToolBar(model: model, isBusy: app.saving || importing, select: selectTool)
    }

    private var preview: some View {
        KadrioEditorCanvas(model: model)
        .overlay(alignment: .top) {
            if savedBanner {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kadrioText("savedToPhotos")).font(.system(size: 12, weight: .semibold))
                        Text(kadrioFormat("tokens.remaining", app.ledger.tokens)).font(.system(size: 10))
                            .foregroundStyle(Color.kadrioSecondary)
                    }
                    Spacer()
                    Button(kadrioText("share")) {
                        if let work = savedWork { share = KadrioShareItem(url: app.workURL(work)) }
                    }.font(.system(size: 12, weight: .medium)).padding(9).background(
                        Color.kadrioBackground, in: Capsule())
                }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 17)).shadow(
                    color: .black.opacity(0.12), radius: 10, y: 4
                ).padding(.top, 3).transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func addPhotos() {
        guard model.activeSourceCount < 4 else { showPhotoLimit = true; return }
        pendingLayout = nil
        replacementSourceID = nil
        showPicker = true
    }

    private func selectTool(_ tool: KadrioTool) {
        if tool == .collage, !model.state.collage {
            pendingLayout = nil
            replacementSourceID = nil
            if !model.selectLayout(.columns) { showPicker = true }
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) { model.selectTool(tool) }
    }

    private func selectLayout(_ layout: KadrioCollageLayout) {
        replacementSourceID = nil
        let missing = model.missingSourceCount(for: layout)
        guard missing <= 0 else {
            pendingLayout = layout
            showPicker = true
            return
        }
        pendingLayout = nil
        model.selectLayout(layout)
    }

    private func importMore(_ items: [PhotosPickerItem]) {
        guard !importing else { return }
        importing = true
        let requestedLayout = pendingLayout
        let replacement = replacementSourceID
        Task {
            var sources: [KadrioSource] = []
            defer {
                importing = false
                photoItems = []
                replacementSourceID = nil
            }
            do {
                for item in items.prefix(replacement == nil ? items.count : 1) {
                    guard let file = try await item.loadTransferable(type: KadrioImportFile.self) else {
                        throw KadrioError.invalidImage
                    }
                    defer { try? FileManager.default.removeItem(at: file.url) }
                    sources.append(try await KadrioImageProcessing.shared.importSource(url: file.url))
                }
                if let replacement, let source = sources.first {
                    if !model.replaceSource(replacement, with: source) {
                        await KadrioImageProcessing.shared.clean(sources)
                    }
                    return
                }
                model.addSources(sources, layout: requestedLayout)
                pendingLayout = nil
                if let layout = requestedLayout {
                    let missing = layout.photoCount - model.activeSourceCount
                    if missing > 0 {
                        app.errorMessage = kadrioFormat("collage.addPhotos", missing)
                    }
                }
            } catch {
                await KadrioImageProcessing.shared.clean(sources)
                app.present(error)
            }
        }
    }

    private func closeEditor() {
        model.finish()
        dismiss()
    }

    private func save() {
        guard !savingRequest, !app.saving, !importing, model.activeSourceCount > 0 else { return }
        guard !model.isCurrentResultSaved else { return }
        guard app.ledger.tokens > 0 else {
            app.showPaywall = true
            return
        }
        if model.tool == .collage, model.activeSourceCount < 2 {
            app.present(KadrioError.collageCount)
            return
        }
        let sources = model.activeSources
        let snapshot = model.snapshotForSaving()
        savingRequest = true
        saveSpinner = false
        savedBanner = false
        Task {
            defer {
                savingRequest = false
                saveSpinner = false
            }
            if let work = await app.save(sources: sources, state: snapshot.state, tool: snapshot.tool) {
                savedWork = work
                model.markSaved(snapshot)
                withAnimation { savedBanner = true }
            }
        }
    }
}
