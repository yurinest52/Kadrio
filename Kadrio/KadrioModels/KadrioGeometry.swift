import Foundation
import CoreGraphics


struct KadrioGeometry {
    static let photoZoomRange = 1.0...6.0

    static func clampedZoom(_ zoom: Double) -> Double {
        min(photoZoomRange.upperBound, max(photoZoomRange.lowerBound, zoom))
    }

    static func collageSize(preview: Bool) -> CGSize {
        CGSize(width: preview ? 1100 : 4000, height: preview ? 1375 : 5000)
    }

    static func collageImageCells(count: Int, layout: Int, size: CGSize, spacing: Double, split: KadrioCollageSplit = KadrioCollageSplit()) -> [CGRect] {
        cells(count: count, layout: layout, size: size, spacing: spacing, split: split).map {
            CGRect(x: $0.minX, y: size.height - $0.maxY, width: $0.width, height: $0.height)
        }
    }

    static func collageCornerRadius(_ size: CGSize) -> CGFloat {
        min(size.width, size.height) * 0.012
    }

    static func placementTransform(_ size: CGSize, in rect: CGRect, placement: KadrioPlacement) -> CGAffineTransform {
        let scale = max(rect.width / size.width, rect.height / size.height) * placement.zoom
        let excessX = max(0, size.width * scale - rect.width)
        let excessY = max(0, size.height * scale - rect.height)
        let x = rect.minX - excessX * (1 - min(1, max(-1, placement.x))) / 2
        let y = rect.minY - excessY * (1 + min(1, max(-1, placement.y))) / 2
        return CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: x, y: y))
    }

    static func orientationTransform(_ size: CGSize, turns: Int, flipped: Bool) -> CGAffineTransform {
        let rotation = CGAffineTransform(rotationAngle: -Double(turns % 4) * .pi / 2)
        let bounds = CGRect(origin: .zero, size: size).applying(rotation)
        var transform = rotation.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        if flipped {
            transform = transform.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: bounds.width, ty: 0))
        }
        return transform
    }

    static func pannedCrop(_ placement: KadrioPlacement, sourceSize: CGSize, previewSize: CGSize, state: KadrioEditState, translation: CGSize) -> KadrioPlacement {
        let crop = cropSize(sourceSize, ratio: state.cropAspectRatio)
        let bounds = frameBounds(crop, state: state)
        let scale = max(crop.width / sourceSize.width, crop.height / sourceSize.height) * placement.zoom
        let excessX = max(0, sourceSize.width * scale - crop.width)
        let excessY = max(0, sourceSize.height * scale - crop.height)
        var result = placement
        result.x = excessX > 0.0001 ? min(1, max(-1, placement.x + 2 * translation.width * bounds.width / max(1, previewSize.width) / excessX)) : 0
        result.y = excessY > 0.0001 ? min(1, max(-1, placement.y + 2 * translation.height * bounds.height / max(1, previewSize.height) / excessY)) : 0
        return result
    }

    static func frameContentRect(_ size: CGSize, state: KadrioEditState) -> CGRect {
        let border = state.frame == .none ? 0 : min(size.width, size.height) * state.thickness
        let bottom = state.frame == .polaroid ? border * 3.5 : border
        return CGRect(x: border, y: bottom, width: size.width, height: size.height)
    }

    static func frameBounds(_ size: CGSize, state: KadrioEditState) -> CGRect {
        guard state.frame != .none else { return CGRect(origin: .zero, size: size) }
        let content = frameContentRect(size, state: state)
        return CGRect(x: 0, y: 0, width: size.width + content.minX * 2, height: size.height + content.minX + content.minY).integral
    }

    static func doubleFrameRects(_ content: CGRect) -> (outer: CGRect, inner: CGRect) {
        let outer = content.insetBy(dx: content.minX * 0.24, dy: content.minX * 0.24)
        return (outer, outer.insetBy(dx: content.minX * 0.16, dy: content.minX * 0.16))
    }

    static func cropSize(_ size: CGSize, ratio: Double) -> CGSize {
        let ratio = max(0.1, ratio)
        if size.width / size.height > ratio {
            return CGSize(width: size.height * ratio, height: size.height)
        }
        return CGSize(width: size.width, height: size.width / ratio)
    }

    static func cells(count: Int, layout: Int, size: CGSize, spacing: Double, split: KadrioCollageSplit = KadrioCollageSplit()) -> [CGRect] {
        let requested = KadrioCollageLayout(rawValue: layout) ?? .feature
        let selected = count >= requested.photoCount ? requested : KadrioCollageLayout.initial(for: count)
        let gap = min(size.width, size.height) * spacing
        let outer = CGRect(origin: .zero, size: size).insetBy(dx: gap, dy: gap)
        let w = (outer.width - gap) * min(0.8, max(0.2, split.x))
        let h = (outer.height - gap) * min(0.8, max(0.2, split.y))
        let left = CGRect(x: outer.minX, y: outer.minY, width: w, height: outer.height)
        let right = CGRect(x: outer.minX + w + gap, y: outer.minY, width: outer.width - gap - w, height: outer.height)
        let topLeft = CGRect(x: outer.minX, y: outer.minY, width: w, height: h)
        let topRight = CGRect(x: right.minX, y: outer.minY, width: right.width, height: h)
        let bottomLeft = CGRect(x: outer.minX, y: outer.minY + h + gap, width: w, height: outer.height - gap - h)
        let bottomRight = CGRect(x: right.minX, y: bottomLeft.minY, width: right.width, height: outer.height - gap - h)
        switch selected {
        case .columns: return [left, right]
        case .feature: return [left, topRight, bottomRight]
        case .top: return [CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: h), bottomLeft, bottomRight]
        case .grid: return [topLeft, topRight, bottomLeft, bottomRight]
        }
    }
}


