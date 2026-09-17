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
/// cues are layers over it, and Core Animation's own timeline decides what is on screen. Each word
/// is its own layer, laid out by `CaptionLineBreaker` and moved by `CaptionAnimator` — the same two
/// the editor's SwiftUI preview uses — sampled into keyframes.
enum CaptionRenderer {
    /// Keyframes a second for the sampled animations.
    static let samplesPerSecond = 30.0

    /// The layer tree, or nil when there is nothing to draw.
    static func tool(
        cues: [PlacedCue],
        style: CaptionStyle,
        locale: Locale,
        renderSize: CGSize,
        positions: [PlacedCue.ID: CaptionPosition] = [:],
        underlays: [CALayer] = []
    ) -> AVVideoCompositionCoreAnimationTool? {
        guard !cues.isEmpty || !underlays.isEmpty, renderSize.width > 0, renderSize.height > 0 else { return nil }

        let frame = CGRect(origin: .zero, size: renderSize)
        let parent = CALayer()
        parent.frame = frame
        parent.isGeometryFlipped = false

        let video = CALayer()
        video.frame = frame
        parent.addSublayer(video)
        // Pictures and text sit over the video and under the captions.
        for layer in underlays { parent.addSublayer(layer) }

        let fontSize = max(12, renderSize.height * style.relativeFontSize)
        let font = makeFont(style, size: fontSize)
        for cue in cues {
            if let layer = cueLayer(
                cue,
                style: style,
                locale: locale,
                font: font,
                fontSize: fontSize,
                renderSize: renderSize,
                position: positions[cue.id] ?? cue.position ?? style.position
            ) {
                parent.addSublayer(layer)
            }
        }

        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: video, in: parent)
    }

    /// One cue: a container (with the plate, if any) holding one group per word.
    static func cueLayer(
        _ cue: PlacedCue,
        style: CaptionStyle,
        locale: Locale,
        font: CTFont,
        fontSize: CGFloat,
        renderSize: CGSize,
        position: CaptionPosition
    ) -> CALayer? {
        let display = CaptionWords(cue: cue, style: style, locale: locale)
        guard !display.words.isEmpty else { return nil }

        let inset: CGSize = style.backgroundColor == nil
            ? CGSize(width: fontSize * 0.3, height: fontSize * 0.2)
            : CGSize(width: fontSize * 0.55, height: fontSize * 0.28)
        // Room for the outline, the growth of an emphasised word, and its card.
        let pad = fontSize * 0.16
        let widths = display.words.map {
            Double(width(of: attributed($0, style: style, font: font, fontSize: fontSize, color: style.textColor)))
        }
        let space = Double(width(of: attributed(" ", style: style, font: font, fontSize: fontSize, color: style.textColor)))
        let maxWidth = Double(renderSize.width * 0.86 - inset.width * 2)
        let lines = CaptionLineBreaker.lines(widths: widths, space: space, maxWidth: maxWidth)
        let lineHeight = (CTFontGetAscent(font) + CTFontGetDescent(font)) * 1.14
        let lineWidths = lines.map { line in
            line.map { widths[$0] }.reduce(0, +) + space * Double(max(0, line.count - 1))
        }
        let blockWidth = CGFloat(lineWidths.max() ?? 0)
        let blockHeight = CGFloat(lines.count) * lineHeight

        let size = CGSize(width: blockWidth + inset.width * 2, height: blockHeight + inset.height * 2)
        // Core Animation counts up from the bottom here; the position is given from the top.
        let center = CGPoint(x: renderSize.width * position.x, y: renderSize.height * (1 - position.y))
        let container = CALayer()
        container.frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        container.opacity = 0
        if let background = style.backgroundColor {
            container.backgroundColor = cgColor(background)
            container.cornerRadius = fontSize * 0.32
        }

        let emphasis = style.resolvedEmphasis
        var groups: [Int: CALayer] = [:]
        var lits: [Int: CALayer] = [:]
        var boxes: [Int: CALayer] = [:]
        for (lineIndex, line) in lines.enumerated() {
            var x = (size.width - CGFloat(lineWidths[lineIndex])) / 2
            let y = size.height - inset.height - CGFloat(lineIndex + 1) * lineHeight
            for index in line {
                let wordWidth = CGFloat(widths[index])
                let rect = CGRect(x: x, y: y, width: wordWidth, height: lineHeight).insetBy(dx: -pad, dy: -pad * 0.4)
                x += wordWidth + CGFloat(space)

                let group = CALayer()
                group.frame = rect
                let bounds = CGRect(origin: .zero, size: rect.size)

                if emphasis == .box {
                    let card = CALayer()
                    card.frame = bounds.insetBy(dx: pad * 0.3, dy: 0)
                    card.backgroundColor = cgColor(style.emphasisColor)
                    card.cornerRadius = fontSize * 0.18
                    card.opacity = 0
                    group.addSublayer(card)
                    boxes[index] = card
                }

                let colour = display.keywords.contains(index) ? (style.keywordColor ?? style.textColor) : style.textColor
                group.addSublayer(textLayer(display.words[index], style: style, font: font, fontSize: fontSize, color: colour, frame: bounds, pad: pad))

                let showsLit = emphasis == .color || emphasis == .box || (emphasis == .scale && style.highlightColor != nil)
                if showsLit {
                    let litColour = emphasis == .box ? style.boxedTextColor : style.emphasisColor
                    let layer = textLayer(
                        display.words[index],
                        style: style,
                        font: font,
                        fontSize: fontSize,
                        color: litColour,
                        frame: bounds,
                        pad: pad,
                        outlined: emphasis != .box
                    )
                    layer.opacity = 0
                    group.addSublayer(layer)
                    lits[index] = layer
                }
                container.addSublayer(group)
                groups[index] = group
            }
        }

        animate(cue: cue, style: style, wordCount: display.words.count, fontSize: fontSize, container: container, groups: groups, lits: lits, boxes: boxes)
        return container
    }

    private static func animate(
        cue: PlacedCue,
        style: CaptionStyle,
        wordCount: Int,
        fontSize: CGFloat,
        container: CALayer,
        groups: [Int: CALayer],
        lits: [Int: CALayer],
        boxes: [Int: CALayer]
    ) {
        let start = cue.range.start.seconds
        let duration = max(0.05, cue.range.duration.seconds)
        let count = max(2, min(900, Int((duration * samplesPerSecond).rounded(.up)) + 1))
        let times = (0..<count).map { start + duration * Double($0) / Double(count - 1) }
        let frames = times.map { CaptionAnimator.frame(for: cue, wordCount: wordCount, style: style, at: $0) }
        let keyTimes = (0..<count).map { NSNumber(value: Double($0) / Double(count - 1)) }

        var opacity = frames.map(\.opacity)
        opacity[0] = 0
        opacity[count - 1] = 0
        add(container, "opacity", opacity.map { NSNumber(value: $0) }, keyTimes, start, duration)
        if frames.contains(where: { abs($0.scale - 1) > 0.001 || abs($0.offset) > 0.001 }) {
            let values = frames.map { NSValue(caTransform3D: transform(scale: $0.scale, offset: $0.offset, fontSize: fontSize)) }
            add(container, "transform", values, keyTimes, start, duration)
        }

        for index in 0..<wordCount {
            let words = frames.map { $0.words[index] }
            if let group = groups[index] {
                if words.contains(where: { $0.opacity < 0.999 }) {
                    add(group, "opacity", words.map { NSNumber(value: $0.opacity) }, keyTimes, start, duration)
                }
                if words.contains(where: { abs($0.scale - 1) > 0.001 || abs($0.offset) > 0.001 }) {
                    let values = words.map { NSValue(caTransform3D: transform(scale: $0.scale, offset: $0.offset, fontSize: fontSize)) }
                    add(group, "transform", values, keyTimes, start, duration)
                }
            }
            if let lit = lits[index] {
                let on: [Double] = words.map { word in
                    switch style.resolvedEmphasis {
                    case .color: word.isLit ? 1 : 0
                    case .box: word.box
                    default: word.isActive ? 1 : 0
                    }
                }
                if on.contains(where: { $0 > 0 }) {
                    add(lit, "opacity", on.map { NSNumber(value: $0) }, keyTimes, start, duration)
                }
            }
            if let box = boxes[index] {
                let on = words.map(\.box)
                if on.contains(where: { $0 > 0 }) {
                    add(box, "opacity", on.map { NSNumber(value: $0) }, keyTimes, start, duration)
                }
            }
        }
    }

    /// Scale about the layer's centre, then a vertical nudge (positive is down on screen).
    private static func transform(scale: Double, offset: Double, fontSize: CGFloat) -> CATransform3D {
        let moved = CATransform3DMakeTranslation(0, -CGFloat(offset) * fontSize, 0)
        return CATransform3DScale(moved, CGFloat(scale), CGFloat(scale), 1)
    }

    private static func add(_ layer: CALayer, _ keyPath: String, _ values: [Any], _ keyTimes: [NSNumber], _ start: Double, _ duration: Double) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes
        // `AVCoreAnimationBeginTimeAtZero` rather than 0: a begin time of exactly zero means "now"
        // to Core Animation, and every cue would appear at once on the first frame.
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + start
        animation.duration = duration
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
        layer.add(animation, forKey: keyPath)
    }

    private static func textLayer(
        _ word: String,
        style: CaptionStyle,
        font: CTFont,
        fontSize: CGFloat,
        color: RGBAColor,
        frame: CGRect,
        pad: CGFloat,
        outlined: Bool = true
    ) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = attributed(word, style: style, font: font, fontSize: fontSize, color: color, outlined: outlined)
        layer.alignmentMode = .center
        layer.isWrapped = false
        layer.truncationMode = .none
        // Rendered at the video's own scale, not the screen's: at 1 the text is soft on anything
        // above 1080p, and captions are the one thing in the frame made of edges.
        layer.contentsScale = 2
        layer.frame = frame.insetBy(dx: 0, dy: pad * 0.4)
        if style.shadow == true {
            layer.shadowColor = CGColor(gray: 0, alpha: 1)
            layer.shadowOpacity = 0.55
            layer.shadowRadius = fontSize * 0.1
            layer.shadowOffset = CGSize(width: 0, height: -fontSize * 0.04)
        }
        return layer
    }

    static func makeFont(_ style: CaptionStyle, size: CGFloat) -> CTFont {
        if let name = style.fontName {
            return CTFontCreateWithName(name as CFString, size, nil)
        }
        // Heavy by default. A caption is read at a glance over moving pictures, and weight is what
        // carries it there — not size, which only costs the frame.
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: "Helvetica Neue" as CFString,
            kCTFontTraitsAttribute: [kCTFontSymbolicTrait: CTFontSymbolicTraits.traitBold.rawValue],
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    static func attributed(
        _ text: String,
        style: CaptionStyle,
        font: CTFont,
        fontSize: CGFloat,
        color: RGBAColor,
        outlined: Bool = true
    ) -> NSAttributedString {
        // Core Text's own attribute names rather than UIKit's: an engine that has no business
        // drawing a view has no business importing the view framework.
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): cgColor(color),
        ]
        // An outline rather than a shadow. Short video is watched over whatever happens to be
        // behind the words, and a stroke is the only thing that survives white footage.
        let weight = style.resolvedStrokeWeight
        if outlined, weight > 0.001 {
            attributes[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = cgColor(style.resolvedStrokeColor)
            // Negative means stroke *and* fill; positive would draw the outline only.
            attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = -fontSize * weight
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    /// The width a string takes on one line, from Core Text.
    static func width(of string: NSAttributedString) -> CGFloat {
        let line = CTLineCreateWithAttributedString(string as CFAttributedString)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// The size a string needs at a given width, from Core Text's own line breaking.
    static func measure(_ string: NSAttributedString, maxWidth: CGFloat) -> CGSize {
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

    static func cgColor(_ color: RGBAColor) -> CGColor {
        CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [CGFloat(color.red), CGFloat(color.green), CGFloat(color.blue), CGFloat(color.alpha)]
        ) ?? CGColor(gray: 1, alpha: 1)
    }
}
