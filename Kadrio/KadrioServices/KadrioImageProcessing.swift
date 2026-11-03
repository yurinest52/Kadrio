import Foundation
import UIKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import CoreTransferable

struct KadrioImportFile: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("KadrioTransfer-\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: url)
            return Self(url: url)
        }
    }
}

actor KadrioImageProcessing {
    static let shared = KadrioImageProcessing()
    private let previewSources: NSCache<NSString, CIImage> = {
        let cache = NSCache<NSString, CIImage>()
        cache.countLimit = 12
        cache.totalCostLimit = KadrioImageQuality.previewSourceCacheLimit
        return cache
    }()
    private struct FramePreviewContent {
        let key: KadrioRenderKey
        let maxPixel: Double
        let image: CIImage
    }
    private var framePreviewContent: FramePreviewContent?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private lazy var context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: colorSpace])

    func importSource(url: URL) throws -> KadrioSource {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KadrioEditing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let original = folder.appendingPathComponent("KadrioOriginal.\(url.pathExtension.isEmpty ? "jpg" : url.pathExtension)")
            try FileManager.default.copyItem(at: url, to: original)
            guard let source = CGImageSourceCreateWithURL(original as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw KadrioError.invalidImage }
            let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
            let preview = folder.appendingPathComponent("KadrioPreview.jpg")
            try thumbnail(from: original, to: preview, maxPixel: Int(KadrioImageQuality.previewMaxPixel))
            return KadrioSource(id: UUID(), url: original, previewURL: preview, pixelWidth: orientation >= 5 ? height : width, pixelHeight: orientation >= 5 ? width : height)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func importCamera(_ image: UIImage) throws -> KadrioSource {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KadrioCamera-\(UUID()).jpg")
        guard let data = image.jpegData(compressionQuality: 0.98) else { throw KadrioError.invalidImage }
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try importSource(url: url)
    }

    func thumbnail(from url: URL, to target: URL, maxPixel: Int = 500) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceShouldCacheImmediately: true] as CFDictionary), let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw KadrioError.invalidImage }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw KadrioError.storage }
    }

    private func normalized(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    private func previewSize(for source: KadrioSource, maxPixel: Double = KadrioImageQuality.previewMaxPixel) -> CGSize {
        let scale = min(1, maxPixel / Double(max(source.pixelWidth, source.pixelHeight)))
        return CGSize(width: Double(source.pixelWidth) * scale, height: Double(source.pixelHeight) * scale)
    }

    private func previewLevels(for source: KadrioSource) -> [Int] {
        let originalMaxPixel = max(source.pixelWidth, source.pixelHeight)
        return Array(Set(KadrioImageQuality.previewSourceLevels.map { min($0, originalMaxPixel) })).sorted()
    }

    private func previewCacheKey(_ source: KadrioSource, maxPixel: Int) -> NSString {
        "\(source.id.uuidString):\(maxPixel)" as NSString
    }

    private func previewResolutions(sources: [KadrioSource], state: KadrioEditState, size: CGSize,
                                    cells: [CGRect]? = nil, maxPixel: Double) -> [Int] {
        let orientation = KadrioGeometry.orientationTransform(size, turns: state.turns, flipped: state.flipped)
        let orientedSize = CGRect(origin: .zero, size: size).applying(orientation).size
        let cropSize = KadrioGeometry.cropSize(orientedSize, ratio: state.cropAspectRatio)
        let cropRect = CGRect(origin: .zero, size: cropSize)
        let cropTransform = KadrioGeometry.placementTransform(orientedSize, in: cropRect, placement: state.crop)
        let canvasToCrop = orientation.concatenating(cropTransform)
        let bounds = KadrioGeometry.frameBounds(cropSize, state: state)
        let outputScale = maxPixel / max(bounds.width, bounds.height)
        let levels = sources.map { previewLevels(for: $0) }
        var selections = sources.indices.map { index -> Int in
            let sourceSize = previewSize(for: sources[index])
            var required = KadrioImageQuality.previewMaxPixel
            if let cells {
                if cells.indices.contains(index), !cells[index].applying(canvasToCrop).intersection(cropRect).isEmpty {
                    let placement = state.placements[index]
                    let scale = max(cells[index].width / sourceSize.width, cells[index].height / sourceSize.height) * placement.zoom
                    required = max(sourceSize.width, sourceSize.height) * scale * cropTransform.a * outputScale
                }
            } else {
                required = max(sourceSize.width, sourceSize.height) * cropTransform.a * outputScale
            }
            return levels[index].firstIndex { Double($0) + 1 >= required } ?? (levels[index].count - 1)
        }
        func cost(_ index: Int) -> Int {
            let source = sources[index]
            let pixels = Double(levels[index][selections[index]])
            let aspect = Double(min(source.pixelWidth, source.pixelHeight)) / Double(max(source.pixelWidth, source.pixelHeight))
            return Int(ceil(pixels * pixels * aspect)) * 4
        }
        while sources.indices.reduce(0, { $0 + cost($1) }) > KadrioImageQuality.previewSourceMemoryBudget {
            guard let index = sources.indices.filter({ selections[$0] > 0 }).max(by: { cost($0) < cost($1) }) else { break }
            selections[index] -= 1
        }
        return sources.indices.map { levels[$0][selections[$0]] }
    }

    private func image(_ source: KadrioSource, preview: Bool, maxPixel: Int = Int(KadrioImageQuality.previewMaxPixel)) throws -> CIImage {
        if preview {
            let resolution = min(maxPixel, max(source.pixelWidth, source.pixelHeight))
            let key = previewCacheKey(source, maxPixel: resolution)
            if let cached = previewSources.object(forKey: key) { return cached }
            try Task.checkCancellation()
            let url = resolution <= Int(KadrioImageQuality.previewMaxPixel) ? source.previewURL : source.url
            guard let file = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let decoded = CGImageSourceCreateThumbnailAtIndex(file, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: resolution,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw KadrioError.invalidImage }
            let size = previewSize(for: source, maxPixel: Double(resolution))
            let result = CIImage(cgImage: decoded).transformed(by: CGAffineTransform(
                scaleX: size.width / CGFloat(decoded.width), y: size.height / CGFloat(decoded.height)))
            previewSources.setObject(result, forKey: key, cost: decoded.bytesPerRow * decoded.height)
            return result
        }
        guard let result = CIImage(contentsOf: source.url, options: [.applyOrientationProperty: true]) else { throw KadrioError.invalidImage }
        return normalized(result)
    }

    private func positioned(_ image: CIImage, in rect: CGRect, placement: KadrioPlacement) -> CIImage {
        image.transformed(by: KadrioGeometry.placementTransform(image.extent.size, in: rect, placement: placement)).cropped(to: rect)
    }

    private func adjusted(_ image: CIImage, state: KadrioEditState) -> CIImage {
        guard state.brightness != 0 || state.contrast != 1 else { return image }
        return image.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: state.brightness, kCIInputContrastKey: state.contrast,
            kCIInputSaturationKey: 1
        ]).cropped(to: image.extent)
    }

    private func filtered(_ image: CIImage, filter: KadrioFilter, intensity: Double) -> CIImage {
        guard filter != .original, intensity > 0 else { return image }
        let effect: CIImage
        switch filter {
        case .original: return image
        case .vivid: effect = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.6, kCIInputContrastKey: 1.14, kCIInputBrightnessKey: 0.025])
        case .mono: effect = image.applyingFilter("CIPhotoEffectNoir")
        case .warm: effect = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 4800, y: 0)])
        case .cool: effect = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 9000, y: 0)])
        }
        return image.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: effect, kCIInputTimeKey: intensity]).cropped(to: image.extent)
    }

    private func framed(_ image: CIImage, state: KadrioEditState) -> CIImage {
        guard state.frame != .none else { return image }
        let contentRect = KadrioGeometry.frameContentRect(image.extent.size, state: state)
        let border = contentRect.minX
        let rect = KadrioGeometry.frameBounds(image.extent.size, state: state)
        let color = CIColor(red: state.frameColor.red, green: state.frameColor.green, blue: state.frameColor.blue, alpha: state.frameColor.alpha)
        let background = CIImage(color: color).composited(over: CIImage(color: .white)).cropped(to: rect)
        var content = image.transformed(by: CGAffineTransform(translationX: border, y: contentRect.minY))
        if state.frame == .rounded {
            let mask = (CIFilter(name: "CIRoundedRectangleGenerator", parameters: ["inputExtent": CIVector(cgRect: contentRect), "inputRadius": border * 2, "inputColor": CIColor.white])?.outputImage ?? CIImage(color: .white)).cropped(to: rect)
            content = content.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask])
        }
        var output = content.composited(over: background).cropped(to: rect)
        if state.frame == .double {
            let (outer, inner) = KadrioGeometry.doubleFrameRects(contentRect)
            let band = CIImage(color: color).cropped(to: outer)
            let center = output.cropped(to: inner)
            output = center.composited(over: band.composited(over: output)).cropped(to: rect)
        }
        return output
    }

    private func render(sources: [KadrioSource], state: KadrioEditState, preview: Bool, collageSize: CGSize? = nil, maxPixel: Double = KadrioImageQuality.previewMaxPixel, includeFrame: Bool = true) throws -> CIImage {
        let sources = Array(sources.prefix(state.sourceCount))
        guard let first = sources.first else { throw KadrioError.invalidImage }
        var result: CIImage
        if state.collage, sources.count >= 2 || collageSize != nil {
            let size = collageSize ?? KadrioGeometry.collageSize(preview: preview)
            let rect = CGRect(origin: .zero, size: size)
            result = CIImage(color: .white).cropped(to: rect)
            let count = collageSize == nil ? sources.count : (KadrioCollageLayout(rawValue: state.layout)?.photoCount ?? sources.count)
            let cells = KadrioGeometry.collageImageCells(count: count, layout: state.layout, size: size, spacing: state.spacing, split: state.collageSplit)
            let resolutions = preview ? previewResolutions(sources: sources, state: state, size: size, cells: cells, maxPixel: maxPixel) : []
            for (index, cell) in cells.enumerated() {
                guard sources.indices.contains(index) else { continue }
                let source = adjusted(try image(sources[index], preview: preview,
                    maxPixel: preview ? resolutions[index] : Int(KadrioImageQuality.previewMaxPixel)), state: state)
                let content = positioned(source, in: cell, placement: state.placements[index])
                let mask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: ["inputExtent": CIVector(cgRect: cell), "inputRadius": KadrioGeometry.collageCornerRadius(size), "inputColor": CIColor.white])?.outputImage ?? CIImage(color: .white)
                let rounded = content.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .white).cropped(to: cell), kCIInputMaskImageKey: mask]).cropped(to: cell)
                result = rounded.composited(over: result)
            }
        } else {
            let resolution = preview ? previewResolutions(sources: [first], state: state,
                size: previewSize(for: first), maxPixel: maxPixel)[0] : Int(KadrioImageQuality.previewMaxPixel)
            result = adjusted(try image(first, preview: preview, maxPixel: resolution), state: state)
        }
        result = normalized(result.transformed(by: KadrioGeometry.orientationTransform(result.extent.size, turns: state.turns, flipped: state.flipped)))
        let ratio = state.cropAspectRatio
        let cropSize = KadrioGeometry.cropSize(result.extent.size, ratio: ratio)
        result = positioned(result, in: CGRect(origin: .zero, size: cropSize), placement: state.crop)
        result = filtered(result, filter: state.filter, intensity: state.intensity)
        let content = normalized(result)
        return includeFrame ? framed(content, state: state) : content
    }

    func layoutThumbnail(sources: [KadrioSource], state: KadrioEditState) throws -> UIImage {
        try Task.checkCancellation()
        return try autoreleasepool {
            let image = try render(sources: sources, state: state, preview: true, collageSize: KadrioImageQuality.layoutThumbnailSize, maxPixel: KadrioImageQuality.layoutThumbnailSize.height)
            guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colorSpace) else { throw KadrioError.invalidImage }
            return UIImage(cgImage: cg)
        }
    }

    func cropSourceSize(sources: [KadrioSource], state: KadrioEditState) throws -> CGSize {
        guard let first = sources.first else { throw KadrioError.invalidImage }
        let size = state.collage && state.sourceCount >= 2
            ? KadrioGeometry.collageSize(preview: true) : previewSize(for: first)
        return CGRect(origin: .zero, size: size)
            .applying(KadrioGeometry.orientationTransform(size, turns: state.turns, flipped: state.flipped)).size
    }

    func previewFrame(sources: [KadrioSource], state: KadrioEditState, maxPixel: Double,
                      frameEditing: Bool = false, interactive: Bool = false) throws -> (image: UIImage, cropSourceSize: CGSize) {
        let size = try cropSourceSize(sources: sources, state: state)
        return (try preview(sources: sources, state: state, maxPixel: maxPixel,
                            frameEditing: frameEditing, interactive: interactive), size)
    }

    func preview(sources: [KadrioSource], state: KadrioEditState, maxPixel: Double = KadrioImageQuality.previewMaxPixel,
                 frameEditing: Bool = false, interactive: Bool = false) throws -> UIImage {
        try Task.checkCancellation()
        return try autoreleasepool {
            let image = try framePreview(sources: sources, state: state, maxPixel: maxPixel,
                                         enabled: frameEditing, interactive: interactive)
            let scale = min(1, maxPixel / max(image.extent.width, image.extent.height))
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cgImage = context.createCGImage(scaled, from: scaled.extent, format: .RGBA8, colorSpace: colorSpace) else { throw KadrioError.invalidImage }
            return UIImage(cgImage: cgImage)
        }
    }

    private func framePreview(sources: [KadrioSource], state: KadrioEditState, maxPixel: Double,
                              enabled: Bool, interactive: Bool) throws -> CIImage {
        guard enabled, state.frame != .none else {
            return try render(sources: sources, state: state, preview: true, maxPixel: maxPixel)
        }
        var keyState = state
        keyState.frameColor = KadrioColor()
        let key = KadrioRenderKey(state: keyState, sourceIDs: sources.map(\.id))
        if interactive, let cached = framePreviewContent, cached.key == key, cached.maxPixel == maxPixel {
            return framed(cached.image, state: state)
        }
        let content = try render(sources: sources, state: state, preview: true, maxPixel: maxPixel, includeFrame: false)
        let result = framed(content, state: state)
        let scale = min(1, maxPixel / max(result.extent.width, result.extent.height))
        let scaled = content.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        if let cg = context.createCGImage(scaled, from: scaled.extent, format: .RGBA8, colorSpace: colorSpace) {
            let cached = CIImage(cgImage: cg).transformed(by: CGAffineTransform(
                scaleX: content.extent.width / CGFloat(cg.width), y: content.extent.height / CGFloat(cg.height)))
            framePreviewContent = FramePreviewContent(key: key, maxPixel: maxPixel, image: cached)
        }
        return result
    }

    func export(sources: [KadrioSource], state: KadrioEditState) throws -> URL {
        try autoreleasepool {
            let image = try render(sources: sources, state: state, preview: false)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("KadrioExport-\(UUID()).jpg")
            try context.writeJPEGRepresentation(of: image, to: url, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.96])
            return url
        }
    }

    func clean(_ sources: [KadrioSource]) {
        let removed = Set(sources.map(\.id))
        if let cached = framePreviewContent, cached.key.sourceIDs.contains(where: { removed.contains($0) }) {
            framePreviewContent = nil
        }
        for source in sources {
            for resolution in previewLevels(for: source) {
                previewSources.removeObject(forKey: previewCacheKey(source, maxPixel: resolution))
            }
            let directory = source.url.deletingLastPathComponent()
            guard directory.lastPathComponent.hasPrefix("KadrioEditing-") else { continue }
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
