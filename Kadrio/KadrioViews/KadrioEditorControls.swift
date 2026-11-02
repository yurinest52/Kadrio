import SwiftUI

struct KadrioEditorControls: View {
    @ObservedObject var model: KadrioEditorModel
    let isBusy: Bool
    let onSelectLayout: (KadrioCollageLayout) -> Void
    let onAddPhotos: () -> Void
    let onReplacePhoto: () -> Void
    let onFrameColor: () -> Void
    @State private var showingCorrections = false

    var body: some View {
        VStack(spacing: 12) {
            switch model.tool {
            case .collage: collageControls
            case .crop: cropControls
            case .filters: filterControls
            case .frames: frameControls
            }
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 23)).kadrioCardShadow().disabled(
            isBusy)
    }

    private var collageControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let id = model.selectedCollageSourceID, model.activeSources.contains(where: { $0.id == id }) {
                Button(action: onReplacePhoto) {
                    Label(kadrioText("collage.replacePhoto"), systemImage: "photo.on.rectangle.angled")
                        .font(.system(size: 12, weight: .medium)).padding(.horizontal, 14)
                        .frame(minHeight: 36).background(Color.kadrioBackground, in: Capsule())
                }
            }
            HStack {
                Text(kadrioText("layout")).font(.system(size: 12)).foregroundStyle(Color.kadrioSecondary)
                Spacer()
            }
            HStack(spacing: 10) {
                ForEach(KadrioCollageLayout.allCases) { layout in
                    Button {
                        onSelectLayout(layout)
                    } label: {
                        Group {
                            if let image = model.layoutThumbnails[layout] {
                                Image(uiImage: image).resizable().scaledToFit()
                            } else {
                                KadrioLayoutIcon(layout: layout)
                            }
                        }
                            .frame(width: 30, height: 32)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundStyle(model.state.collageLayout == layout ? .black : .gray.opacity(0.5))
                            .background(
                                model.state.collageLayout == layout ? .white : Color.kadrioBackground,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12).strokeBorder(
                                    model.state.collageLayout == layout ? .black : .clear, lineWidth: 1.5)
                            }
                    }
                    .buttonStyle(KadrioPressButtonStyle())
                    .accessibilityLabel(kadrioFormat("layout.number", layout.rawValue + 1))
                    .accessibilityHint(kadrioText("collage.gesture"))
                }
                Button {
                    onAddPhotos()
                } label: {
                    Image(systemName: "plus").font(.system(size: 20, weight: .light)).frame(maxWidth: .infinity).frame(
                        height: 44
                    ).background(Color.kadrioBackground, in: RoundedRectangle(cornerRadius: 12))
                }.accessibilityLabel(kadrioText("addPhoto"))
            }
            parameterSlider("spacing", value: model.editingBinding(for: \.spacing), range: 0...0.08)
            if model.activeSourceCount < 2 {
                Text(kadrioText("error.collageCount")).font(.system(size: 11)).foregroundStyle(Color.kadrioSecondary)
            }
        }
    }

    private var cropControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(KadrioCropRatio.allCases) { ratio in
                    Button {
                        model.selectCropRatio(ratio)
                    } label: {
                        VStack(spacing: 6) {
                            KadrioCropRatioIcon(ratio: ratio)
                                .frame(width: 38, height: 38).background(
                                    model.state.ratio == ratio ? .black : Color.kadrioBackground, in: Circle()
                                ).foregroundStyle(model.state.ratio == ratio ? .white : .gray)
                            Text(ratio.title).font(.system(size: 10)).foregroundStyle(
                                model.state.ratio == ratio ? .black : .gray)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(KadrioPressButtonStyle())
                }
            }
            HStack(spacing: 8) {
                ForEach(KadrioCropAction.allCases, id: \.self) { action in
                    cropAction(action) { model.perform(action) }
                }
            }
        }
    }

    private func cropAction(_ action: KadrioCropAction, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 6) {
                KadrioCropActionIcon(action: action).frame(width: 14, height: 14)
                Text(action.title)
            }.font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity)
                .frame(height: 34).background(Color.kadrioBackground, in: Capsule())
        }.buttonStyle(KadrioPressButtonStyle())
    }

    private var filterControls: some View {
        VStack(spacing: 12) {
            Picker(kadrioText("colorControls"), selection: $showingCorrections) {
                Text(kadrioText("filters")).tag(false)
                Text(kadrioText("corrections")).tag(true)
            }.pickerStyle(.segmented)
            Group {
                if showingCorrections {
                    let revision = model.correctionRevision
                    VStack(spacing: 12) {
                        parameterSlider("brightness", value: model.correctionBinding(for: \.brightness, revision: revision), range: -0.5...0.5,
                                        displayValue: Int((model.state.brightness * 200).rounded()),
                                        onEditingChanged: { model.correctionEditingChanged($0, revision: revision) })
                        parameterSlider("contrast", value: model.correctionBinding(for: \.contrast, revision: revision), range: 0.5...1.5,
                                        displayValue: Int(((model.state.contrast - 1) * 200).rounded()),
                                        onEditingChanged: { model.correctionEditingChanged($0, revision: revision) })
                        Button(kadrioText("resetCorrections")) {
                            model.resetCorrections()
                        }.font(.system(size: 12, weight: .medium)).frame(minHeight: 28)
                            .disabled(model.state.brightness == 0 && model.state.contrast == 1)
                    }.id(revision)
                } else {
                    filterOptions
                }
            }.frame(height: showingCorrections ? 144 : nil, alignment: .top)
        }
    }

    private var filterOptions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(KadrioFilter.allCases) { filter in
                    Button {
                        model.selectFilter(filter)
                    } label: {
                        VStack(spacing: 6) {
                            Group {
                                if let image = model.thumbnails[filter] {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    Color.kadrioBackground
                                }
                            }.frame(width: 43, height: 43).clipShape(Circle()).padding(3).overlay(
                                Circle().stroke(model.state.filter == filter ? .black : .clear, lineWidth: 1.5))
                            Text(filter.title).font(.system(size: 9)).foregroundStyle(
                                model.state.filter == filter ? .black : .gray
                            ).lineLimit(1).minimumScaleFactor(0.7)
                        }.frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }.buttonStyle(KadrioPressButtonStyle())
                }
            }
            if model.state.filter != .original {
                parameterSlider("intensity", value: model.editingBinding(for: \.intensity), range: 0...1)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.state.filter != .original)
    }

    private var frameControls: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 13) {
                    ForEach(KadrioFrame.allCases) { frame in
                        Button {
                            model.selectFrame(frame)
                        } label: {
                            VStack(spacing: 5) {
                                frameThumbnail(frame).frame(width: 43, height: 43).padding(6)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .inset(by: -2).strokeBorder(
                                                model.state.frame == frame ? .black : .clear, lineWidth: 2)
                                    }
                                    .overlay(alignment: .topTrailing) {
                                        if model.state.frame == frame {
                                            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.white).frame(width: 15, height: 15)
                                                .background(.black, in: Circle())
                                                .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
                                                .offset(x: 3, y: -3)
                                        }
                                    }
                                Text(frame.title).font(.system(size: 9, weight: model.state.frame == frame ? .semibold : .regular)).foregroundStyle(
                                    model.state.frame == frame ? .black : .gray)
                            }.contentShape(Rectangle())
                        }.buttonStyle(KadrioPressButtonStyle())
                            .accessibilityAddTraits(model.state.frame == frame ? .isSelected : [])
                    }
                }.padding(4)
            }.scrollIndicators(.hidden)
            if model.state.frame != .none {
                HStack(spacing: 10) {
                    ForEach(Array(KadrioFrameColorView.presets.prefix(6).enumerated()), id: \.offset) { _, color in
                        Button {
                            model.selectFrameColor(color)
                        } label: {
                            Circle().fill(Color(red: color.red, green: color.green, blue: color.blue)).frame(
                                width: 20, height: 20
                            ).overlay(Circle().stroke(.gray.opacity(0.25), lineWidth: 0.5))
                        }.accessibilityLabel(color.hex)
                    }
                    Button {
                        onFrameColor()
                    } label: {
                        Image("kadrioowncolor").resizable().scaledToFit().frame(width: 24, height: 24)
                            .frame(width: 32, height: 32)
                    }.accessibilityLabel(kadrioText("frameColor"))
                    Slider(
                        value: model.editingBinding(for: \.thickness), in: 0.01...0.14,
                        onEditingChanged: model.sliderEditingChanged
                    ).accessibilityLabel(
                        kadrioText("thickness"))
                }
            }
        }
    }

    private func frameThumbnail(_ frame: KadrioFrame) -> some View {
        Group {
            if frame == .none {
                RoundedRectangle(cornerRadius: 5).fill(Color.kadrioBackground)
                    .overlay {
                        Image(systemName: "xmark").foregroundStyle(model.state.frame == .none ? .black : .gray)
                    }
            } else if let image = model.frameThumbnails[frame] {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 5).fill(Color.kadrioBackground)
            }
        }
    }

    private func parameterSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, displayValue: Int? = nil,
                                 onEditingChanged: ((Bool) -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title == "spacing" ? kadrioText(title) : displayValue.map { String(format: kadrioText("correction.value"), kadrioText(title), $0) }
                 ?? String(format: kadrioText("parameter.value"), kadrioText(title), Int(value.wrappedValue * 100)))
                .font(.system(size: 10)).foregroundStyle(Color.kadrioSecondary)
            Slider(
                value: value, in: range,
                onEditingChanged: onEditingChanged ?? model.sliderEditingChanged
            ).accessibilityLabel(kadrioText(title))
        }
    }

}

struct KadrioLayoutIcon: View {
    let layout: KadrioCollageLayout
    var body: some View {
        GeometryReader { geometry in
            let cells = KadrioGeometry.cells(
                count: layout.photoCount, layout: layout.rawValue, size: geometry.size, spacing: 0.075)
            ForEach(Array(cells.enumerated()), id: \.offset) { _, rect in
                RoundedRectangle(cornerRadius: 2).frame(width: rect.width, height: rect.height).position(
                    x: rect.midX, y: rect.midY)
            }
        }
    }
}
