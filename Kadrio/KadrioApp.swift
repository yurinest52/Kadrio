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

    private var showingSplash: Bool { !splashFinished || !app.initialized }
    var body: some View {
        ZStack {
            if showingSplash { KadrioSplashView().transition(.opacity).zIndex(1) }
            else if !onboardingCompleted {
                KadrioOnboardingView {
                    onboardingCompleted = true
                    app.showPaywall = true
                }
            } else { KadrioHomeView() }
        }
        .animation(.easeInOut(duration: 0.35), value: showingSplash)
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
