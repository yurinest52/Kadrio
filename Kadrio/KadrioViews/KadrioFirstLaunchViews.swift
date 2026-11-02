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
    private let privacyURL = URL(string: "https://www.freeprivacypolicy.com/live/fa251b16-ff0a-4e3d-aa62-25984710d0cd")!
    private let termsURL = URL(string: "https://www.freeprivacypolicy.com/live/6f7d54a2-04d7-4599-b7c9-d8f86b7ff3bf")!
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let compact = geometry.size.height < 520
                let contentWidth = max(1, geometry.size.width - 48)
                let artworkHeight = min(contentWidth * 250 / 342, compact ? max(1, geometry.size.height) * 0.34 : .infinity)
                ScrollView {
                    VStack(spacing: compact ? 12 : 18) {
                        KadrioPaywallArtwork()
                            .frame(width: artworkHeight * 342 / 250, height: artworkHeight)
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 7) {
                            Text(kadrioText("paywall.title")).font(.system(size: 28, weight: .heavy)).tracking(-0.8)
                            Text(kadrioText("paywall.subtitle")).font(.system(size: 14)).foregroundStyle(
                                Color.kadrioSecondary)
                        }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 13) {
                            ForEach(["paywall.tools", "paywall.resolution", "paywall.share"], id: \.self) { key in
                                Label(kadrioText(key), systemImage: "checkmark.circle.fill").font(.system(size: 15))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(.vertical, 7)
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(kadrioText("paywall.tokens")).font(.system(size: 16, weight: .semibold))
                                Text(kadrioText("paywall.threeSaves")).font(.system(size: 12)).foregroundStyle(
                                    Color.kadrioSecondary)
                            }.fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(kadrioText("paywall.pricePlaceholder")).font(.system(size: 20, weight: .bold)).fixedSize()
                        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18)).overlay(
                            RoundedRectangle(cornerRadius: 18).stroke(.black, lineWidth: 1.5))
                    }.frame(width: contentWidth).padding(.horizontal, 24).padding(.bottom, 12)
                        .frame(minHeight: geometry.size.height, alignment: .top)
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
            .safeAreaInset(edge: .bottom, spacing: 0) { purchaseControls }
            .toolbar(.hidden, for: .navigationBar)
        }
        .background(Color.kadrioBackground.ignoresSafeArea())
        .interactiveDismissDisabled(true)
        .modifier(KadrioScreenEntrance())
        .modifier(KadrioErrorModifier(app: app))
    }

    private var purchaseControls: some View {
        VStack(spacing: 8) {
            KadrioPrimaryButton(title: kadrioText(processing ? "loading" : "paywall.getTokens")) {
                guard !processing else { return }
                processing = true
                Task {
                    let replenished = await app.replenish()
                    if !replenished { processing = false }
                }
            }.accessibilityIdentifier("KadrioPaywallGetTokens").disabled(processing)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    legalLink("privacy", destination: privacyURL).fixedSize(horizontal: true, vertical: true)
                    Text("·")
                    legalLink("terms", destination: termsURL).fixedSize(horizontal: true, vertical: true)
                }
                VStack(spacing: 0) {
                    legalLink("privacy", destination: privacyURL)
                    legalLink("terms", destination: termsURL)
                }
            }.font(.system(size: 11)).foregroundStyle(Color.kadrioSecondary)
                .frame(maxWidth: .infinity)
        }.padding(.horizontal, 24).padding(.vertical, 12).background(Color.kadrioBackground)
    }

    private func legalLink(_ title: String, destination: URL) -> some View {
        Link(destination: destination) {
            Text(kadrioText(title)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4).frame(minHeight: 44)
        }
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
