import XCTest
import CoreImage
import ImageIO
@testable import Kadrio

final class KadrioImageProcessingTests: XCTestCase {
    private func createPhoto(width: Int, height: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KadrioSynthetic-\(UUID()).jpg")
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        let image = CIImage(color: CIColor(red: 0.8, green: 0.3, blue: 0.15)).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        try context.writeJPEGRepresentation(of: image, to: url, colorSpace: CGColorSpaceCreateDeviceRGB())
        return url
    }

    private func dimensions(_ url: URL) throws -> CGSize {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        return CGSize(width: width, height: height)
    }

    func testCropRatiosFitInsideSource() {
        let source = CGSize(width: 4000, height: 3000)
        for ratio in [1.0, 0.8, 9.0 / 16, 16.0 / 9] {
            let output = KadrioGeometry.cropSize(source, ratio: ratio)
            XCTAssertEqual(output.width / output.height, ratio, accuracy: 0.0001)
            XCTAssertLessThanOrEqual(output.width, source.width)
            XCTAssertLessThanOrEqual(output.height, source.height)
        }
    }

    func testLayoutsHaveDistinctGeometryAndNoOverlaps() {
        let size = CGSize(width: 800, height: 1000)
        let bounds = CGRect(origin: .zero, size: size)
        var layouts: [[CGRect]] = []
        for layout in KadrioCollageLayout.allCases {
            let cells = KadrioGeometry.cells(count: 4, layout: layout.rawValue, size: size, spacing: 0.03)
            XCTAssertEqual(cells.count, layout.photoCount)
            for (index, cell) in cells.enumerated() {
                XCTAssertTrue(bounds.contains(cell))
                for other in cells.dropFirst(index + 1) { XCTAssertFalse(cell.intersects(other)) }
            }
            layouts.append(cells)
        }
        for index in 0..<4 { for other in layouts.dropFirst(index + 1) { XCTAssertNotEqual(layouts[index], other) } }
        XCTAssertEqual(layouts[0][0].height, layouts[0][1].height)
        XCTAssertGreaterThan(layouts[1][0].height, layouts[1][1].height)
        XCTAssertEqual(layouts[1][1].minX, layouts[1][2].minX)
        XCTAssertGreaterThan(layouts[2][0].width, layouts[2][1].width)
        XCTAssertEqual(layouts[2][1].minY, layouts[2][2].minY)
        XCTAssertTrue(layouts[3].allSatisfy { $0.size == layouts[3][0].size })
    }

    func testUnavailableLayoutsFallBackWithoutEmptySlots() {
        for count in 2...3 {
            for layout in KadrioCollageLayout.allCases where layout.photoCount > count {
                let cells = KadrioGeometry.cells(count: count, layout: layout.rawValue, size: CGSize(width: 800, height: 1000), spacing: 0.02)
                XCTAssertEqual(cells.count, count)
                XCTAssertEqual(KadrioCollageLayout.initial(for: count).photoCount, count)
            }
        }
    }

    func testFortyEightMegapixelImportAndFullResolutionExport() async throws {
        let url = try createPhoto(width: 8000, height: 6000)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try await KadrioImageProcessing.shared.importSource(url: url)
        var state = KadrioEditState()
        state.freeRatio = 4.0 / 3
        state.filter = .vivid
        let preview = try await KadrioImageProcessing.shared.preview(sources: [source], state: state)
        XCTAssertLessThanOrEqual(max(preview.size.width, preview.size.height), 1400)
        let probe = await KadrioMainThreadProbe()
        await probe.start()
        let export = try await KadrioImageProcessing.shared.export(sources: [source], state: state)
        let ticks = await probe.stop()
        XCTAssertGreaterThan(ticks, 0, "Main actor must remain responsive during 48 MP export")
        XCTAssertEqual(try dimensions(export), CGSize(width: 8000, height: 6000))
        try FileManager.default.removeItem(at: export)
        await KadrioImageProcessing.shared.clean([source])
    }

    func testRotatedCropExportHasExactRatio() async throws {
        let url = try createPhoto(width: 1200, height: 800)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try await KadrioImageProcessing.shared.importSource(url: url)
        var state = KadrioEditState()
        state.ratio = .portrait
        state.turns = 1
        state.flipped = true
        let export = try await KadrioImageProcessing.shared.export(sources: [source], state: state)
        let size = try dimensions(export)
        XCTAssertEqual(size.width / size.height, 0.8, accuracy: 0.002)
        try FileManager.default.removeItem(at: export)
        await KadrioImageProcessing.shared.clean([source])
    }

