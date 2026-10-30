import SwiftUI

struct KadrioOnboardingView: View {
    let completion: () -> Void
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        ZStack(alignment: .bottomTrailing) {
                            Image("KadrioOnboardingPortrait").resizable().scaledToFill().frame(
                                width: max(1, geometry.size.width - 48),
                                height: min(max(1, geometry.size.width - 48) * 1.28, geometry.size.height * 0.67)
                            ).clipped().clipShape(RoundedRectangle(cornerRadius: 25))
                            Image("KadrioPortraitPreview").resizable().scaledToFill().frame(width: 128, height: 155)
                                .clipped().clipShape(RoundedRectangle(cornerRadius: 23)).rotationEffect(.degrees(7))
                                .offset(x: -22, y: 25)
                        }.padding(.top, 12).padding(.bottom, 18)
                        Spacer(minLength: 22)
                        Text(kadrioText("onboarding.title")).font(.system(size: 29, weight: .heavy)).tracking(-0.9)
                            .multilineTextAlignment(.center).frame(maxWidth: 300).fixedSize(horizontal: false, vertical: true)
                        Text(kadrioText("onboarding.subtitle")).font(.system(size: 15)).foregroundStyle(
                            Color.kadrioSecondary
                        ).multilineTextAlignment(.center).padding(.top, 15)
                        HStack(spacing: 6) {
                            Capsule().frame(width: 19, height: 5)
                            Circle().fill(.gray.opacity(0.25)).frame(width: 5)
                            Circle().fill(.gray.opacity(0.25)).frame(width: 5)
                        }.frame(height: 8).padding(.top, 18).accessibilityHidden(true)
                        Spacer(minLength: 20)
                    }.padding(.horizontal, 24)
                }.scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                KadrioPrimaryButton(title: kadrioText("continue"), action: completion).accessibilityIdentifier(
                    "KadrioOnboardingContinue"
                )
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16).background(Color.kadrioBackground)
            }
            .background(Color.kadrioBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .modifier(KadrioScreenEntrance())
    }
}

struct KadrioPaywallView: View {
    let onClose: () -> Void
    @EnvironmentObject private var app: KadrioAppState
    @State private var processing = false
    private let legalURL = URL(string: "https://www.freeprivacypolicy.com/live/fa251b16-ff0a-4e3d-aa62-25984710d0cd")!
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 18) {
                        KadrioPaywallArtwork()
                            .frame(height: max(1, geometry.size.width - 48) * 250 / 342)
                        VStack(spacing: 7) {
                            Text(kadrioText("paywall.title")).font(.system(size: 28, weight: .heavy)).tracking(-0.8)
                            Text(kadrioText("paywall.subtitle")).font(.system(size: 14)).foregroundStyle(
                                Color.kadrioSecondary)
                        }
                        VStack(alignment: .leading, spacing: 13) {
                            ForEach(["paywall.tools", "paywall.resolution", "paywall.share"], id: \.self) { key in
                                Label(kadrioText(key), systemImage: "checkmark.circle.fill").font(.system(size: 15))
                            }
                        }.padding(.vertical, 7)
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(kadrioText("paywall.tokens")).font(.system(size: 16, weight: .semibold))
                                Text(kadrioText("paywall.threeSaves")).font(.system(size: 12)).foregroundStyle(
                                    Color.kadrioSecondary)
                            }
                            Spacer()
                            Text(kadrioText("paywall.pricePlaceholder")).font(.system(size: 20, weight: .bold))
                        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18)).overlay(
                            RoundedRectangle(cornerRadius: 18).stroke(.black, lineWidth: 1.5))
                        KadrioPrimaryButton(title: kadrioText(processing ? "loading" : "paywall.getTokens")) {
                            guard !processing else { return }
                            processing = true
                            Task {
                                let replenished = await app.replenish()
                                if !replenished { processing = false }
                            }
                        }.accessibilityIdentifier("KadrioPaywallGetTokens").disabled(processing)
                        HStack(spacing: 8) {
                            Link(kadrioText("privacy"), destination: legalURL)
                                .padding(.horizontal, 4).frame(minHeight: 44)
                            Text("·")
                            Link(kadrioText("terms"), destination: legalURL)
                                .padding(.horizontal, 4).frame(minHeight: 44)
                        }.font(.system(size: 11)).foregroundStyle(Color.kadrioSecondary).padding(.bottom, 15)
                    }.padding(.horizontal, 24).padding(.top, 0).frame(minHeight: geometry.size.height, alignment: .top)
                }.scrollIndicators(.hidden)
            }
            .background(Color.kadrioBackground)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Spacer()
                    KadrioCircleButton(symbol: "xmark", label: kadrioText("close"), action: onClose).disabled(
                        processing
                    ).accessibilityIdentifier("KadrioPaywallClose")
                }.padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 0).background(Color.kadrioBackground)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .background(Color.kadrioBackground.ignoresSafeArea())
        .interactiveDismissDisabled(true)
        .modifier(KadrioScreenEntrance())
        .modifier(KadrioErrorModifier(app: app))
    }
}

struct KadrioPaywallArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 16)
            ZStack {
                Image("KadrioPaywallLake").resizable().scaledToFit()
                    .frame(width: width * 0.398, height: width * 0.52)
                    .rotationEffect(.degrees(8)).offset(x: -width * 0.23, y: width * 0.035)
                Image("KadrioPaywallMountains").resizable().scaledToFit()
                    .frame(width: width * 0.398, height: width * 0.52)
                    .rotationEffect(.degrees(-8)).offset(x: width * 0.23, y: -width * 0.015)
                Image("KadrioPortraitPreview").resizable().scaledToFit()
                    .frame(width: width * 0.41, height: width * 0.54)
                    .offset(y: -width * 0.035)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}
