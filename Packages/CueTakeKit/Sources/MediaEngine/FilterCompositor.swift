import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Domain
import Foundation

/// Filters in effect, read by the compositor on every frame.
///
/// Shared rather than copied into each instruction, so a slider in the editor changes the picture
/// without the composition being rebuilt — rebuilding swaps the player's item, and the picture
/// blinks on every step of a drag.
public final class LiveFilters: @unchecked Sendable {
    public struct Span: Sendable {
        public var start: Double
        public var end: Double
        public var settings: FilterSettings
    }

    private let lock = NSLock()
    private var spans: [Span] = []

    public init(_ effects: [TimelineEffect] = []) {
        update(effects)
    }

    public func update(_ effects: [TimelineEffect]) {
        let next = effects.compactMap { effect in
            effect.filter.map { Span(start: effect.start.seconds, end: effect.end, settings: $0.clamped) }
        }
        lock.withLock { spans = next }
    }

    /// The filters over a moment, bottom to top.
    func settings(at seconds: Double) -> [FilterSettings] {
        lock.withLock { spans.filter { $0.start <= seconds && seconds < $0.end }.map(\.settings) }
    }
}

/// A composition instruction the filter compositor understands: the same layers as the system's
/// instructions, plus where to read the filters from.
final class FilterInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let layers: [AVVideoCompositionLayerInstruction]
    let filters: LiveFilters

    init(_ instruction: AVVideoCompositionInstruction, filters: LiveFilters) {
        timeRange = instruction.timeRange
        layers = instruction.layerInstructions
        let ids = Set(instruction.layerInstructions.map(\.trackID))
        requiredSourceTrackIDs = ids.sorted().map { NSNumber(value: $0) }
        self.filters = filters
    }
}

/// Composites the video the way the system compositor does — every layer's transform, crop and
/// opacity, top over bottom — and then lays the filters over the frame.
///
/// Used only when a project has a filter; everything else keeps the system's compositor.
final class FilterCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "cuetake.filter-compositor", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var renderSize: CGSize = .zero
    private var cancelled = false

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA], kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA], kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        let size = newRenderContext.size
        lock.withLock { renderSize = size }
    }

    func cancelAllPendingVideoCompositionRequests() {
        lock.withLock { cancelled = true }
        queue.async { [self] in lock.withLock { cancelled = false } }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        nonisolated(unsafe) let request = request
        queue.async { [self] in
            if lock.withLock({ cancelled }) {
                request.finishCancelledRequest()
                return
            }
            guard let instruction = request.videoCompositionInstruction as? FilterInstruction,
                  let output = request.renderContext.newPixelBuffer()
            else {
                request.finish(with: NSError(domain: "CueTake.FilterCompositor", code: 1))
                return
            }
            autoreleasepool {
                let time = request.compositionTime
                let size = request.renderContext.size
                let bounds = CGRect(origin: .zero, size: size)
                var frame = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: bounds)

                // The first layer instruction is on top; paint from the bottom up.
                for layer in instruction.layers.reversed() {
                    guard let pixels = request.sourceFrame(byTrackID: layer.trackID) else { continue }
                    if let image = Self.place(pixels, layer: layer, at: time, renderHeight: size.height) {
                        frame = image.composited(over: frame)
                    }
                }

                for settings in instruction.filters.settings(at: time.seconds) {
                    frame = FilterLooks.apply(settings, to: frame, in: bounds)
                }

                context.render(frame.cropped(to: bounds), to: output, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
            }
            request.finish(withComposedVideoFrame: output)
        }
    }

    /// One source frame as its layer instruction places it, in Core Image's bottom-up space.
    static func place(
        _ pixels: CVPixelBuffer,
        layer: AVVideoCompositionLayerInstruction,
        at time: CMTime,
        renderHeight: CGFloat
    ) -> CIImage? {
        let sourceHeight = CGFloat(CVPixelBufferGetHeight(pixels))
        var image = CIImage(cvPixelBuffer: pixels)

        var cropStart = CGRect.zero, cropEnd = CGRect.zero
        var cropRange = CMTimeRange.invalid
        if layer.getCropRectangleRamp(for: time, startCropRectangle: &cropStart, endCropRectangle: &cropEnd, timeRange: &cropRange) {
            let crop = interpolate(cropStart, cropEnd, fraction(time, cropRange))
            if crop.width > 0, crop.height > 0 {
                // The crop is given top-down; Core Image counts from the bottom.
                image = image.cropped(to: CGRect(x: crop.minX, y: sourceHeight - crop.maxY, width: crop.width, height: crop.height))
            }
        }

        var startTransform = CGAffineTransform.identity, endTransform = CGAffineTransform.identity
        var transformRange = CMTimeRange.invalid
        var transform = CGAffineTransform.identity
        if layer.getTransformRamp(for: time, start: &startTransform, end: &endTransform, timeRange: &transformRange) {
            transform = interpolate(startTransform, endTransform, fraction(time, transformRange))
        }
        // Flip into top-down space, apply the layer's transform, flip back for the render.
        let toTopDown = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: sourceHeight)
        let toBottomUp = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: renderHeight)
        image = image.transformed(by: toTopDown.concatenating(transform).concatenating(toBottomUp))

        var opacityStart: Float = 1, opacityEnd: Float = 1
        var opacityRange = CMTimeRange.invalid
        if layer.getOpacityRamp(for: time, startOpacity: &opacityStart, endOpacity: &opacityEnd, timeRange: &opacityRange) {
            let opacity = CGFloat(opacityStart + (opacityEnd - opacityStart) * Float(fraction(time, opacityRange)))
            if opacity < 0.999 {
                image = image.applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(0, opacity)),
                ])
            }
        }
        return image
    }

    private static func fraction(_ time: CMTime, _ range: CMTimeRange) -> Double {
        guard range.isValid, range.duration.seconds > 0 else { return 0 }
        return min(max((time - range.start).seconds / range.duration.seconds, 0), 1)
    }

    private static func interpolate(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        let t = CGFloat(t)
        return CGRect(
            x: a.minX + (b.minX - a.minX) * t,
            y: a.minY + (b.minY - a.minY) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }

    private static func interpolate(_ a: CGAffineTransform, _ b: CGAffineTransform, _ t: Double) -> CGAffineTransform {
        guard t > 0 else { return a }
        let t = CGFloat(t)
        return CGAffineTransform(
            a: a.a + (b.a - a.a) * t, b: a.b + (b.b - a.b) * t,
            c: a.c + (b.c - a.c) * t, d: a.d + (b.d - a.d) * t,
            tx: a.tx + (b.tx - a.tx) * t, ty: a.ty + (b.ty - a.ty) * t
        )
    }
}

