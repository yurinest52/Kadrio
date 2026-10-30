import SwiftUI
import UIKit

@main
struct KadrioApp: App {
    @StateObject private var app = KadrioAppState()

    init() {
        UIWindow.appearance().backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)
    }

    var body: some Scene {
        WindowGroup {
            KadrioRootView().environmentObject(app).preferredColorScheme(.light).tint(.black)
                .buttonStyle(KadrioPressButtonStyle())
        }
    }
}

struct KadrioRootView: View {
    @EnvironmentObject private var app: KadrioAppState
    @AppStorage("KadrioOnboardingCompleted") private var onboardingCompleted = false
    @State private var splashFinished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var screenAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.54)
    }

    private var showingSplash: Bool { !splashFinished || !app.initialized }
    var body: some View {
        ZStack {
            Color.kadrioBackground.ignoresSafeArea()
            if showingSplash { KadrioSplashView().transition(.kadrioScreen(reduceMotion: reduceMotion)).zIndex(1) }
            else if !onboardingCompleted {
                KadrioOnboardingView {
                    withAnimation(screenAnimation) {
                        onboardingCompleted = true
                        app.showPaywall = true
                    }
                }
                .transition(.kadrioScreen(reduceMotion: reduceMotion))
            } else { KadrioHomeView().transition(.kadrioScreen(reduceMotion: reduceMotion)) }
        }
        .background(Color.kadrioBackground.ignoresSafeArea())
        .animation(screenAnimation, value: showingSplash)
        .animation(screenAnimation, value: onboardingCompleted)
        .task {
            let clock = ContinuousClock()
            let minimumSplashEnd = clock.now.advanced(by: .milliseconds(2400))
            await app.initialize()
            do {
                try await clock.sleep(until: minimumSplashEnd)
                guard !Task.isCancelled else { return }
                splashFinished = true
            } catch {}
        }
        .alert(kadrioText("error.title"), isPresented: Binding(get: { !app.initialized && app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
            Button(kadrioText("retry")) { Task { await app.initialize() } }
        } message: { Text(app.errorMessage ?? "") }
    }
}
