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
        let maxWidth = renderSize.width * 0.86

        for cue in cues {
            // With word highlighting the line is rebuilt from the words, so the lit layers above
            // it are laid out from exactly the same characters.
            let highlightsWords = style.highlightsWords && !cue.words.isEmpty
            let source = highlightsWords ? cue.words.map(\.text).joined(separator: " ") : cue.text
            let text = style.textCase.apply(to: source, locale: locale)
            guard !text.isEmpty else { continue }

            let string = attributed(text, style: style, fontSize: fontSize)

            // Sized to the text rather than to a fixed box, so a plate hugs its words instead of
            // being a dark band the width of the frame.
            let inset: CGSize = style.backgroundColor == nil
                ? CGSize(width: fontSize * 0.3, height: fontSize * 0.2)
                : CGSize(width: fontSize * 0.55, height: fontSize * 0.28)
            let measured = measure(string, maxWidth: maxWidth - inset.width * 2)
            let frame = CGRect(
                x: (renderSize.width - measured.width) / 2 - inset.width,
                // Core Animation's origin is bottom-left and the position is given from the top,
                // so the y flips here. Getting this wrong puts lower thirds in the sky.
                y: renderSize.height * (1 - style.position.y) - measured.height / 2 - inset.height,
                width: measured.width + inset.width * 2,
                height: measured.height + inset.height * 2
            )

            let layer = CATextLayer()
            layer.string = string
            layer.alignmentMode = .center
            layer.isWrapped = true
            layer.truncationMode = .none
            // Rendered at the video's own scale, not the screen's: at 1 the text is soft on
            // anything above 1080p, and captions are the one thing in the frame made of edges.
            layer.contentsScale = 2
            layer.frame = frame

            if let background = style.backgroundColor {
                // The plate is its own layer behind the text, so the text layer can be inset
                // inside it without the words touching the edges.
                let plate = CALayer()
                plate.frame = frame
                plate.backgroundColor = cgColor(background)
                plate.cornerRadius = fontSize * 0.32
                plate.opacity = 0
                plate.add(visibility(for: cue.range), forKey: "plate")
                parent.addSublayer(plate)
            }
            layer.frame = frame.insetBy(dx: inset.width, dy: inset.height)

            // Hidden by default and switched on for its own range. Opacity rather than isHidden
            // because only the former can be animated on the composition's timeline.
            layer.opacity = 0
            layer.add(visibility(for: cue.range), forKey: "cue")
            parent.addSublayer(layer)

            // Karaoke: one layer per word, laid out exactly like the base line — every other word
            // is set in clear, so the lit word sits precisely over its own letters — and switched
            // on from the moment the word is said until the cue ends. Stacked, they fill the line
            // left to right in time with the voice.
            if highlightsWords, let highlight = style.highlightColor {
                let words = cue.words.map { style.textCase.apply(to: $0.text, locale: locale) }
                for (index, word) in cue.words.enumerated() {
                    let lit = CATextLayer()
                    lit.string = highlighted(words, lit: index, style: style, color: highlight, fontSize: fontSize)
                    lit.alignmentMode = .center
                    lit.isWrapped = true
                    lit.contentsScale = 2
                    lit.frame = layer.frame
                    lit.opacity = 0
                    let from = max(word.range.start.seconds, cue.range.start.seconds)
                    lit.add(
                        visibility(
                            for: MediaTimeRange(
                                start: MediaTime(seconds: from),
                                duration: MediaTime(seconds: max(0.05, cue.range.end.seconds - from))
                            ),
                            fade: false
                        ),
                        forKey: "word"
                    )
                    parent.addSublayer(lit)
                }
            }
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
    private static func visibility(for range: MediaTimeRange, fade: Bool = true) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0, 1, 1, 0]
        // A frame of fade at each end. Captions that pop in hard read as a glitch at the moment a
        // cut lands, which is exactly when they change. Lit words switch hard: a word that fades
        // on is late.
        animation.keyTimes = fade ? [0, 0.06, 0.94, 1] : [0, 0.001, 0.999, 1]
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + range.start.seconds
        animation.duration = max(0.05, range.duration.seconds)
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

        // Core Text's own attribute names rather than UIKit's. They are the same attributes —
        // UIKit's are a thin renaming — and an engine that has no business drawing a view has no
        // business importing the view framework.
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): cgColor(style.textColor),
        ]

        // An outline rather than a shadow. Short video is watched over whatever happens to be
        // behind the words, and a stroke is the only thing that survives white footage.
        if style.backgroundColor == nil {
            attributes[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = cgColor(.black)
            // Negative means stroke *and* fill; positive would draw the outline only.
            attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = -fontSize * 0.14
        }

        return NSAttributedString(string: text, attributes: attributes)
    }

    /// The size a string needs at a given width, from Core Text's own line breaking — the same
    /// breaking the text layer will use, so the box and the words agree.
    private static func measure(_ string: NSAttributedString, maxWidth: CGFloat) -> CGSize {
        let framesetter = CTFramesetterCreateWithAttributedString(string as CFAttributedString)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: string.length),
            nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            nil
        )
        return CGSize(width: ceil(min(size.width, maxWidth)) + 2, height: ceil(size.height) + 2)
    }

    /// The whole line, with only one word visible — in the highlight colour — and the rest clear.
    private static func highlighted(
        _ words: [String],
        lit: Int,
        style: CaptionStyle,
        color: RGBAColor,
        fontSize: CGFloat
    ) -> NSAttributedString {
        let base = attributed(words.joined(separator: " "), style: style, fontSize: fontSize)
        let result = NSMutableAttributedString(attributedString: base)
        let clear = CGColor(gray: 0, alpha: 0)
        let whole = NSRange(location: 0, length: result.length)
        result.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: clear, range: whole)
        result.addAttribute(NSAttributedString.Key(kCTStrokeColorAttributeName as String), value: clear, range: whole)

        let offset = words.prefix(lit).reduce(0) { $0 + ($1 as NSString).length + 1 }
        let range = NSRange(location: offset, length: (words[lit] as NSString).length)
        result.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: cgColor(color), range: range)
        if style.backgroundColor == nil {
            result.addAttribute(NSAttributedString.Key(kCTStrokeColorAttributeName as String), value: cgColor(.black), range: range)
        }
        return result
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
