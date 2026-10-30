import SwiftUI

struct KadrioFrameColorView: View {
    @Binding var color: KadrioColor
    @Environment(\.dismiss) private var dismiss
    @State private var hue: Double = 0.04
    @State private var saturation: Double = 0.6
    @State private var brightness: Double = 0.9
    @State private var hex = ""
    @State private var selectedTab = 1
    static let presets = [
        KadrioColor(red: 0.06, green: 0.06, blue: 0.06), KadrioColor(), KadrioColor(red: 0.94, green: 0.4, blue: 0.35),
        KadrioColor(red: 1, green: 0.77, blue: 0.28), KadrioColor(red: 0.4, green: 0.72, blue: 0.65),
        KadrioColor(red: 0.31, green: 0.6, blue: 0.88), KadrioColor(red: 0.84, green: 0.32, blue: 0.57),
    ]

    private var selectedColor: Color { Color(red: color.red, green: color.green, blue: color.blue) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text(kadrioText("frameColor")).font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.kadrioSecondary).frame(width: 28, height: 28)
                            .background(Color.kadrioBackground, in: Circle())
                    }.accessibilityLabel(kadrioText("close")).accessibilityIdentifier("KadrioFrameColorClose")
                }
                HStack(spacing: 0) {
                    ForEach(Array(["color.grid", "spectrum", "color.sliders"].enumerated()), id: \.offset) { index, key in
                        Button { selectedTab = index } label: {
                            Text(kadrioText(key)).font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity).frame(height: 30)
                                .foregroundStyle(selectedTab == index ? .white : Color.kadrioSecondary)
                                .background(selectedTab == index ? Color.black : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                }.padding(3).background(Color.kadrioBackground, in: RoundedRectangle(cornerRadius: 7))
                Group {
                    if selectedTab == 0 { colorGrid }
                    else if selectedTab == 1 { spectrum }
                    else { colorSliders }
                }.frame(height: 150)
                hueTrack
                HStack(spacing: 10) {
                    Circle().fill(selectedColor).frame(width: 38, height: 38)
                        .overlay(Circle().stroke(.black.opacity(0.08), lineWidth: 1))
                    HStack(spacing: 8) {
                        Text(kadrioText("hex")).font(.system(size: 9)).foregroundStyle(Color.kadrioSecondary)
                        TextField(kadrioText("hex.placeholder"), text: $hex)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .submitLabel(.done).onSubmit { applyHex() }
                            .accessibilityLabel(kadrioText("hexColor"))
                    }.padding(.horizontal, 12).frame(height: 40)
                        .background(Color.kadrioBackground, in: RoundedRectangle(cornerRadius: 9))
                    Text(kadrioText("color.opacity")).font(.system(size: 13, weight: .medium))
                        .frame(width: 88, height: 40)
                        .background(Color.kadrioBackground, in: RoundedRectangle(cornerRadius: 9))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(kadrioText("color.recent")).font(.system(size: 11)).foregroundStyle(Color.kadrioSecondary)
                    HStack(spacing: 12) {
                        ForEach([2, 4, 3, 5, 0, 1, 6], id: \.self) { index in
                            let preset = Self.presets[index]
                            Button {
                                color = preset
                                sync()
                            } label: {
                                Circle().fill(Color(red: preset.red, green: preset.green, blue: preset.blue))
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(color.hex == preset.hex ? .black : .clear, lineWidth: 2))
                            }.buttonStyle(.plain).accessibilityLabel(preset.hex)
                        }
                        Spacer(minLength: 0)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 8)
        }
        .background(.white)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                applyHex()
                dismiss()
            } label: {
                Text(kadrioText("done")).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 46)
                    .background(.black, in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("KadrioFrameColorDone")
                .padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 12).background(.white)
        }
        .presentationDetents([.height(500), .large]).presentationDragIndicator(.visible)
        .presentationCornerRadius(26).presentationBackground(.white)
        .onAppear { sync() }
    }

    private var spectrum: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                Circle().stroke(.white, lineWidth: 2).frame(width: 21, height: 21)
                    .shadow(color: .black.opacity(0.25), radius: 2)
                    .position(x: max(11, min(geometry.size.width - 11, saturation * geometry.size.width)),
                              y: max(11, min(geometry.size.height - 11, (1 - brightness) * geometry.size.height)))
            }.clipShape(RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    saturation = min(1, max(0, value.location.x / max(1, geometry.size.width)))
                    brightness = min(1, max(0, 1 - value.location.y / max(1, geometry.size.height)))
                    updateColor()
                })
        }.accessibilityLabel(kadrioText("spectrum"))
    }

    private var hueTrack: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                LinearGradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) },
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 12).clipShape(Capsule())
                Circle().fill(.white).frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .offset(x: hue * max(0, geometry.size.width - 20))
            }.frame(height: 22).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    hue = min(1, max(0, (value.location.x - 10) / max(1, geometry.size.width - 20)))
                    updateColor()
                })
        }.frame(height: 22).accessibilityLabel(kadrioText("hue"))
            .accessibilityValue("\(Int(hue * 360))")
            .accessibilityAdjustableAction { direction in
                hue = min(1, max(0, hue + (direction == .increment ? 0.02 : -0.02)))
                updateColor()
            }
    }

    private var colorGrid: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<12, id: \.self) { column in
                            let sample = column == 0
                                ? Color(white: 1 - Double(row) / 7)
                                : Color(hue: Double(column - 1) / 11, saturation: row < 4 ? Double(row + 1) / 4 : 1,
                                        brightness: row < 4 ? 1 : 1 - Double(row - 3) * 0.18)
                            Button {
                                var r: CGFloat = 0
                                var g: CGFloat = 0
                                var b: CGFloat = 0
                                var a: CGFloat = 0
                                UIColor(sample).getRed(&r, green: &g, blue: &b, alpha: &a)
                                color = KadrioColor(red: r, green: g, blue: b)
                                sync()
                            } label: { sample.frame(maxWidth: .infinity, maxHeight: .infinity) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var colorSliders: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(kadrioText("hue")).font(.system(size: 11)).foregroundStyle(Color.kadrioSecondary)
                Slider(value: $hue, in: 0...1).onChange(of: hue) { updateColor() }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(kadrioText("color.saturation")).font(.system(size: 11)).foregroundStyle(Color.kadrioSecondary)
                Slider(value: $saturation, in: 0...1).onChange(of: saturation) { updateColor() }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(kadrioText("color.brightness")).font(.system(size: 11)).foregroundStyle(Color.kadrioSecondary)
                Slider(value: $brightness, in: 0...1).onChange(of: brightness) { updateColor() }
            }
        }.tint(.black)
    }

    private func sync() {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1).getHue(
            &h, saturation: &s, brightness: &b, alpha: &a)
        hue = h
        saturation = s
        brightness = b
        hex = color.hex
    }

    private func updateColor() {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1).getRed(
            &r, green: &g, blue: &b, alpha: &a)
        color = KadrioColor(red: r, green: g, blue: b)
        hex = color.hex
    }

    private func applyHex() {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let number = UInt32(value, radix: 16) else {
            hex = color.hex
            return
        }
        color = KadrioColor(
            red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255,
            blue: Double(number & 255) / 255)
        sync()
    }
}
