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
    var hex: String {
        String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

struct KadrioEditState: Codable, Equatable, Sendable {
    var collage = false
    var sourceCount = 1
    var layout = 1
    var spacing: Double = 0.02
    var placements = Array(repeating: KadrioPlacement(), count: 4)
    var ratio: KadrioCropRatio = .free
    var freeRatio: Double = 0.8
    var crop = KadrioPlacement()
    var turns = 0
    var flipped = false
    var filter: KadrioFilter = .original
    var intensity: Double = 0.8
    var frame: KadrioFrame = .none
    var frameColor = KadrioColor()
    var thickness: Double = 0.04
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
    case invalidImage, storage, noTokens, photoAccess, cameraAccess, cameraUnavailable, collageCount, configuration
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
        }
    }
}

struct KadrioGeometry {
    static func cropSize(_ size: CGSize, ratio: Double) -> CGSize {
        let ratio = max(0.1, ratio)
        if size.width / size.height > ratio {
            return CGSize(width: size.height * ratio, height: size.height)
        }
        return CGSize(width: size.width, height: size.width / ratio)
    }

    static func cells(count: Int, layout: Int, size: CGSize, spacing: Double) -> [CGRect] {
        let requested = KadrioCollageLayout(rawValue: layout) ?? .feature
        let selected = count >= requested.photoCount ? requested : KadrioCollageLayout.initial(for: count)
        let gap = min(size.width, size.height) * spacing
        let outer = CGRect(origin: .zero, size: size).insetBy(dx: gap, dy: gap)
        let w = (outer.width - gap) / 2
        let h = (outer.height - gap) / 2
        let left = CGRect(x: outer.minX, y: outer.minY, width: w, height: outer.height)
        let right = CGRect(x: outer.minX + w + gap, y: outer.minY, width: w, height: outer.height)
        let topLeft = CGRect(x: outer.minX, y: outer.minY, width: w, height: h)
        let topRight = CGRect(x: right.minX, y: outer.minY, width: w, height: h)
        let bottomLeft = CGRect(x: outer.minX, y: outer.minY + h + gap, width: w, height: h)
        let bottomRight = CGRect(x: right.minX, y: bottomLeft.minY, width: w, height: h)
        switch selected {
        case .columns: return [left, right]
        case .feature: return [left, topRight, bottomRight]
        case .top: return [CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: h), bottomLeft, bottomRight]
        case .grid: return [topLeft, topRight, bottomLeft, bottomRight]
        }
    }
}
