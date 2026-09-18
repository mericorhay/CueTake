import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Domain
import Foundation
import QuartzCore
import Vision

/// Pictures and text drawn behind the people in the video, read by the compositor on every frame.
///
/// Shared like `LiveFilters`, so moving a title the person stands in front of changes the
/// picture without the composition being rebuilt. The one being edited is left out: the editor
/// draws it on top with its handles while a finger is on it, and it goes back behind the person
/// when let go.
public final class LiveBehind: @unchecked Sendable {
    private let lock = NSLock()
    private var overlays: [Overlay] = []
    private var editing: Overlay.ID?
    private var directory: URL?
    /// Each overlay drawn once at the frame's size, by what it looks like.
    private var drawn: [Overlay: CGImage] = [:]
    private var drawnSize: CGSize = .zero

    public init(_ overlays: [Overlay] = [], mediaDirectory: URL? = nil) {
        update(overlays, editing: nil, mediaDirectory: mediaDirectory)
    }

    public func update(_ overlays: [Overlay], editing: Overlay.ID?, mediaDirectory: URL?) {
        let behind = overlays.filter(\.isBehindPerson)
        lock.withLock {
            self.overlays = behind
            self.editing = editing
            if let mediaDirectory { directory = mediaDirectory }
            // Only what is still wanted stays drawn.
            let kept = Set(behind.map(Self.look))
            drawn = drawn.filter { kept.contains(Self.look($0.key)) }
        }
    }

    public var isEmpty: Bool { lock.withLock { overlays.isEmpty } }

    /// What shows behind the people at a moment, bottom to top, with how much of each shows.
    func showing(at seconds: Double) -> [(overlay: Overlay, level: Double)] {
        lock.withLock {
            overlays.compactMap { overlay -> (overlay: Overlay, level: Double)? in
                guard overlay.id != editing else { return nil }
                let level = overlay.visibility(at: seconds)
                return level > 0.001 ? (overlay, level) : nil
            }
        }
    }

    /// One overlay as a frame-sized picture, drawn the first time it is asked for.
    func picture(of overlay: Overlay, size: CGSize) -> CIImage? {
        let key = Self.look(overlay)
        let (cached, directory) = lock.withLock { () -> (CGImage?, URL?) in
            if drawnSize != size {
                drawn.removeAll()
                drawnSize = size
            }
            return (drawn[key], self.directory)
        }
        if let cached { return CIImage(cgImage: cached) }
        guard let directory, let image = Self.draw(overlay, size: size, mediaDirectory: directory) else { return nil }
        lock.withLock {
            if drawn.count > 8 { drawn.removeAll() }
            drawn[key] = image
        }
        return CIImage(cgImage: image)
    }

    /// The overlay with the things that do not change its picture taken out.
    private static func look(_ overlay: Overlay) -> Overlay {
        var look = overlay
        look.start = .zero
        look.duration = .zero
        look.transform.opacity = 1
        look.animation = .none
        return look
    }

    /// The same layer the export burns in, drawn into a frame-sized bitmap. Both use a y-up
    /// context, so where it sits, how it turns and how the text reads all match.
    static func draw(_ overlay: Overlay, size: CGSize, mediaDirectory: URL) -> CGImage? {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard width > 0, height > 0,
              let layer = OverlayRenderer.stillLayer(for: overlay, renderSize: size, mediaDirectory: mediaDirectory),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        let stage = CALayer()
        stage.frame = CGRect(origin: .zero, size: size)
        stage.addSublayer(layer)
        stage.render(in: context)
        return context.makeImage()
    }
}

/// Finds the people in a composed frame and lays the behind-person overlays under them.
///
/// One per compositor, used only on its queue: the sequence handler keeps the edge steady from
/// one frame to the next.
final class PersonCutter {
    private let request: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        // Balanced is Apple's setting for live video.
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()
    private let sequence = VNSequenceRequestHandler()

    func compose(_ frame: CIImage, behind: [(overlay: Overlay, level: Double)], pictures: LiveBehind, in bounds: CGRect) -> CIImage {
        var under = frame
        for (overlay, level) in behind {
            guard var picture = pictures.picture(of: overlay, size: bounds.size) else { continue }
            if level < 0.999 {
                picture = picture.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: level, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: level, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: level, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: level),
                ])
            }
            under = picture.composited(over: under)
        }
        // No one in the picture: the overlay is simply over the frame, like any other.
        guard (try? sequence.perform([request], on: frame)) != nil,
              let buffer = request.results?.first?.pixelBuffer
        else { return under.cropped(to: bounds) }
        let mask = CIImage(cvPixelBuffer: buffer)
        let fitted = mask
            .transformed(by: CGAffineTransform(
                scaleX: bounds.width / max(mask.extent.width, 1),
                y: bounds.height / max(mask.extent.height, 1)
            ))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(min(bounds.width, bounds.height)) * 0.002)
            .cropped(to: bounds)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = frame
        blend.backgroundImage = under
        blend.maskImage = fitted
        return blend.outputImage?.cropped(to: bounds) ?? under.cropped(to: bounds)
    }
}
