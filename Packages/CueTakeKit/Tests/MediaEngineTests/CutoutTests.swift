import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Domain
import Foundation
import ImageIO
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

    /// The picture inside comes out the right way up: a photo red on top and blue below is still
    /// red on top once drawn behind the person. It came out upside down on the phone once.
    @Test func aBehindPictureIsTheRightWayUp() throws {
        let folder = URL(filePath: NSTemporaryDirectory()).appending(path: "behind-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // 20×20: red rows on top, blue rows below, in the file as it is stored.
        let side = 20
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let i = (y * side + x) * 4
                pixels[i] = y < side / 2 ? 255 : 0
                pixels[i + 1] = 0
                pixels[i + 2] = y < side / 2 ? 0 : 255
            }
        }
        let photo = try pixels.withUnsafeMutableBytes { raw -> CGImage in
            let context = try #require(CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            return try #require(context.makeImage())
        }
        let file = folder.appending(path: "photo.png", directoryHint: .notDirectory)
        let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, photo, nil)
        #expect(CGImageDestinationFinalize(destination))

        var overlay = Overlay(content: .image(relativePath: "photo.png", aspect: 1), start: .zero, duration: MediaTime(seconds: 2))
        overlay.isBehindPerson = true
        let image = try #require(LiveBehind.draw(overlay, size: CGSize(width: 200, height: 200), mediaDirectory: folder))

        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        _ = bytes.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        // The photo is half the frame wide, centred: rows 50…150. Row 60 is near its top.
        let upper = (60 * width + 100) * 4, lower = (140 * width + 100) * 4
        #expect(bytes[upper] > 200 && bytes[upper + 2] < 60)
        #expect(bytes[lower + 2] > 200 && bytes[lower] < 60)
    }

    /// Labels: thing 1 in the top left corner, thing 2 in the bottom right.
    private func labels() throws -> CVPixelBuffer {
        var made: CVPixelBuffer?
        CVPixelBufferCreate(nil, 10, 10, kCVPixelFormatType_OneComponent8, nil, &made)
        let buffer = try #require(made)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<10 {
            for x in 0..<10 {
                base[y * stride + x] = x < 3 && y < 3 ? 1 : (x >= 7 && y >= 7 ? 2 : 0)
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    @Test func theTappedThingIsTheOneKeptAndFollowed() throws {
        let buffer = try labels()
        let top = try #require(BackgroundRemover.instance(near: CGPoint(x: 0.1, y: 0.1), in: buffer))
        #expect(top.label == 1)
        #expect(abs(top.centre.x - 0.15) < 0.001)
        #expect(abs(top.centre.y - 0.15) < 0.001)
        // Beside both, nearer the second: the nearest one, not everything.
        let near = try #require(BackgroundRemover.instance(near: CGPoint(x: 0.6, y: 0.65), in: buffer))
        #expect(near.label == 2)
        #expect(abs(near.centre.x - 0.85) < 0.001)
    }

    @Test func aTappedPointIsPartOfTheRendersName() {
        let all = BackgroundSettings(style: .black, cutout: .subject)
        let one = BackgroundSettings(style: .black, cutout: .subject, subjectPoint: SubjectPoint(x: 0.3, y: 0.7))
        let other = BackgroundSettings(style: .black, cutout: .subject, subjectPoint: SubjectPoint(x: 0.6, y: 0.7))
        #expect(Set([all.token, one.token, other.token]).count == 3)
        #expect(SubjectPoint(x: 2, y: -1) == SubjectPoint(x: 1, y: 0))
    }
}
