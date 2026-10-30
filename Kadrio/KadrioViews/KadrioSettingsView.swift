import StoreKit
import SwiftUI

struct KadrioConfiguration {
    private static func value(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "KadrioConfiguration", withExtension: "plist"),
            let dictionary = NSDictionary(contentsOf: url), let value = dictionary[key] as? String, !value.isEmpty
        else { return nil }
        return value
    }
    static var supportEmail: String? { value("KadrioSupportEmail") }
    static func documentURL(_ document: KadrioDocument) -> URL? {
        guard let value = value(document == .support ? "KadrioSupportURL" : document == .privacy ? "KadrioPrivacyURL" : "KadrioTermsURL"),
            let url = URL(string: value), url.scheme == "https"
        else { return nil }
        return url
    }
}

enum KadrioDocument: String, Identifiable {
    case privacy, terms, support
    var id: String { rawValue }
    var title: String { kadrioText(rawValue) }
}

struct KadrioDocumentView: View {
    let document: KadrioDocument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: document == .support ? "envelope" : "doc.text").font(
                        .system(size: 32, weight: .light)
                    ).padding(.top, 20)
                    Text(kadrioText("document.\(document.rawValue)")).font(.system(size: 17)).lineSpacing(6)
                    if document == .support, let email = KadrioConfiguration.supportEmail,
                        let url = URL(string: "mailto:\(email)")
                    {
                        Link(email, destination: url).font(.headline)
                    } else if document != .support, let url = KadrioConfiguration.documentURL(document) {
                        KadrioPrimaryButton(title: kadrioText("document.open")) { openURL(url) }
                    } else {
                        Text(kadrioText("document.configuration")).font(.system(size: 14)).foregroundStyle(
                            Color.kadrioSecondary)
                    }
                    if document == .support {
                        ShareLink(
                            item:
                                "Kadrio · iOS \(UIDevice.current.systemVersion) · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")"
                        ) {
                            Label(kadrioText("support.diagnostics"), systemImage: "square.and.arrow.up")
                        }
                    }
                }.padding(24)
            }.background(Color.kadrioBackground).navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(kadrioText("done")) { dismiss() } } }
        }
    }
}

struct KadrioSettingsView: View {
    @EnvironmentObject private var app: KadrioAppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @State private var confirmClear = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 21)).frame(
                            width: 44, height: 44, alignment: .leading)
                    }.accessibilityLabel(kadrioText("back")).accessibilityIdentifier("KadrioSettingsBack")
                    Text(kadrioText("settings")).font(.system(size: 34, weight: .bold)).tracking(-1).padding(.top, -17)
                    HStack(spacing: 15) {
                        Image(systemName: "sparkles").font(.system(size: 25))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(kadrioFormat("tokens.remaining", app.ledger.tokens)).font(
                                .system(size: 18, weight: .medium))
                            Text(kadrioText("tokens.exchange")).font(.system(size: 13)).foregroundStyle(
                                Color.kadrioSecondary)
                        }
                        Spacer(minLength: 3)
                        Button {
                            app.showPaywall = true
                        } label: {
                            Text(kadrioText("getMore")).font(.system(size: 13, weight: .semibold)).fixedSize(
                                horizontal: true, vertical: false
                            ).foregroundStyle(.white).padding(.horizontal, 15).frame(height: 35).background(
                                .black, in: Capsule())
                        }
                    }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 22)).kadrioCardShadow()
                    Button {
                        confirmClear = true
                    } label: {
                        Text(kadrioText("clearHistory")).foregroundStyle(Color(red: 0.73, green: 0.37, blue: 0.42))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(19).background(
                                .white, in: RoundedRectangle(cornerRadius: 19))
                    }.disabled(app.saving).kadrioCardShadow()
                    VStack(spacing: 0) {
                        settingsRow("rateUs") { requestReview() }
                        Divider().padding(.leading, 18)
                        settingsRow("support") { if let url = KadrioConfiguration.documentURL(.support) { openURL(url) } }
                    }.background(.white, in: RoundedRectangle(cornerRadius: 20)).kadrioCardShadow().padding(.top, -7)
                    VStack(spacing: 0) {
                        settingsRow("privacy") { if let url = KadrioConfiguration.documentURL(.privacy) { openURL(url) } }
                        Divider().padding(.leading, 18)
                        settingsRow("terms") { if let url = KadrioConfiguration.documentURL(.terms) { openURL(url) } }
                    }.background(.white, in: RoundedRectangle(cornerRadius: 20)).kadrioCardShadow().padding(.top, -7)
                    Spacer()
                }.font(.system(size: 17)).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16).frame(
                    maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
            }.scrollIndicators(.hidden)
        }
        .background(Color.kadrioBackground)
        .toolbar(.hidden, for: .navigationBar)
        .modifier(KadrioScreenEntrance())
        .alert(kadrioText("clear.title"), isPresented: $confirmClear) {
            Button(kadrioText("cancel"), role: .cancel) {}
            Button(kadrioText("clear"), role: .destructive) { Task { await app.clearHistory() } }
        } message: {
            Text(kadrioText("clear.message"))
        }
    }

    private func settingsRow(_ key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(kadrioText(key))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(.gray.opacity(0.5))
            }.padding(.horizontal, 19).frame(height: 54).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("KadrioSettingsRow-" + key)
    }
}

extension View {
    func kadrioCardShadow() -> some View { shadow(color: .black.opacity(0.025), radius: 9, y: 5) }
}
