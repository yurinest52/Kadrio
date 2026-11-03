import SwiftUI
import UIKit

struct KadrioBottomSheet<Sheet: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let height: CGFloat
    var onDismiss: () -> Void = {}
    var dragHandleOnly = false
    var isolatesKeyboard = false
    @ViewBuilder var sheet: () -> Sheet

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> KadrioSheetPresenter {
        let controller = KadrioSheetPresenter()
        controller.onAppear = { [weak coordinator = context.coordinator] in coordinator?.update() }
        context.coordinator.presenter = controller
        return controller
    }

    func updateUIViewController(_ controller: KadrioSheetPresenter, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update()
    }

    static func dismantleUIViewController(_ controller: KadrioSheetPresenter, coordinator: Coordinator) {
        controller.onAppear = nil
        coordinator.host?.dismiss(animated: false)
    }

    final class Coordinator: NSObject, UIViewControllerTransitioningDelegate, UIGestureRecognizerDelegate {
        var parent: KadrioBottomSheet
        weak var presenter: KadrioSheetPresenter?
        var host: KadrioSheetHostingController<Sheet>?
        private var interaction: UIPercentDrivenInteractiveTransition?

        init(parent: KadrioBottomSheet) { self.parent = parent }

        func update() {
            if parent.isPresented {
                if let host {
                    host.rootView = KadrioSheetBody(content: parent.sheet())
                    return
                }
                guard let presenter, presenter.viewIfLoaded?.window != nil else { return }
                var presentingController: UIViewController = presenter
                while let ancestor = presentingController.parent { presentingController = ancestor }
                guard presentingController.presentedViewController == nil else { return }
                let host = KadrioSheetHostingController(content: parent.sheet(), avoidsKeyboard: parent.isolatesKeyboard)
                host.modalPresentationStyle = .custom
                host.transitioningDelegate = self
                host.overrideUserInterfaceStyle = .light
                host.view.backgroundColor = .white
                host.view.layer.cornerRadius = 27
                host.view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                host.view.clipsToBounds = true
                let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
                pan.delegate = self
                host.view.addGestureRecognizer(pan)
                self.host = host
                presentingController.present(host, animated: true)
            } else if let host, host.presentingViewController != nil, !host.isBeingDismissed {
                host.dismiss(animated: true)
            }
        }

        func presentationController(forPresented presented: UIViewController, presenting: UIViewController?,
                                    source: UIViewController) -> UIPresentationController? {
            let controller = KadrioSheetPresentation(presentedViewController: presented, presenting: presenting)
            controller.height = parent.height
            controller.onDismiss = { [weak self] in
                guard let self else { return }
                host = nil
                interaction = nil
                parent.isPresented = false
                parent.onDismiss()
            }
            return controller
        }

        func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                                 source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            KadrioSheetTransition(presenting: true)
        }

        func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            KadrioSheetTransition(presenting: false)
        }

        func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning)
            -> UIViewControllerInteractiveTransitioning? { interaction }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard parent.dragHandleOnly, let host else { return true }
            return touch.location(in: host.view).y <= 36
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let host, !host.isBeingPresented else { return false }
            let velocity = pan.velocity(in: host.view)
            return velocity.y > 0 && velocity.y > abs(velocity.x)
        }

        @objc private func drag(_ pan: UIPanGestureRecognizer) {
            guard let host else { return }
            let progress = min(1, max(0, pan.translation(in: host.view.superview).y / max(1, host.view.bounds.height)))
            switch pan.state {
            case .began:
                interaction = UIPercentDrivenInteractiveTransition()
                interaction?.completionCurve = .easeOut
                host.dismiss(animated: true)
            case .changed:
                interaction?.update(progress)
            case .ended:
                if progress > 0.3 || pan.velocity(in: host.view.superview).y > 700 {
                    interaction?.finish()
                } else {
                    interaction?.cancel()
                }
                interaction = nil
            case .cancelled, .failed:
                interaction?.cancel()
                interaction = nil
            default: break
            }
        }
    }
}

