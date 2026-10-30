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
            try thumbnail(from: original, to: preview, maxPixel: 1400)
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

    private func image(_ source: KadrioSource, preview: Bool) throws -> CIImage {
        guard let result = CIImage(contentsOf: preview ? source.previewURL : source.url, options: [.applyOrientationProperty: true]) else { throw KadrioError.invalidImage }
        return normalized(result)
    }

    private func positioned(_ image: CIImage, in rect: CGRect, placement: KadrioPlacement) -> CIImage {
        let scale = max(rect.width / image.extent.width, rect.height / image.extent.height) * placement.zoom
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let excessX = max(0, scaled.extent.width - rect.width)
        let excessY = max(0, scaled.extent.height - rect.height)
        let x = rect.minX - excessX * (1 - min(1, max(-1, placement.x))) / 2
        let y = rect.minY - excessY * (1 + min(1, max(-1, placement.y))) / 2
        return scaled.transformed(by: CGAffineTransform(translationX: x, y: y)).cropped(to: rect)
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
        let border = min(image.extent.width, image.extent.height) * state.thickness
        let bottom = state.frame == .polaroid ? border * 3.5 : border
        let rect = CGRect(x: 0, y: 0, width: image.extent.width + border * 2, height: image.extent.height + border + bottom).integral
        let color = CIColor(red: state.frameColor.red, green: state.frameColor.green, blue: state.frameColor.blue)
        let background = CIImage(color: color).cropped(to: rect)
        let contentRect = CGRect(x: border, y: bottom, width: image.extent.width, height: image.extent.height)
        var content = image.transformed(by: CGAffineTransform(translationX: border, y: bottom))
        if state.frame == .rounded {
            let mask = (CIFilter(name: "CIRoundedRectangleGenerator", parameters: ["inputExtent": CIVector(cgRect: contentRect), "inputRadius": border * 2, "inputColor": CIColor.white])?.outputImage ?? CIImage(color: .white)).cropped(to: rect)
            content = content.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask])
        }
        var output = content.composited(over: background).cropped(to: rect)
        if state.frame == .double {
            let outer = contentRect.insetBy(dx: border * 0.24, dy: border * 0.24)
            let inner = outer.insetBy(dx: border * 0.16, dy: border * 0.16)
            let band = CIImage(color: color).cropped(to: outer)
            let center = output.cropped(to: inner)
            output = center.composited(over: band.composited(over: output)).cropped(to: rect)
        }
        return output
    }

    private func render(sources: [KadrioSource], state: KadrioEditState, preview: Bool) throws -> CIImage {
        let sources = Array(sources.prefix(state.sourceCount))
        guard let first = sources.first else { throw KadrioError.invalidImage }
        var result: CIImage
        if state.collage, sources.count >= 2 {
            let size = CGSize(width: preview ? 1100 : 4000, height: preview ? 1375 : 5000)
            let rect = CGRect(origin: .zero, size: size)
            result = CIImage(color: .white).cropped(to: rect)
            let cells = KadrioGeometry.cells(count: sources.count, layout: state.layout, size: size, spacing: state.spacing)
            for (index, topRect) in cells.enumerated() {
                let cell = CGRect(x: topRect.minX, y: size.height - topRect.maxY, width: topRect.width, height: topRect.height)
                let source = try image(sources[index], preview: preview)
                let content = positioned(source, in: cell, placement: state.placements[index])
                let mask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: ["inputExtent": CIVector(cgRect: cell), "inputRadius": min(size.width, size.height) * 0.012, "inputColor": CIColor.white])?.outputImage ?? CIImage(color: .white)
                let rounded = content.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .white).cropped(to: cell), kCIInputMaskImageKey: mask]).cropped(to: cell)
                result = rounded.composited(over: result)
            }
        } else {
            result = try image(first, preview: preview)
        }
        if state.turns % 4 != 0 {
            result = normalized(result.transformed(by: CGAffineTransform(rotationAngle: -Double(state.turns % 4) * .pi / 2)))
        }
        if state.flipped {
            result = normalized(result.transformed(by: CGAffineTransform(scaleX: -1, y: 1)))
        }
        let ratio = state.ratio.value ?? state.freeRatio
        let cropSize = KadrioGeometry.cropSize(result.extent.size, ratio: ratio)
        result = positioned(result, in: CGRect(origin: .zero, size: cropSize), placement: state.crop)
        result = filtered(result, filter: state.filter, intensity: state.intensity)
        return framed(normalized(result), state: state)
    }

    func preview(sources: [KadrioSource], state: KadrioEditState) throws -> UIImage {
        try Task.checkCancellation()
        return try autoreleasepool {
            let image = try render(sources: sources, state: state, preview: true)
            let scale = min(1, 1400 / max(image.extent.width, image.extent.height))
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cgImage = context.createCGImage(scaled, from: scaled.extent, format: .RGBA8, colorSpace: colorSpace) else { throw KadrioError.invalidImage }
            return UIImage(cgImage: cgImage)
        }
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
        for source in sources {
            let directory = source.url.deletingLastPathComponent()
            guard directory.lastPathComponent.hasPrefix("KadrioEditing-") else { continue }
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