struct KadrioCollageGeometry: Equatable {
    let layout: KadrioCollageLayout
    let cells: [CGRect]
    let canvasToView: CGAffineTransform
    let outputToView: CGAffineTransform
    let contentRect: CGRect
    let contentRadius: CGFloat
    let frameBand: CGRect
    let frameBandInterior: CGRect
    let previewSize: CGSize

    init(state: KadrioEditState, count: Int, previewSize: CGSize) {
        let size = KadrioGeometry.collageSize(preview: true)
        layout = count >= state.collageLayout.photoCount ? state.collageLayout : KadrioCollageLayout.initial(for: count)
        cells = KadrioGeometry.collageImageCells(count: count, layout: state.layout, size: size, spacing: state.spacing, split: state.collageSplit)
        let orientation = KadrioGeometry.orientationTransform(size, turns: state.turns, flipped: state.flipped)
        let orientedSize = CGRect(origin: .zero, size: size).applying(orientation).size
        let cropSize = KadrioGeometry.cropSize(orientedSize, ratio: state.cropAspectRatio)
        let crop = KadrioGeometry.placementTransform(orientedSize, in: CGRect(origin: .zero, size: cropSize), placement: state.crop)
        contentRect = KadrioGeometry.frameContentRect(cropSize, state: state)
        let bounds = KadrioGeometry.frameBounds(cropSize, state: state)
        outputToView = CGAffineTransform(a: previewSize.width / bounds.width, b: 0, c: 0, d: -previewSize.height / bounds.height, tx: 0, ty: previewSize.height)
        canvasToView = orientation.concatenating(crop)
            .concatenating(CGAffineTransform(translationX: contentRect.minX, y: contentRect.minY))
            .concatenating(outputToView)
        contentRadius = state.frame == .rounded ? contentRect.minX * 2 : 0
        let band = state.frame == .double && state.frameColor.alpha > 0
            ? KadrioGeometry.doubleFrameRects(contentRect) : (outer: CGRect.null, inner: CGRect.null)
        frameBand = band.outer
        frameBandInterior = band.inner
        self.previewSize = previewSize
    }

    func dividerPoint(_ divider: KadrioCollageDivider) -> CGPoint? {
        guard cells.count >= 2 else { return nil }
        let vertical = divider == .vertical
        var segments: [(CGPoint, CGPoint)] = []
        func between(_ first: CGRect, _ second: CGRect, vertical: Bool) -> (CGPoint, CGPoint) {
            if vertical {
                let x = (first.maxX + second.minX) / 2
                return (CGPoint(x: x, y: max(first.minY, second.minY)),
                        CGPoint(x: x, y: min(first.maxY, second.maxY)))
            }
            let y = (first.minY + second.maxY) / 2
            return (CGPoint(x: max(first.minX, second.minX), y: y),
                    CGPoint(x: min(first.maxX, second.maxX), y: y))
        }
        switch cells.count {
        case 2:
            if vertical { segments = [between(cells[0], cells[1], vertical: true)] }
        case 3:
            if layout == .feature {
                segments = [vertical ? between(cells[0], cells[1].union(cells[2]), vertical: true)
                    : between(cells[1], cells[2], vertical: false)]
            } else {
                segments = [vertical ? between(cells[1], cells[2], vertical: true)
                    : between(cells[0], cells[1].union(cells[2]), vertical: false)]
            }
        default:
            segments = vertical
                ? [between(cells[0], cells[1], vertical: true), between(cells[2], cells[3], vertical: true)]
                : [between(cells[0], cells[2], vertical: false), between(cells[1], cells[3], vertical: false)]
        }
        let canvasToOutput = canvasToView.concatenating(outputToView.inverted())
        var longest: (point: CGPoint, length: CGFloat)?
        for (start, end) in segments {
            for visible in visibleDividerSegments(from: start.applying(canvasToOutput), to: end.applying(canvasToOutput)) {
                let length = hypot(visible.1.x - visible.0.x, visible.1.y - visible.0.y)
                if length > (longest?.length ?? 0) {
                    longest = (CGPoint(x: (visible.0.x + visible.1.x) / 2,
                                       y: (visible.0.y + visible.1.y) / 2), length)
                }
            }
        }
        return longest?.point.applying(canvasToOutput.inverted())
    }

