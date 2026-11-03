import SwiftUI


struct KadrioEditorPresentation: UIViewControllerRepresentable {
    @Binding var request: KadrioEditorRequest?
    @EnvironmentObject private var app: KadrioAppState

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> KadrioSheetPresenter {
        let controller = KadrioSheetPresenter()
        context.coordinator.presenter = controller
        controller.onAppear = { [weak coordinator = context.coordinator] in coordinator?.update() }
        return controller
    }

    func updateUIViewController(_ controller: KadrioSheetPresenter, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update()
    }

    static func dismantleUIViewController(_ controller: KadrioSheetPresenter, coordinator: Coordinator) {
        controller.onAppear = nil
        coordinator.cancelPendingPresentation()
        coordinator.host?.dismiss(animated: false)
    }

    @MainActor
    final class Coordinator {
        var parent: KadrioEditorPresentation
        weak var presenter: KadrioSheetPresenter?
        var host: UIHostingController<AnyView>?
        private var presentationTask: Task<Void, Never>?
        private var presentationRevision = 0

        init(parent: KadrioEditorPresentation) { self.parent = parent }

        func update() {
            guard parent.request != nil else {
                cancelPendingPresentation()
                close()
                return
            }
            guard host == nil, presentationTask == nil else { return }
            presentationRevision += 1
            let revision = presentationRevision
            presentationTask = Task { [weak self] in
                await Task.yield()
                while !Task.isCancelled {
                    guard let self, presentationRevision == revision else { return }
                    guard parent.request != nil else { presentationTask = nil; return }
                    if presentIfReady() { presentationTask = nil; return }
                    do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
                }
            }
        }

        func cancelPendingPresentation() {
            presentationRevision += 1
            presentationTask?.cancel()
            presentationTask = nil
        }

        private func presentIfReady() -> Bool {
            guard let request = parent.request, host == nil,
                  let presenter, presenter.viewIfLoaded?.window != nil else { return false }
            var presenting: UIViewController = presenter
            while let ancestor = presenting.parent { presenting = ancestor }
            guard presenting.presentedViewController == nil,
                  presenting.transitionCoordinator == nil,
                  !presenting.isBeingPresented, !presenting.isBeingDismissed else { return false }
            let editor = KadrioEditorView(request: request, onClose: { [weak self] in self?.close() })
                .environmentObject(parent.app).tint(.black).buttonStyle(KadrioPressButtonStyle())
            let host = UIHostingController(rootView: AnyView(editor))
            host.safeAreaRegions = .container
            host.overrideUserInterfaceStyle = .light
            host.modalPresentationStyle = .fullScreen
            self.host = host
            presenting.present(host, animated: true)
            return true
        }

        private func close() {
            guard let host, !host.isBeingDismissed else { return }
            host.view.endEditing(true)
            host.dismiss(animated: true) { [weak self] in
                self?.host = nil
                self?.parent.request = nil
            }
        }
    }
}
