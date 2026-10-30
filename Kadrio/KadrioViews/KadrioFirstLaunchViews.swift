import SwiftUI

struct KadrioOnboardingView: View {
    let completion: () -> Void
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    Image("KadrioOnboardingPortrait").resizable().scaledToFill().frame(width: geometry.size.width - 48, height: geometry.size.height * 0.56).clipped().clipShape(RoundedRectangle(cornerRadius: 25))
                    Image("KadrioPortraitPreview").resizable().scaledToFill().frame(width: 128, height: 155).clipped().clipShape(RoundedRectangle(cornerRadius: 23)).rotationEffect(.degrees(7)).offset(x: -22, y: 25)
                }.padding(.top, 20)
                Spacer(minLength: 22)
                Text(kadrioText("onboarding.title")).font(.system(size: 29, weight: .heavy)).tracking(-0.9).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text(kadrioText("onboarding.subtitle")).font(.system(size: 15)).foregroundStyle(Color.kadrioSecondary).multilineTextAlignment(.center).padding(.top, 15)
                HStack(spacing: 6) { Capsule().frame(width: 19, height: 5); Circle().fill(.gray.opacity(0.25)).frame(width: 5); Circle().fill(.gray.opacity(0.25)).frame(width: 5) }.frame(height: 8).padding(.top, 18).accessibilityHidden(true)
                Spacer(minLength: 20)
                KadrioPrimaryButton(title: kadrioText("continue"), action: completion).padding(.bottom, 22)
            }.padding(.horizontal, 24).frame(maxHeight: .infinity)
        }.background(Color.kadrioBackground)
    }
}

struct KadrioPaywallView: View {
    let onClose: () -> Void
    @EnvironmentObject private var app: KadrioAppState
    @State private var processing = false
    @State private var document: KadrioDocument?
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    HStack { Spacer(); KadrioCircleButton(symbol: "xmark", label: kadrioText("close"), action: onClose).disabled(processing).accessibilityIdentifier("KadrioPaywallClose") }.padding(.top, 8)
                    ZStack {
                        Image("KadrioPaywallLake").resizable().scaledToFill().frame(width: 136, height: 178).clipped().clipShape(RoundedRectangle(cornerRadius: 20)).rotationEffect(.degrees(-9)).offset(x: -78, y: 14)
                        Image("KadrioPaywallMountains").resizable().scaledToFill().frame(width: 136, height: 178).clipped().clipShape(RoundedRectangle(cornerRadius: 20)).rotationEffect(.degrees(8)).offset(x: 78, y: 7)
                        Image("KadrioPortraitPreview").resizable().scaledToFill().frame(width: 140, height: 185).clipped().clipShape(RoundedRectangle(cornerRadius: 20))
                    }.frame(height: min(220, geometry.size.height * 0.29))
                    VStack(spacing: 7) {
                        Text(kadrioText("paywall.title")).font(.system(size: 28, weight: .heavy)).tracking(-0.8)
                        Text(kadrioText("paywall.subtitle")).font(.system(size: 14)).foregroundStyle(Color.kadrioSecondary)
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
                            Text(kadrioText("paywall.threeSaves")).font(.system(size: 12)).foregroundStyle(Color.kadrioSecondary)
                        }
                        Spacer()
                        Text(kadrioText("paywall.pricePlaceholder")).font(.system(size: 20, weight: .bold))
                    }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.black, lineWidth: 1.5))
                    KadrioPrimaryButton(title: kadrioText(processing ? "loading" : "paywall.getTokens")) {
                        guard !processing else { return }
                        processing = true
                        Task {
                            let replenished = await app.replenish()
                            if !replenished { processing = false }
                        }
                    }.accessibilityIdentifier("KadrioPaywallGetTokens").disabled(processing)
                    HStack(spacing: 8) {
                        Button(kadrioText("privacy")) { document = .privacy }
                        Text("·")
                        Button(kadrioText("terms")) { document = .terms }
                    }.font(.system(size: 11)).foregroundStyle(Color.kadrioSecondary).padding(.bottom, 15)
                }.padding(.horizontal, 24).frame(minHeight: geometry.size.height)
            }.scrollIndicators(.hidden)
        }
        .background(Color.kadrioBackground.ignoresSafeArea())
        .interactiveDismissDisabled(true)
        .sheet(item: $document) { KadrioDocumentView(document: $0) }
        .modifier(KadrioErrorModifier(app: app))
    }
}