final class KadrioSheetPresenter: UIViewController {
    var onAppear: (() -> Void)?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppear?()
    }
}

final class KadrioSheetHostingController<Content: View>: UIViewController {
    private let contentHost: UIHostingController<KadrioSheetBody<Content>>
    private let avoidsKeyboard: Bool

    var rootView: KadrioSheetBody<Content> {
        get { contentHost.rootView }
        set { contentHost.rootView = newValue }
    }

    init(content: Content, avoidsKeyboard: Bool) {
        contentHost = UIHostingController(rootView: KadrioSheetBody(content: content))
        contentHost.safeAreaRegions = .container
        self.avoidsKeyboard = avoidsKeyboard
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        addChild(contentHost)
        guard let content = contentHost.view else { return }
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: avoidsKeyboard ? view.keyboardLayoutGuide.topAnchor : view.safeAreaLayoutGuide.bottomAnchor)
        ])
        contentHost.didMove(toParent: self)
    }
}

struct KadrioSheetBody<Content: View>: View {
    let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.gray.opacity(0.45)).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity).padding(.top, 8)
                .accessibilityHidden(true)
            content
        }
        .background(.white)
    }
}

final class KadrioSheetPresentation: UIPresentationController {
    var height: CGFloat = 400
    var onDismiss: (() -> Void)?
    private let dimming = UIView()

    override var shouldRemovePresentersView: Bool { false }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }
        let bounds = containerView.bounds
        let height = min(height + containerView.safeAreaInsets.bottom,
                         bounds.height - containerView.safeAreaInsets.top - 16)
        return CGRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height)
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        dimming.frame = containerView?.bounds ?? .zero
        if !presentedViewController.isBeingPresented, !presentedViewController.isBeingDismissed {
            presentedView?.frame = frameOfPresentedViewInContainerView
        }
    }

    override func presentationTransitionWillBegin() {
        guard let containerView else { return }
        dimming.backgroundColor = UIColor.black.withAlphaComponent(0.24)
        dimming.frame = containerView.bounds
        dimming.alpha = 0
        dimming.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissFromBackground)))
        containerView.insertSubview(dimming, at: 0)
        if let coordinator = presentedViewController.transitionCoordinator {
            coordinator.animate(alongsideTransition: { _ in self.dimming.alpha = 1 })
        } else { dimming.alpha = 1 }
    }

    @objc private func dismissFromBackground() {
        guard !presentedViewController.isBeingPresented, !presentedViewController.isBeingDismissed else { return }
        presentedViewController.dismiss(animated: true)
    }

    override func dismissalTransitionWillBegin() {
        if let coordinator = presentedViewController.transitionCoordinator {
            coordinator.animate(alongsideTransition: { _ in self.dimming.alpha = 0 })
        } else { dimming.alpha = 0 }
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        if !completed {
            dimming.removeFromSuperview()
            onDismiss?()
        }
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed {
            dimming.removeFromSuperview()
            onDismiss?()
        } else {
            dimming.alpha = 1
        }
    }
}

final class KadrioSheetTransition: NSObject, UIViewControllerAnimatedTransitioning {
    let presenting: Bool

    init(presenting: Bool) { self.presenting = presenting }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.28 }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let key: UITransitionContextViewControllerKey = presenting ? .to : .from
        guard let controller = context.viewController(forKey: key), let view = controller.view else {
            context.completeTransition(false)
            return
        }
        if presenting {
            context.containerView.addSubview(view)
            view.frame = context.finalFrame(for: controller)
            view.transform = CGAffineTransform(translationX: 0, y: view.bounds.height)
        }
        UIView.animate(withDuration: transitionDuration(using: context), delay: 0, options: [.curveEaseOut]) {
            view.transform = self.presenting ? .identity : CGAffineTransform(translationX: 0, y: view.bounds.height)
        } completion: { _ in
            let completed = !context.transitionWasCancelled
            if !completed { view.transform = .identity }
            context.completeTransition(completed)
        }
    }
}