    func testCollageCellsContainTheirOwnPhotoWithoutEmptyEdges() async throws {
        let colors = [CIColor(red: 1, green: 0, blue: 0), CIColor(red: 0, green: 1, blue: 0), CIColor(red: 0, green: 0, blue: 1), CIColor(red: 1, green: 1, blue: 0)]
        let context = CIContext(options: [.cacheIntermediates: false])
        let space = CGColorSpaceCreateDeviceRGB()
        var sources: [KadrioSource] = []
        for color in colors {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("KadrioCellColor-\(UUID()).jpg")
            let image = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 240, height: 300))
            try context.writeJPEGRepresentation(of: image, to: url, colorSpace: space)
            sources.append(try await KadrioImageProcessing.shared.importSource(url: url))
            try FileManager.default.removeItem(at: url)
        }
        var state = KadrioEditState()
        state.collage = true
        state.sourceCount = 4
        state.layout = 2
        state.spacing = 0.03
        state.placements[0] = KadrioPlacement(zoom: 2, x: 1, y: -1)
        let export = try await KadrioImageProcessing.shared.export(sources: sources, state: state)
        let image = try XCTUnwrap(CIImage(contentsOf: export))
        let cells = KadrioGeometry.cells(count: 4, layout: 2, size: CGSize(width: 4000, height: 5000), spacing: state.spacing)
        for (index, cell) in cells.enumerated() {
            let expected = [colors[index].red, colors[index].green, colors[index].blue]
            for point in [CGPoint(x: cell.midX, y: cell.midY), CGPoint(x: cell.minX + 4, y: cell.midY), CGPoint(x: cell.maxX - 4, y: cell.midY), CGPoint(x: cell.midX, y: cell.minY + 4), CGPoint(x: cell.midX, y: cell.maxY - 4)] {
                var pixel = [UInt8](repeating: 0, count: 4)
                context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: point.x, y: 5000 - point.y, width: 1, height: 1), format: .RGBA8, colorSpace: space)
                for channel in 0..<3 { XCTAssertEqual(Double(pixel[channel]), Double(expected[channel]) * 255, accuracy: 10) }
            }
        }
        try FileManager.default.removeItem(at: export)
        await KadrioImageProcessing.shared.clean(sources)
    }

    func testEmbeddedDisplayP3IsConvertedToSRGB() async throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let srgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let cgColor = try XCTUnwrap(CGColor(colorSpace: p3, components: [0.8, 0.4, 0.1, 1]))
        let image = CIImage(color: CIColor(cgColor: cgColor)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KadrioP3-\(UUID()).jpg")
        let context = CIContext(options: [.cacheIntermediates: false])
        try context.writeJPEGRepresentation(of: image, to: url, colorSpace: p3)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try await KadrioImageProcessing.shared.importSource(url: url)
        var state = KadrioEditState()
        state.freeRatio = 1
        let export = try await KadrioImageProcessing.shared.export(sources: [source], state: state)
        let result = try XCTUnwrap(CIImage(contentsOf: export))
        var expected = [UInt8](repeating: 0, count: 4)
        var actual = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &expected, rowBytes: 4, bounds: CGRect(x: 50, y: 50, width: 1, height: 1), format: .RGBA8, colorSpace: srgb)
        context.render(result, toBitmap: &actual, rowBytes: 4, bounds: CGRect(x: 50, y: 50, width: 1, height: 1), format: .RGBA8, colorSpace: srgb)
        for channel in 0..<3 { XCTAssertEqual(Int(actual[channel]), Int(expected[channel]), accuracy: 5) }
        try FileManager.default.removeItem(at: export)
        await KadrioImageProcessing.shared.clean([source])
    }

    func testAllFrameStylesExportWithCustomColor() async throws {
        let url = try createPhoto(width: 240, height: 300)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try await KadrioImageProcessing.shared.importSource(url: url)
        for frame in KadrioFrame.allCases {
            var state = KadrioEditState()
            state.freeRatio = 0.8
            state.frame = frame
            state.frameColor = KadrioColor(red: 0.2, green: 0.6, blue: 0.3)
            state.thickness = 0.1
            let preview = try await KadrioImageProcessing.shared.preview(sources: [source], state: state)
            let export = try await KadrioImageProcessing.shared.export(sources: [source], state: state)
            let size = try dimensions(export)
            XCTAssertEqual(size.width, preview.size.width, accuracy: 1)
            XCTAssertEqual(size.height, preview.size.height, accuracy: 1)
            if frame == .none { XCTAssertEqual(size, CGSize(width: 240, height: 300)) }
            else { XCTAssertGreaterThan(size.width, 240); XCTAssertGreaterThan(size.height, 300) }
            try FileManager.default.removeItem(at: export)
        }
        await KadrioImageProcessing.shared.clean([source])
    }

    func testCollageExportsEveryLayoutWithFourSources() async throws {
        let url = try createPhoto(width: 240, height: 300)
        defer { try? FileManager.default.removeItem(at: url) }
        var sources: [KadrioSource] = []
        for _ in 0..<4 { sources.append(try await KadrioImageProcessing.shared.importSource(url: url)) }
        for layout in 0..<4 {
            var state = KadrioEditState()
            state.sourceCount = 4
            state.collage = true
            state.layout = layout
            state.spacing = 0.03
            state.placements[0] = KadrioPlacement(zoom: 2, x: 1, y: -1)
            let export = try await KadrioImageProcessing.shared.export(sources: sources, state: state)
            XCTAssertEqual(try dimensions(export), CGSize(width: 4000, height: 5000))
            try FileManager.default.removeItem(at: export)
        }
        await KadrioImageProcessing.shared.clean(sources)
    }

    @MainActor func testUndoRedoPreservesAllEditingParameters() {
        let source = KadrioSource(id: UUID(), url: URL(fileURLWithPath: "/tmp/KadrioMissing"), previewURL: URL(fileURLWithPath: "/tmp/KadrioMissing"), pixelWidth: 400, pixelHeight: 500)
        let model = KadrioEditorModel(request: KadrioEditorRequest(sources: [source], tool: .frames))
        let original = model.state
        model.change { $0.frame = .rounded; $0.frameColor = KadrioColor(red: 0.5, green: 0.1, blue: 0.2); $0.crop.zoom = 2; $0.filter = .warm }
        let changed = model.state
        model.undo()
        XCTAssertEqual(model.state, original)
        model.redo()
        XCTAssertEqual(model.state, changed)
        model.finish()
    }
}

@MainActor private final class KadrioMainThreadProbe {
    private var ticks = 0
    private var task: Task<Void, Never>?
    func start() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                if Task.isCancelled { return }
                self?.ticks += 1
            }
        }
    }
    func stop() -> Int { task?.cancel(); return ticks }
}
