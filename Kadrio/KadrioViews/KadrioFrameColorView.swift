import SwiftUI

struct KadrioFrameColorView: View {
    @Binding var color: KadrioColor
    var editingChanged: (Bool) -> Void = { _ in }
    @GestureState private var dragging = false
    private enum PaletteTab: String, CaseIterable, Identifiable {
        case grid = "color.grid", spectrum, sliders = "color.sliders"
        var id: String { rawValue }
    }
    let onClose: () -> Void
    @State private var hue: Double = 0.04
    @State private var saturation: Double = 0.6
    @State private var brightness: Double = 0.9
    @State private var hex = ""
    @State private var inputError: String?
    @State private var selectedTab = PaletteTab.spectrum
    @State private var opacityText = "100"
    @State private var inputFrame = CGRect.zero
    @FocusState private var focusedField: KadrioColorField?
    private enum KadrioColorField { case hex, opacity }
    static let presets = [
        KadrioColor(red: 0.06, green: 0.06, blue: 0.06), KadrioColor(red: 242.0 / 255, green: 242.0 / 255, blue: 244.0 / 255), KadrioColor(red: 0.94, green: 0.4, blue: 0.35),
        KadrioColor(red: 1, green: 0.77, blue: 0.28), KadrioColor(red: 0.4, green: 0.72, blue: 0.65),
        KadrioColor(red: 0.31, green: 0.6, blue: 0.88), KadrioColor(red: 0.84, green: 0.32, blue: 0.57),
    ]

