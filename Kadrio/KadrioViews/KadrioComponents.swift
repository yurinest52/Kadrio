import ImageIO
import SwiftUI
import UIKit

extension Color {
    static let kadrioBackground = Color(red: 0.95, green: 0.95, blue: 0.96)
    static let kadrioSecondary = Color(white: 0.53)
}

struct KadrioPrimaryButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 54)
                .foregroundStyle(.white).background(.black, in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct KadrioCircleButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44).background(.white, in: Circle()).contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

struct KadrioFileImage: View {
    let url: URL
    var maxPixel = 700
    var mode: ContentMode = .fill
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: mode)
                } else {
                    Color.black.opacity(0.035).overlay { ProgressView() }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .task(id: url) {
            let url = url
            let maxPixel = maxPixel
            image = await Task.detached(priority: .userInitiated) {
                guard
                    let source = CGImageSourceCreateWithURL(
                        url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                    let cg = CGImageSourceCreateThumbnailAtIndex(
                        source, 0,
                        [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                        ] as CFDictionary)
                else { return nil as UIImage? }
                return UIImage(cgImage: cg)
            }.value
        }
    }
}

struct KadrioShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct KadrioShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct KadrioAccessView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "lock").font(.system(size: 27, weight: .light)).frame(width: 68, height: 68)
                    .background(Color.kadrioBackground, in: Circle())
                Text(kadrioText("access.title")).font(.system(size: 21, weight: .bold))
                Text(kadrioText("access.message")).font(.system(size: 14)).foregroundStyle(Color.kadrioSecondary)
                    .multilineTextAlignment(.center)
            }.padding(24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                KadrioPrimaryButton(title: kadrioText("openSettings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button(kadrioText("notNow")) { dismiss() }.font(.system(size: 14)).foregroundStyle(
                    Color.kadrioSecondary
                ).frame(height: 44)
            }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12).background(.white)
        }
        .presentationDetents([.height(400), .large]).presentationDragIndicator(.visible)
    }
}

struct KadrioErrorModifier: ViewModifier {
    @ObservedObject var app: KadrioAppState
    var active = true
    func body(content: Content) -> some View {
        content
            .alert(
                kadrioText("error.title"),
                isPresented: Binding(
                    get: { active && app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })
            ) {
                Button(kadrioText("ok"), role: .cancel) { app.errorMessage = nil }
            } message: {
                Text(app.errorMessage ?? "")
            }
            .sheet(isPresented: Binding(get: { active && app.accessDenied }, set: { app.accessDenied = $0 })) {
                KadrioAccessView()
            }
    }
}

struct KadrioCameraView: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.cameraCaptureMode = .photo
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: KadrioCameraView
        init(parent: KadrioCameraView) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
            parent.completion(nil)
        }
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.dismiss()
            parent.completion(info[.originalImage] as? UIImage)
        }
    }
}

struct KadrioCropRatioIcon: View {
    let ratio: KadrioCropRatio
    var body: some View {
        let aspect = ratio.value ?? 1
        let width = aspect >= 1 ? 16.0 : 19.0 * aspect
        let height = aspect >= 1 ? 16.0 / aspect : 19.0
        RoundedRectangle(cornerRadius: 2)
            .stroke(style: StrokeStyle(lineWidth: 1.1, dash: ratio == .free ? [1.5, 1.5] : []))
            .frame(width: width, height: height)
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}

private struct KadrioScreenMotion {
    var opacity: Double = 0
    var scale: CGFloat = 0.978
    var offset: CGFloat = 18
    var blur: CGFloat = 3
}

struct KadrioScreenEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        Group {
            if reduceMotion {
                content.opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: appeared)
            } else {
                content.keyframeAnimator(initialValue: KadrioScreenMotion(), trigger: appeared) { view, motion in
                    view
                        .opacity(motion.opacity)
                        .scaleEffect(motion.scale, anchor: .center)
                        .offset(y: motion.offset)
                        .blur(radius: motion.blur)
                } keyframes: { _ in
                    KeyframeTrack(\.opacity) {
                        CubicKeyframe(1, duration: 0.24)
                    }
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(1.003, duration: 0.36)
                        CubicKeyframe(1, duration: 0.18)
                    }
                    KeyframeTrack(\.offset) {
                        CubicKeyframe(2, duration: 0.28)
                        CubicKeyframe(0, duration: 0.26)
                    }
                    KeyframeTrack(\.blur) {
                        CubicKeyframe(0, duration: 0.3)
                    }
                }
            }
        }
        .onAppear { appeared = true }
    }
}

private struct KadrioScreenDeparture: ViewModifier {
    let progress: CGFloat
    func body(content: Content) -> some View {
        content
            .opacity(1 - Double(progress))
            .scaleEffect(1 - progress * 0.015)
            .offset(y: -progress * 12)
            .blur(radius: progress * 2)
    }
}

extension AnyTransition {
    static func kadrioScreen(reduceMotion: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .identity,
            removal: reduceMotion ? .opacity : .modifier(
                active: KadrioScreenDeparture(progress: 1),
                identity: KadrioScreenDeparture(progress: 0)))
    }
}
