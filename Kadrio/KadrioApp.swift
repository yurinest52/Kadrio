import SwiftUI

@main
struct KadrioApp: App {
    @StateObject private var app = KadrioAppState()
    var body: some Scene {
        WindowGroup {
            KadrioRootView().environmentObject(app).preferredColorScheme(.light).tint(.black)
        }
    }
}

struct KadrioRootView: View {
    @EnvironmentObject private var app: KadrioAppState
    @AppStorage("KadrioOnboardingCompleted") private var onboardingCompleted = false
    @State private var splashFinished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showingSplash: Bool { !splashFinished || !app.initialized }
    var body: some View {
        ZStack {
            if showingSplash { KadrioSplashView().transition(.opacity).zIndex(1) }
            else if !onboardingCompleted {
                KadrioOnboardingView {
                    withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.3)) {
                        onboardingCompleted = true
                        app.showPaywall = true
                    }
                }
                .transition(.opacity)
            } else { KadrioHomeView().transition(.opacity) }
        }
        .background(Color.kadrioBackground.ignoresSafeArea())
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.35), value: showingSplash)
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.3), value: onboardingCompleted)
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