    private var selectedColor: Color { Color(red: color.red, green: color.green, blue: color.blue).opacity(color.alpha) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Text(kadrioText("frameColor")).font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Button { if finishEditing() { onClose() } } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.kadrioSecondary).frame(width: 28, height: 28)
                                .background(Color.kadrioBackground, in: Circle())
                        }.accessibilityLabel(kadrioText("close")).accessibilityIdentifier("KadrioFrameColorClose")
                    }
                    HStack(spacing: 0) {
                        ForEach(PaletteTab.allCases) { tab in
                            Button { if finishEditing() { selectedTab = tab } } label: {
                                Text(kadrioText(tab.rawValue)).font(.system(size: 12, weight: .medium))
                                    .frame(maxWidth: .infinity).frame(height: 30)
                                    .foregroundStyle(selectedTab == tab ? .white : Color.kadrioSecondary)
                                    .background(selectedTab == tab ? Color.black : .clear, in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(KadrioPressButtonStyle())
                        }
                    }.padding(3).background(Color.kadrioBackground, in: RoundedRectangle(cornerRadius: 7))
                    Group {
                        if selectedTab == .grid { colorGrid }
                        else if selectedTab == .spectrum { spectrum }
                        else { colorSliders }
                    }.frame(height: 150)
                    hueTrack
                    HStack(spacing: 10) {
                        Circle().fill(selectedColor).frame(width: 38, height: 38)
                            .overlay(Circle().stroke(.black.opacity(0.08), lineWidth: 1))
                        HStack(spacing: 8) {
                            Text(kadrioText("hex")).font(.system(size: 9)).foregroundStyle(Color.kadrioSecondary)
                            TextField(kadrioText("hex.placeholder"), text: hexInput)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .keyboardType(.asciiCapable).textInputAutocapitalization(.characters).autocorrectionDisabled()
                                .focused($focusedField, equals: .hex)
                                .onChange(of: hex) { previous, text in validateHexInput(text, previous: previous) }
                                .submitLabel(.done).onSubmit { finishEditing() }
                                .accessibilityLabel(kadrioText("hexColor"))
                        }.padding(.horizontal, 12).frame(height: 40)
                            .background(Color.kadrioBackground, in: RoundedRectangle(cornerRadius: 9))
                        HStack(spacing: 1) {
                            TextField("100", text: opacityInput)
                                .keyboardType(.numberPad).multilineTextAlignment(.leading)
                                .focused($focusedField, equals: .opacity)
                                .onChange(of: opacityText) { previous, text in validateOpacityInput(text, previous: previous) }
                                .submitLabel(.done).onSubmit { finishEditing() }
                                .accessibilityLabel(kadrioText("color.opacity.label"))
                            Text("%")
                        }.font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 14).frame(width: 88, height: 40)
                            .background(Color.kadrioBackground, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .id("KadrioFrameColorInputs")
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: KadrioColorInputFrame.self, value: geometry.frame(in: .named("KadrioPalette")))
                    })
                    VStack(alignment: .leading, spacing: 8) {
                        Text(kadrioText("color.recent")).font(.system(size: 11)).foregroundStyle(Color.kadrioSecondary)
                        HStack(spacing: 12) {
                            ForEach([2, 4, 3, 5, 0, 1, 6], id: \.self) { index in
                                let preset = Self.presets[index]
                                Button {
                                    dismissKeyboard()
                                    color = preset
                                    sync()
                                } label: {
                                    Circle().fill(Color(red: preset.red, green: preset.green, blue: preset.blue))
                                        .frame(width: 24, height: 24)
                                        .overlay(Circle().stroke(color.hex == preset.hex ? .black : .clear, lineWidth: 2))
                                }.buttonStyle(KadrioPressButtonStyle()).accessibilityLabel(preset.hex)
                            }
                            Spacer(minLength: 0)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 8)
            }
            .coordinateSpace(name: "KadrioPalette")
            .onPreferenceChange(KadrioColorInputFrame.self) { inputFrame = $0 }
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                if !inputFrame.contains(value.location) { finishEditing() }
            })
            .onChange(of: focusedField) { previous, field in
                if previous == .hex { applyHex() }
                if previous == .opacity { applyOpacity() }
                if field != nil {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("KadrioFrameColorInputs", anchor: .center)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
                guard focusedField != nil else { return }
                DispatchQueue.main.async {
                    guard focusedField != nil else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("KadrioFrameColorInputs", anchor: .center)
                    }
                }
            }
            .background(.white)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    if finishEditing() { onClose() }
                } label: {
                    Text(kadrioText("done")).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 46)
                        .background(.black, in: Capsule())
                }.buttonStyle(KadrioPressButtonStyle()).accessibilityIdentifier("KadrioFrameColorDone")
                    .padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 12).background(.white)
            }
            .onAppear { sync() }
            .onChange(of: dragging) { _, active in editingChanged(active) }
            .onDisappear {
                dismissKeyboard()
                editingChanged(false)
            }
            .alert(kadrioText("error.title"), isPresented: Binding(
                get: { inputError != nil }, set: { if !$0 { inputError = nil } })) {
                Button(kadrioText("done"), role: .cancel) {}
            } message: {
                Text(kadrioText(inputError ?? "color.invalidHex"))
            }
        }
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
                .gesture(DragGesture(minimumDistance: 0).updating($dragging) { _, active, _ in active = true }.onChanged { value in
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
                .gesture(DragGesture(minimumDistance: 0).updating($dragging) { _, active, _ in active = true }.onChanged { value in
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
                                dismissKeyboard()
                                color = KadrioColor(red: r, green: g, blue: b, alpha: color.alpha)
                                sync()
                            } label: { sample.frame(maxWidth: .infinity, maxHeight: .infinity) }
                                .buttonStyle(KadrioPressButtonStyle())
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
                Slider(value: componentInput($hue), in: 0...1, onEditingChanged: editingChanged)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(kadrioText("color.saturation")).font(.system(size: 11)).foregroundStyle(Color.kadrioSecondary)
                Slider(value: componentInput($saturation), in: 0...1, onEditingChanged: editingChanged)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(kadrioText("color.brightness")).font(.system(size: 11)).foregroundStyle(Color.kadrioSecondary)
                Slider(value: componentInput($brightness), in: 0...1, onEditingChanged: editingChanged)
            }
        }.tint(.black)
    }

    private var colorHex: String {
        let rgb = String(format: "#%02X%02X%02X", Int((color.red * 255).rounded()),
                         Int((color.green * 255).rounded()), Int((color.blue * 255).rounded()))
        return color.alpha < 1 ? rgb + String(format: "%02X", Int((color.alpha * 255).rounded())) : rgb
    }

    private func sync() {
        syncComponents()
        hex = colorHex
        opacityText = String(Int((color.alpha * 100).rounded()))
    }

    private func syncComponents() {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1).getHue(
            &h, saturation: &s, brightness: &b, alpha: &a)
        hue = h
        saturation = s
        brightness = b
    }

    private func updateColor() {
        dismissKeyboard()
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1).getRed(
            &r, green: &g, blue: &b, alpha: &a)
        color = KadrioColor(red: r, green: g, blue: b, alpha: color.alpha)
        hex = colorHex
    }

    private func componentInput(_ component: Binding<Double>) -> Binding<Double> {
        Binding(get: { component.wrappedValue }, set: { value in
            dismissKeyboard()
            component.wrappedValue = value
            updateColor()
        })
    }

    private func parsedHex(_ text: String) -> KadrioColor? {
        let rawDigits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard [3, 4, 6, 8].contains(rawDigits.count),
              rawDigits.allSatisfy({ "0123456789ABCDEFabcdef".contains($0) }) else { return nil }
        let digits = rawDigits.uppercased()
        let expanded = digits.count <= 4 ? digits.map { "\($0)\($0)" }.joined() : digits
        guard let number = UInt32(expanded, radix: 16) else { return nil }
        let hasAlpha = expanded.count == 8
        let rgb = hasAlpha ? number >> 8 : number
        return KadrioColor(red: Double((rgb >> 16) & 255) / 255,
                           green: Double((rgb >> 8) & 255) / 255,
                           blue: Double(rgb & 255) / 255,
                           alpha: hasAlpha ? Double(number & 255) / 255 : color.alpha)
    }

    private var hexInput: Binding<String> {
        Binding(get: { hex }, set: { text in
            hex = text
            guard let selected = parsedHex(text) else { return }
            color = selected
            syncComponents()
            opacityText = String(Int((color.alpha * 100).rounded()))
        })
    }

    private var opacityInput: Binding<String> {
        Binding(get: { opacityText }, set: { text in
            opacityText = text
            guard let value = opacityValue(text) else { return }
            color.alpha = Double(value) / 100
            hex = colorHex
        })
    }

    private func validateHexInput(_ text: String, previous: String) {
        let value = text.uppercased()
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count <= 8,
              digits.allSatisfy({ "0123456789ABCDEFabcdef".contains($0) }) else {
            hex = previous
            inputError = "color.invalidHex"
            dismissKeyboard()
            return
        }
        hex = value
    }

    private func opacityValue(_ text: String) -> Int? {
        guard !text.isEmpty, text.count <= 3,
              text.allSatisfy({ "0123456789".contains($0) }),
              let value = Int(text), (0...100).contains(value) else { return nil }
        return value
    }

    private func validateOpacityInput(_ text: String, previous: String) {
        guard text.count <= 3, text.allSatisfy({ "0123456789".contains($0) }),
              text.isEmpty || opacityValue(text) != nil else {
            opacityText = previous
            inputError = "color.invalidOpacity"
            dismissKeyboard()
            return
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @discardableResult
    private func finishEditing() -> Bool {
        guard opacityValue(opacityText) != nil else {
            inputError = "color.invalidOpacity"
            opacityText = String(Int((color.alpha * 100).rounded()))
            dismissKeyboard()
            return false
        }
        guard parsedHex(hex) != nil else {
            inputError = "color.invalidHex"
            hex = colorHex
            dismissKeyboard()
            return false
        }
        if focusedField == .hex { applyHex() }
        if focusedField == .opacity { applyOpacity() }
        dismissKeyboard()
        return true
    }

    @discardableResult
    private func applyOpacity() -> Bool {
        guard let percentage = opacityValue(opacityText) else {
            opacityText = String(Int((color.alpha * 100).rounded()))
            inputError = "color.invalidOpacity"
            return false
        }
        color.alpha = Double(percentage) / 100
        opacityText = String(percentage)
        hex = colorHex
        return true
    }

    @discardableResult
    private func applyHex() -> Bool {
        guard let selected = parsedHex(hex) else {
            hex = colorHex
            inputError = "color.invalidHex"
            return false
        }
        color = selected
        syncComponents()
        hex = hex.uppercased()
        opacityText = String(Int((color.alpha * 100).rounded()))
        return true
    }
}

private struct KadrioColorInputFrame: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