/// The looks, as Core Image filters.
public enum FilterLooks {
    public static func apply(_ settings: FilterSettings, to image: CIImage, in bounds: CGRect) -> CIImage {
        let original = image
        var looked = image

        switch settings.look {
        case .natural:
            break
        case .vivid:
            looked = looked.applyingFilter("CIVibrance", parameters: ["inputAmount": 0.9])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.12, kCIInputContrastKey: 1.06])
        case .cinematic:
            // Warm skin, cool shadows, a gentle S-curve.
            looked = looked
                .applyingFilter("CIToneCurve", parameters: [
                    "inputPoint0": CIVector(x: 0, y: 0.02),
                    "inputPoint1": CIVector(x: 0.25, y: 0.2),
                    "inputPoint2": CIVector(x: 0.5, y: 0.5),
                    "inputPoint3": CIVector(x: 0.75, y: 0.8),
                    "inputPoint4": CIVector(x: 1, y: 0.97),
                ])
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1.05, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0.98, z: 0.02, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0.04, z: 0.96, w: 0),
                    "inputBiasVector": CIVector(x: 0, y: 0.005, z: 0.02, w: 0),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.9])
        case .warm:
            looked = tint(looked, warmth: 0.8)
        case .cool:
            looked = tint(looked, warmth: -0.8)
        case .vintage:
            looked = looked.applyingFilter("CIPhotoEffectTransfer")
        case .fade:
            looked = looked.applyingFilter("CIPhotoEffectFade")
        case .chrome:
            looked = looked.applyingFilter("CIPhotoEffectChrome")
        case .instant:
            looked = looked.applyingFilter("CIPhotoEffectInstant")
        case .dramatic:
            looked = looked
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.3, kCIInputSaturationKey: 0.8])
                .applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.9, kCIInputRadiusKey: 1.6])
        case .mono:
            looked = looked.applyingFilter("CIPhotoEffectMono")
        case .noir:
            looked = looked.applyingFilter("CIPhotoEffectNoir")
        }

        if settings.look != .natural, settings.intensity < 0.999 {
            looked = original.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: looked,
                kCIInputTimeKey: settings.intensity,
            ])
        }

        if abs(settings.brightness) > 0.001 || abs(settings.contrast) > 0.001 || abs(settings.saturation) > 0.001 {
            looked = looked.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: settings.brightness * 0.25,
                kCIInputContrastKey: 1 + settings.contrast * 0.5,
                kCIInputSaturationKey: 1 + settings.saturation,
            ])
        }
        if abs(settings.warmth) > 0.001 {
            looked = tint(looked, warmth: settings.warmth)
        }
        if settings.vignette > 0.001 {
            looked = looked.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: settings.vignette * 2,
                kCIInputRadiusKey: 1.5,
            ])
        }
        if settings.sharpness > 0.001 {
            looked = looked.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: settings.sharpness * 0.8])
        }
        return looked.cropped(to: bounds)
    }

    private static func tint(_ image: CIImage, warmth: Double) -> CIImage {
        let w = CGFloat(warmth)
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1 + 0.1 * w, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1 + 0.02 * w, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1 - 0.12 * w, w: 0),
        ])
    }
}
