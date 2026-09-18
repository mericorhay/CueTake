import CoreGraphics
import CoreImage
import CoreMedia
import Domain
import Foundation
import Testing
@testable import MediaEngine

struct CutoutTests {
    private let context = CIContext(options: [.cacheIntermediates: false])

    /// One pixel of a picture, 0…1, from the top left.
    private func pixel(_ image: CIImage, at point: CGPoint = .zero) -> [Double] {
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return bytes.map { Double($0) / 255 }
    }

    private func solid(_ red: Double, _ green: Double, _ blue: Double) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue, alpha: 1, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!)
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    @Test func theCubeHoldsEveryPointOnce() {
        let data = ChromaCubes.build(.green)
        #expect(data.count == ChromaCubes.size * ChromaCubes.size * ChromaCubes.size * 4 * MemoryLayout<Float>.size)
    }

    @Test func aGreenFrameBecomesSeeThroughAndSkinDoesNot() {
        let cubes = ChromaCubes()
        let screen = pixel(cubes.apply(.green, to: solid(0.1, 0.85, 0.3)))
        #expect(screen[3] < 0.05)
        let skin = pixel(cubes.apply(.green, to: solid(0.8, 0.6, 0.5)))
        #expect(skin[3] > 0.95)
        #expect(abs(skin[0] - 0.8) < 0.05)
    }

    @Test func liveKeysFollowTheirVideoWhateverTrackItIsOn() {
        var layer = VideoLayer(recordingID: UUID(), title: "a", sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 2)))
        layer.chroma = .green
        let plain = VideoLayer(recordingID: UUID(), title: "b", sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 2)))
        let keys = LiveKeys([layer, plain])
        keys.bind([7: layer.id, 8: plain.id])
        #expect(keys.key(for: 7) == .green)
        #expect(keys.key(for: 8) == nil)
        #expect(keys.key(for: 9) == nil)

        layer.chroma = .blue
        keys.update([layer, plain])
        #expect(keys.key(for: 7) == .blue)
    }

    @Test func theOverlayBeingEditedIsLeftToTheEditor() {
        var behind = Overlay(content: .text(OverlayText(text: "A")), start: .zero, duration: MediaTime(seconds: 4))
        behind.isBehindPerson = true
        let front = Overlay(content: .text(OverlayText(text: "B")), start: .zero, duration: MediaTime(seconds: 4))
        let live = LiveBehind([behind, front])
        #expect(!live.isEmpty)
        #expect(live.showing(at: 1).map { $0.overlay.id } == [behind.id])
        live.update([behind, front], editing: behind.id, mediaDirectory: nil)
        #expect(live.showing(at: 1).isEmpty)
        #expect(live.showing(at: 5).isEmpty)
        live.update([front], editing: nil, mediaDirectory: nil)
        #expect(live.isEmpty)
    }

    /// Where the drawn picture puts the overlay is where the export's layer tool puts it: a plate
    /// near the top left of the frame is near the top left of the picture.
    @Test func aBehindOverlayIsDrawnWhereTheExportDrawsIt() throws {
        var overlay = Overlay(
            content: .text(OverlayText(text: "TOP", background: .white)),
            start: .zero,
            duration: MediaTime(seconds: 2),
            transform: OverlayTransform(x: 0.25, y: 0.2)
        )
        overlay.isBehindPerson = true
        let size = CGSize(width: 200, height: 400)
        let image = try #require(LiveBehind.draw(overlay, size: size, mediaDirectory: URL(filePath: NSTemporaryDirectory())))
        #expect(image.width == 200)
        #expect(image.height == 400)

        // Rows are stored top first.
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let bitmap = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        #expect(drawn)
        var rows: [Int] = [], columns: [Int] = []
        for y in 0..<height {
            for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 128 {
                rows.append(y)
                columns.append(x)
            }
        }
        let top = try #require(rows.min()), bottom = try #require(rows.max())
        let left = try #require(columns.min()), right = try #require(columns.max())
        let middleY = Double(top + bottom) / 2 / Double(height)
        let middleX = Double(left + right) / 2 / Double(width)
        #expect(abs(middleY - 0.2) < 0.05)
        #expect(abs(middleX - 0.25) < 0.08)
    }
}
