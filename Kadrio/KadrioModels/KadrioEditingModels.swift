import Foundation
import CoreGraphics

func kadrioText(_ key: String) -> String {
    NSLocalizedString(key, tableName: "KadrioLocalizable", bundle: .main, comment: "")
}

func kadrioFormat(_ key: String, _ value: Int) -> String {
    String(format: kadrioText(key), value)
}


enum KadrioTool: String, CaseIterable, Codable, Identifiable, Sendable {
    case collage, crop, filters, frames
    var id: String { rawValue }
    var title: String { kadrioText(rawValue) }
    var asset: String {
        switch self {
        case .collage: "KadrioCollageToolPhoto"
        case .crop: "KadrioCropToolPhoto"
        case .filters: "KadrioFiltersToolPhoto"
        case .frames: "KadrioPortraitPreview"
        }
    }
}


enum KadrioCollageLayout: Int, CaseIterable, Identifiable, Sendable {
    case columns, feature, top, grid
    var id: Int { rawValue }
    var photoCount: Int {
        switch self {
        case .columns: 2
        case .feature, .top: 3
        case .grid: 4
        }
    }
    static func initial(for count: Int) -> Self {
        switch count {
        case ...2: .columns
        case 3: .feature
        default: .grid
        }
    }
}


enum KadrioCropAction: String, CaseIterable {
    case rotate, flip, reset
    var title: String { kadrioText(rawValue) }
}


enum KadrioImageQuality {
    static let previewMaxPixel: Double = 1400
    static let previewSourceLevels = [1400, 2800, 4200]
    static let previewSourceMemoryBudget = 128 * 1024 * 1024
    static let previewSourceCacheLimit = 160 * 1024 * 1024
    static let filterThumbnailMaxPixel: Double = 160
    static let layoutThumbnailSize = CGSize(width: 140, height: 175)
}


enum KadrioFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, vivid, mono, warm, cool
    var id: String { rawValue }
    var title: String { kadrioText(rawValue) }
}


enum KadrioFrame: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, white, black, polaroid, rounded, double
    var id: String { rawValue }
    var title: String { kadrioText(rawValue) }
}


enum KadrioCropRatio: String, Codable, CaseIterable, Identifiable, Sendable {
    case free, square, portrait, story, landscape
    var id: String { rawValue }
    var title: String {
        switch self {
        case .free: kadrioText("free")
        case .square: "1:1"
        case .portrait: "4:5"
        case .story: "9:16"
        case .landscape: "16:9"
        }
    }
    var value: Double? {
        switch self {
        case .free: nil
        case .square: 1
        case .portrait: 0.8
        case .story: 9.0 / 16
        case .landscape: 16.0 / 9
        }
    }
}


struct KadrioPlacement: Codable, Equatable, Sendable {
    var zoom: Double = 1
    var x: Double = 0
    var y: Double = 0
}


struct KadrioColor: Codable, Equatable, Sendable {
    var red: Double = 1
    var green: Double = 1
    var blue: Double = 1
    var alpha: Double = 1

    init(red: Double = 1, green: Double = 1, blue: Double = 1, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    private enum CodingKeys: String, CodingKey { case red, green, blue, alpha }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        red = try values.decode(Double.self, forKey: .red)
        green = try values.decode(Double.self, forKey: .green)
        blue = try values.decode(Double.self, forKey: .blue)
        alpha = min(1, max(0, try values.decodeIfPresent(Double.self, forKey: .alpha) ?? 1))
    }

