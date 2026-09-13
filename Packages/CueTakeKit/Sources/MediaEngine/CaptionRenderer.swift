import AVFoundation
import CoreText
import Domain
import Foundation
import QuartzCore

/// Burns the captions into the exported file.
///
/// Burned in, not a sidecar track. Every place this video is going — Reels, TikTok, Shorts —
/// either ignores an embedded subtitle track or hides it behind a control nobody taps, and the
/// whole point of captions on short video is that they are read by someone scrolling with the
/// sound off. A caption that has to be switched on is a caption nobody sees.
///
/// `AVVideoCompositionCoreAnimationTool` is the mechanism: the video is handed to a layer, the
/// cues are layers over it, and Core Animation's own timeline decides which is on screen. That
/// also explains why the editor's preview draws its captions in SwiftUI instead — the animation
/// tool is an export-time facility and `AVPlayer` does not run it.
enum CaptionRenderer {
    /// The layer tree, or nil when there is nothing to draw.
    static func tool(
        cues: [PlacedCue],
        style: CaptionStyle,
        locale: Locale,
        renderSize: CGSize
    ) -> AVVideoCompositionCoreAnimationTool? {
        guard !cues.isEmpty, renderSize.width > 0, renderSize.height > 0 else { return nil }

        let frame = CGRect(origin: .zero, size: renderSize)

        let parent = CALayer()
        parent.frame = frame
        parent.isGeometryFlipped = false

        let video = CALayer()
        video.frame = frame
        parent.addSublayer(video)

        let fontSize = max(12, renderSize.height * style.relativeFontSize)
        // Wide enough to read, narrow enough to break into the two or three word lines short-form
        // captions live on.
        let width = renderSize.width * 0.86
        let height = fontSize * 3.2

        for cue in cues {
            let text = style.textCase.apply(to: cue.text, locale: locale)
            guard !text.isEmpty else { continue }

            let layer = CATextLayer()
            layer.string = attributed(text, style: style, fontSize: fontSize)
            layer.alignmentMode = .center
            layer.isWrapped = true
            layer.truncationMode = .none
            // Rendered at the video's own scale, not the screen's: at 1 the text is soft on
            // anything above 1080p, and captions are the one thing in the frame made of edges.
            layer.contentsScale = 2
            layer.frame = CGRect(
                x: (renderSize.width - width) / 2,
                // Core Animation's origin is bottom-left and the position is given from the top,
                // so the y flips here. Getting this wrong puts lower thirds in the sky.
                y: renderSize.height * (1 - style.position.y) - height / 2,
                width: width,
                height: height
            )

            if let background = style.backgroundColor {
                layer.backgroundColor = cgColor(background)
                layer.cornerRadius = fontSize * 0.28
                layer.masksToBounds = true
            }

            // Hidden by default and switched on for its own range. Opacity rather than isHidden
            // because only the former can be animated on the composition's timeline.
            layer.opacity = 0
            layer.add(visibility(for: cue), forKey: "cue")
            parent.addSublayer(layer)
        }

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: video,
            in: parent
        )
    }

    /// On for the cue's range, off either side.
    ///
    /// `AVCoreAnimationBeginTimeAtZero` rather than 0: a begin time of exactly zero means "now" to
    /// Core Animation, and every cue would appear at once on the first frame.
    private static func visibility(for cue: PlacedCue) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0, 1, 1, 0]
        // A frame of fade at each end. Captions that pop in hard read as a glitch at the moment a
        // cut lands, which is exactly when they change.
        animation.keyTimes = [0, 0.06, 0.94, 1]
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + cue.range.start.seconds
        animation.duration = max(0.1, cue.range.duration.seconds)
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
        return animation
    }

    private static func attributed(
        _ text: String,
        style: CaptionStyle,
        fontSize: CGFloat
    ) -> NSAttributedString {
        let font: CTFont = {
            if let name = style.fontName {
                return CTFontCreateWithName(name as CFString, fontSize, nil)
            }
            // Heavy by default. A caption is read at a glance over moving pictures, and weight is
            // what carries it there — not size, which only costs the frame.
            let descriptor = CTFontDescriptorCreateWithAttributes([
                kCTFontFamilyNameAttribute: "Helvetica Neue" as CFString,
                kCTFontTraitsAttribute: [kCTFontSymbolicTrait: CTFontSymbolicTraits.traitBold.rawValue],
            ] as CFDictionary)
            return CTFontCreateWithFontDescriptor(descriptor, fontSize, nil)
        }()

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: cgColor(style.textColor),
        ]

        // An outline rather than a shadow. Short video is watched over whatever happens to be
        // behind the words, and a stroke is the only thing that survives white footage.
        if style.backgroundColor == nil {
            attributes[.strokeColor] = cgColor(.black)
            // Negative means stroke *and* fill; positive would draw the outline only.
            attributes[.strokeWidth] = -fontSize * 0.14
        }

        return NSAttributedString(string: text, attributes: attributes)
    }

    private static func cgColor(_ color: RGBAColor) -> CGColor {
        CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [
                CGFloat(color.red),
                CGFloat(color.green),
                CGFloat(color.blue),
                CGFloat(color.alpha),
            ]
        ) ?? CGColor(gray: 1, alpha: 1)
    }
}
