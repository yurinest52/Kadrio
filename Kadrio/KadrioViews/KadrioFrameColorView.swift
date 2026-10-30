import SwiftUI

struct KadrioFrameColorView: View {
    @Binding var color: KadrioColor
    @Environment(\.dismiss) private var dismiss
    @State private var hue: Double = 0.04
    @State private var saturation: Double = 0.6
    @State private var brightness: Double = 0.9
    @State private var hex = ""
    static let presets = [KadrioColor(red: 0.06, green: 0.06, blue: 0.06), KadrioColor(), KadrioColor(red: 0.94, green: 0.4, blue: 0.35), KadrioColor(red: 1, green: 0.77, blue: 0.28), KadrioColor(red: 0.4, green: 0.72, blue: 0.65), KadrioColor(red: 0.31, green: 0.6, blue: 0.88), KadrioColor(red: 0.84, green: 0.32, blue: 0.57)]

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text(kadrioText("frameColor")).font(.system(size: 19, weight: .bold))
                Spacer()
                KadrioCircleButton(symbol: "xmark", label: kadrioText("close")) { dismiss() }
            }
            ColorPicker(kadrioText("spectrum"), selection: Binding(get: { Color(red: color.red, green: color.green, blue: color.blue) }, set: { new in
                let converted = UIColor(new)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                converted.getRed(&r, green: &g, blue: &b, alpha: &a)
                color = KadrioColor(red: r, green: g, blue: b)
                sync()
            }), supportsOpacity: false).font(.system(size: 14, weight: .medium))
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    Circle().stroke(.white, lineWidth: 2).frame(width: 19, height: 19).shadow(color: .black.opacity(0.3), radius: 2).position(x: saturation * geometry.size.width, y: (1 - brightness) * geometry.size.height)
                }.clipShape(RoundedRectangle(cornerRadius: 13)).contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    saturation = min(1, max(0, value.location.x / geometry.size.width))
                    brightness = min(1, max(0, 1 - value.location.y / geometry.size.height))
                    updateColor()
                })
            }.frame(height: 160).accessibilityLabel(kadrioText("spectrum"))
            VStack(spacing: 7) {
                LinearGradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) }, startPoint: .leading, endPoint: .trailing).frame(height: 9).clipShape(Capsule())
                Slider(value: $hue, in: 0...1).onChange(of: hue) { updateColor() }.accessibilityLabel(kadrioText("hue"))
            }
            HStack(spacing: 15) {
                Circle().fill(Color(red: color.red, green: color.green, blue: color.blue)).frame(width: 34, height: 34).overlay(Circle().stroke(.gray.opacity(0.2)))
                Text(kadrioText("hex")).font(.system(size: 11)).foregroundStyle(Color.kadrioSecondary)
                TextField(kadrioText("hex.placeholder"), text: $hex).font(.system(size: 15, design: .monospaced)).textInputAutocapitalization(.characters).autocorrectionDisabled().submitLabel(.done).onSubmit { applyHex() }.accessibilityLabel(kadrioText("hexColor"))
                Text(kadrioText("color.opacity")).font(.system(size: 12)).foregroundStyle(Color.kadrioSecondary)
            }.padding(10).background(Color.kadrioBackground, in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 13) {
                ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, preset in
                    Button { color = preset; sync() } label: { Circle().fill(Color(red: preset.red, green: preset.green, blue: preset.blue)).frame(width: 26, height: 26).overlay(Circle().stroke(.gray.opacity(0.2), lineWidth: 1)) }.accessibilityLabel(preset.hex)
                }
                Spacer(minLength: 0)
            }
            KadrioPrimaryButton(title: kadrioText("done")) { applyHex(); dismiss() }
        }.padding(22).presentationDetents([.height(560)]).presentationDragIndicator(.visible).presentationCornerRadius(26).onAppear { sync() }
    }

    private func sync() {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = h; saturation = s; brightness = b; hex = color.hex
    }

    private func updateColor() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1).getRed(&r, green: &g, blue: &b, alpha: &a)
        color = KadrioColor(red: r, green: g, blue: b)
        hex = color.hex
    }

    private func applyHex() {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let number = UInt32(value, radix: 16) else { hex = color.hex; return }
        color = KadrioColor(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
        sync()
    }
}