    private func visibleDividerSegments(from start: CGPoint, to end: CGPoint) -> [(CGPoint, CGPoint)] {
        let vertical = abs(end.y - start.y) >= abs(end.x - start.x)
        let fixed = vertical ? (start.x + end.x) / 2 : (start.y + end.y) / 2
        let crossMin = vertical ? contentRect.minX : contentRect.minY
        let crossMax = vertical ? contentRect.maxX : contentRect.maxY
        guard fixed >= crossMin, fixed <= crossMax else { return [] }
        let radius = min(contentRadius, min(contentRect.width, contentRect.height) / 2)
        let edgeDistance = min(fixed - crossMin, crossMax - fixed)
        let inset = edgeDistance < radius
            ? radius - sqrt(max(0, radius * radius - pow(radius - edgeDistance, 2))) : 0
        let startValue = vertical ? start.y : start.x
        let endValue = vertical ? end.y : end.x
        let lower = max(min(startValue, endValue), (vertical ? contentRect.minY : contentRect.minX) + inset)
        let upper = min(max(startValue, endValue), (vertical ? contentRect.maxY : contentRect.maxX) - inset)
        guard upper > lower else { return [] }
        func point(_ position: CGFloat) -> CGPoint {
            vertical ? CGPoint(x: fixed, y: position) : CGPoint(x: position, y: fixed)
        }
        var cuts = [lower, upper]
        if !frameBand.isNull {
            for rect in [frameBand, frameBandInterior] {
                cuts += [vertical ? rect.minY : rect.minX, vertical ? rect.maxY : rect.maxX]
                    .filter { $0 > lower && $0 < upper }
            }
        }
        cuts = Array(Set(cuts)).sorted()
        var result: [(CGPoint, CGPoint)] = []
        for (a, b) in zip(cuts, cuts.dropFirst()) {
            let middle = point((a + b) / 2)
            guard !frameBand.contains(middle) || frameBandInterior.contains(middle) else { continue }
            if let last = result.last, last.1 == point(a) {
                result[result.count - 1].1 = point(b)
            } else {
                result.append((point(a), point(b)))
            }
        }
        return result
    }

    func containsContent(_ point: CGPoint) -> Bool {
        guard CGRect(origin: .zero, size: previewSize).contains(point) else { return false }
        let output = point.applying(outputToView.inverted())
        return CGPath(roundedRect: contentRect, cornerWidth: contentRadius, cornerHeight: contentRadius, transform: nil).contains(output)
            && (!frameBand.contains(output) || frameBandInterior.contains(output))
    }

    func photo(at point: CGPoint) -> Int? {
        guard containsContent(point) else { return nil }
        let canvasPoint = point.applying(canvasToView.inverted())
        let radius = KadrioGeometry.collageCornerRadius(KadrioGeometry.collageSize(preview: true))
        return cells.firstIndex { CGPath(roundedRect: $0, cornerWidth: radius, cornerHeight: radius, transform: nil).contains(canvasPoint) }
    }

    func canvasTranslation(_ translation: CGSize) -> CGSize {
        let inverse = canvasToView.inverted()
        return CGSize(width: inverse.a * translation.width + inverse.c * translation.height,
                      height: inverse.b * translation.width + inverse.d * translation.height)
    }

    func placement(index: Int, sourceSize: CGSize, start: KadrioPlacement, translation: CGSize, magnification: Double, anchor: CGPoint) -> KadrioPlacement {
        let cell = cells[index]
        let zoom = KadrioGeometry.clampedZoom(start.zoom * magnification)
        let zoomScale = zoom / start.zoom
        let initialOrigin = CGPoint.zero.applying(KadrioGeometry.placementTransform(sourceSize, in: cell, placement: start))
        let offset = canvasTranslation(translation)
        let origin = CGPoint(x: anchor.x + (initialOrigin.x - anchor.x) * zoomScale + offset.width,
                             y: anchor.y + (initialOrigin.y - anchor.y) * zoomScale + offset.height)
        let scale = max(cell.width / sourceSize.width, cell.height / sourceSize.height) * zoom
        let excessX = max(0, sourceSize.width * scale - cell.width)
        let excessY = max(0, sourceSize.height * scale - cell.height)
        return KadrioPlacement(zoom: zoom,
                               x: excessX > 0.0001 ? min(1, max(-1, 1 + 2 * (origin.x - cell.minX) / excessX)) : 0,
                               y: excessY > 0.0001 ? min(1, max(-1, -1 - 2 * (origin.y - cell.minY) / excessY)) : 0)
    }
}
