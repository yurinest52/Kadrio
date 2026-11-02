import SwiftUI

struct KadrioEditorHeader: View {
    @ObservedObject var model: KadrioEditorModel
    let isSaving: Bool
    let isImporting: Bool
    let isSaveRequested: Bool
    let showSaveSpinner: Bool
    let close: () -> Void
    let save: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            KadrioCircleButton(symbol: "xmark", label: kadrioText("close")) {
                close()
            }.accessibilityIdentifier("KadrioEditorClose")
            Spacer()
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 42, height: 44)
            }.disabled(model.undoStates.isEmpty).accessibilityLabel(kadrioText("undo")).accessibilityIdentifier(
                "KadrioEditorUndo")
            Button {
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 42, height: 44)
            }.disabled(model.redoStates.isEmpty).accessibilityLabel(kadrioText("redo")).accessibilityIdentifier(
                "KadrioEditorRedo")
            Spacer()
            Button {
                save()
            } label: {
                ZStack {
                    Text(kadrioText("save")).hidden()
                    HStack(spacing: 6) {
                        Text(kadrioText("alreadySaved"))
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                    }.hidden()
                    HStack(spacing: 6) {
                        Text(kadrioText(model.isCurrentResultSaved ? "alreadySaved" : "save"))
                        if showSaveSpinner { ProgressView().tint(.white).scaleEffect(0.65) }
                        else if model.isCurrentResultSaved {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                        }
                    }
                }.lineLimit(1).minimumScaleFactor(0.65)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 14).frame(
                    height: 32
                ).background(.black, in: Capsule())
                    .frame(minHeight: 44)
            }.accessibilityLabel(kadrioText(model.isCurrentResultSaved ? "alreadySaved" : isSaveRequested ? "saving" : "save")).accessibilityIdentifier("KadrioEditorSave").disabled(
                isSaveRequested || isSaving || isImporting || model.activeSourceCount == 0 || model.isCurrentResultSaved)
        }.padding(.horizontal, 16).disabled(isSaving)
    }

}

struct KadrioEditorToolBar: View {
    @ObservedObject var model: KadrioEditorModel
    let isBusy: Bool
    let select: (KadrioTool) -> Void

    var body: some View {
        HStack {
            ForEach(KadrioTool.allCases) { tool in
                Button {
                    select(tool)
                } label: {
                    VStack(spacing: 5) {
                        KadrioToolIcon(tool: tool)
                            .frame(width: 22, height: 22)
                            .frame(width: 42, height: 42)
                            .foregroundStyle(model.tool == tool ? .white : Color.kadrioSecondary)
                            .background(model.tool == tool ? .black : .clear, in: Circle())
                            .shadow(color: .black.opacity(model.tool == tool ? 0.16 : 0), radius: 5, y: 3)
                            .offset(y: model.tool == tool ? -5 : 0)
                        Text(tool.title).font(.system(size: 10)).foregroundStyle(model.tool == tool ? .black : .gray)
                    }.frame(maxWidth: .infinity).contentShape(Rectangle())
                }.buttonStyle(KadrioPressButtonStyle()).accessibilityIdentifier("KadrioEditorTool-" + tool.rawValue)
            }
        }.padding(.horizontal, 16).padding(.bottom, 8).background(.white).disabled(isBusy)
    }

}