    var hex: String {
        String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}


struct KadrioCollageSplit: Codable, Equatable, Sendable {
    var x: Double = 0.5
    var y: Double = 0.5
}


enum KadrioCollageDivider: Int, CaseIterable, Identifiable {
    case vertical, horizontal
    var id: Int { rawValue }
}


struct KadrioEditState: Codable, Equatable, Sendable {
    var collage = false
    var sourceCount = 1
    var layout = 1
    var collageLayout: KadrioCollageLayout {
        get { KadrioCollageLayout(rawValue: layout) ?? .feature }
        set { layout = newValue.rawValue }
    }
    var collageSplits: [Int: KadrioCollageSplit]?
    var collageSplit: KadrioCollageSplit { collageSplits?[layout] ?? KadrioCollageSplit() }
    var spacing: Double = 0.02
    var placements = Array(repeating: KadrioPlacement(), count: 4)
    var ratio: KadrioCropRatio = .free
    var freeRatio: Double = 0.8
    var cropRatioInverted = false
    var cropAspectRatio: Double {
        let value = ratio.value ?? freeRatio
        return cropRatioInverted ? 1 / value : value
    }
    var crop = KadrioPlacement()
    var turns = 0
    var flipped = false
    var filter: KadrioFilter = .original
    var intensity: Double = 0.8
    var brightness: Double = 0
    var contrast: Double = 1
    var frame: KadrioFrame = .none
    var frameColor = KadrioColor()
    var thickness: Double = 0.04

    func selectingFrame(_ selected: KadrioFrame) -> Self {
        guard selected != frame else { return self }
        var value = self
        value.frame = selected
        if selected == .black { value.frameColor = KadrioColor(red: 0.06, green: 0.06, blue: 0.06) }
        else { value.frameColor = KadrioColor() }
        value.thickness = Self().thickness
        return value
    }
}


struct KadrioRenderKey: Equatable {
    let sourceIDs: [UUID]
    let state: KadrioEditState

    init(state: KadrioEditState, sourceIDs: [UUID]) {
        var value = state
        var ids = Array(sourceIDs.prefix(max(0, state.sourceCount)))
        if value.collage, ids.count >= 2 {
            let requested = value.collageLayout
            let layout = ids.count >= requested.photoCount ? requested : KadrioCollageLayout.initial(for: ids.count)
            value.collageLayout = layout
            ids = Array(ids.prefix(layout.photoCount))
            value.placements = Array(value.placements.prefix(ids.count))
        } else {
            ids = Array(ids.prefix(1))
            value.collage = false
            value.collageLayout = .columns
            value.spacing = 0
            value.placements = []
        }
        if value.collage {
            var split = state.collageSplit
            if value.collageLayout == .columns { split.y = 0.5 }
            value.collageSplits = split == KadrioCollageSplit() ? nil : [value.layout: split]
        } else { value.collageSplits = nil }
        value.sourceCount = ids.count
        if value.frame == .none {
            value.frameColor = KadrioColor()
            value.thickness = 0
        } else {
            if value.frame == .black { value.frame = .white }
            if value.frameColor.alpha == 0 { value.frameColor = KadrioColor(alpha: 0) }
        }
        if value.filter == .original || value.intensity <= 0 {
            value.filter = .original
            value.intensity = 0
        }
        value.freeRatio = max(0.1, value.cropAspectRatio)
        value.ratio = .free
        value.cropRatioInverted = false
        value.turns = (value.turns % 4 + 4) % 4
        self.sourceIDs = ids
        self.state = value
    }
}


struct KadrioWork: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let fileName: String
    let thumbnailName: String
    let createdAt: Date
    let tool: KadrioTool
}


struct KadrioLedger: Codable, Equatable, Sendable {
    var tokens = 3
    var works: [KadrioWork] = []
}


struct KadrioSource: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let previewURL: URL
    let pixelWidth: Int
    let pixelHeight: Int
}


struct KadrioEditorRequest: Identifiable {
    let id = UUID()
    let sources: [KadrioSource]
    let tool: KadrioTool
}


enum KadrioError: LocalizedError {
    case invalidImage, storage, noTokens, photoAccess, cameraAccess, cameraUnavailable, collageCount, configuration, saveUncertain, pendingFilesMissing
    var errorDescription: String? {
        switch self {
        case .invalidImage: kadrioText("error.image")
        case .storage: kadrioText("error.storage")
        case .noTokens: kadrioText("error.tokens")
        case .photoAccess: kadrioText("error.photos")
        case .cameraAccess: kadrioText("error.camera")
        case .cameraUnavailable: kadrioText("error.cameraUnavailable")
        case .collageCount: kadrioText("error.collageCount")
        case .configuration: kadrioText("error.configuration")
        case .saveUncertain: kadrioText("error.saveUncertain")
        case .pendingFilesMissing: kadrioText("error.pendingFilesMissing")
        }
    }
}
