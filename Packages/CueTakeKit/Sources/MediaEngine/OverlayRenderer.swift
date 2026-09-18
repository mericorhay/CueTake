import AVFoundation
import CoreText
import Domain
import Foundation
import ImageIO
import QuartzCore

/// Burns pictures and text into the exported file, the same way captions are: layers over the
/// video layer, shown for their own stretch of the timeline.
///
/// The geometry mirrors the preview's `OverlayCanvas` exactly — centre, size, rotation and flips
/// as fractions of the frame — with the one difference that Core Animation's y axis points up, so
/// positions flip vertically and a clockwise turn on screen is a negative angle here.
enum OverlayRenderer {
    /// Overlays behind a person are not among them: the compositor draws those, under the people.
    static func layers(for overlays: [Overlay], renderSize: CGSize, mediaDirectory: URL) -> [CALayer] {
        overlays.filter { !$0.isBehindPerson }.compactMap { overlay in
            layer(for: overlay, renderSize: renderSize, mediaDirectory: mediaDirectory, still: false)
        }
    }

    /// One overlay fully shown and without motion, for drawing into a single picture.
    static func stillLayer(for overlay: Overlay, renderSize: CGSize, mediaDirectory: URL) -> CALayer? {
        layer(for: overlay, renderSize: renderSize, mediaDirectory: mediaDirectory, still: true)
    }

    private static func layer(for overlay: Overlay, renderSize: CGSize, mediaDirectory: URL, still: Bool) -> CALayer? {
        let t = overlay.transform
        let content: CALayer
        let size: CGSize

        switch overlay.content {
        case .image(let path, let aspect):
            let url = mediaDirectory.appending(path: (path as NSString).lastPathComponent, directoryHint: .notDirectory)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            let width = renderSize.width * t.imageWidthFraction
            size = CGSize(width: width, height: width / max(aspect, 0.01))
            content = CALayer()
            content.contents = image
            content.contentsGravity = .resize

        case .text(let text):
            let fontSize = max(8, renderSize.height * t.textSizeFraction)
            let string = attributed(text, fontSize: fontSize)
            let measured = CaptionRenderer.measure(string, maxWidth: renderSize.width * 0.92)
            let inset = text.background == nil ? CGSize.zero : CGSize(width: fontSize * 0.45, height: fontSize * 0.22)
            size = CGSize(width: measured.width + inset.width * 2, height: measured.height + inset.height * 2)

            let container = CALayer()
            if let background = text.background {
                container.backgroundColor = CaptionRenderer.cgColor(background)
                container.cornerRadius = fontSize * 0.3
            }
            let textLayer = CATextLayer()
            textLayer.string = string
            textLayer.alignmentMode = .center
            textLayer.isWrapped = true
            textLayer.contentsScale = 2
            textLayer.frame = CGRect(x: inset.width, y: inset.height, width: measured.width, height: measured.height)
            container.addSublayer(textLayer)
            content = container
        }

        content.bounds = CGRect(origin: .zero, size: size)
        content.position = CGPoint(x: renderSize.width * t.x, y: renderSize.height * (1 - t.y))
        var transform = CATransform3DMakeRotation(-t.rotation * .pi / 180, 0, 0, 1)
        transform = CATransform3DScale(transform, t.flipX ? -1 : 1, t.flipY ? -1 : 1, 1)
        content.transform = transform
        if still { return content }
        content.opacity = 0
        content.add(visibility(for: overlay), forKey: "visible")

        switch overlay.animation {
        case .pop:
            let pop = CABasicAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.6
            pop.toValue = 1
            pop.duration = min(0.25, overlay.duration.seconds / 3)
            pop.beginTime = AVCoreAnimationBeginTimeAtZero + overlay.start.seconds
            pop.fillMode = .backwards
            pop.isRemovedOnCompletion = false
            content.add(pop, forKey: "pop")
        case .slideUp:
            let slide = CABasicAnimation(keyPath: "position.y")
            slide.fromValue = content.position.y - renderSize.height * 0.08
            slide.toValue = content.position.y
            slide.duration = min(0.35, overlay.duration.seconds / 3)
            slide.beginTime = AVCoreAnimationBeginTimeAtZero + overlay.start.seconds
            slide.fillMode = .backwards
            slide.isRemovedOnCompletion = false
            content.add(slide, forKey: "slide")
        case .none, .fade:
            break
        }
        return content
    }

    private static func visibility(for overlay: Overlay) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        let opacity = Float(overlay.transform.opacity)
        animation.values = [0, opacity, opacity, 0]
        let length = max(0.05, overlay.duration.seconds)
        // A fade takes a quarter second at each end; everything else switches on a frame.
        let edge = overlay.animation == .fade ? min(0.25 / length, 0.3) : 0.001
        animation.keyTimes = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + overlay.start.seconds
        animation.duration = length
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
        return animation
    }

    private static func attributed(_ text: OverlayText, fontSize: CGFloat) -> NSAttributedString {
        let font = CTFontCreateWithName(text.fontName as CFString, fontSize, nil)
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CaptionRenderer.cgColor(text.color),
        ]
        if text.background == nil {
            attributes[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = CaptionRenderer.cgColor(.black)
            attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = -fontSize * 0.12
        }
        return NSAttributedString(string: text.text, attributes: attributes)
    }
}
