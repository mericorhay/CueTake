import CoreGraphics
import CoreText
import Domain
import Foundation

/// The words the floating window writes on itself, localized on the main actor beforehand.
nonisolated struct SuflorChromeText: Sendable {
    var live: String
    var video: String
    var toAd: String
    var ad: String
    var paused: String
    var hold: String
    var holdManual: String
    var done: String
}

/// Everything one frame needs, taken in one piece under the engine's lock.
nonisolated struct SuflorFrame: @unchecked Sendable {
    var clock: SuflorClock
    var layout: SuflorLayout
    var kind: SuflorBrief.Kind
    var text: SuflorChromeText
    var fonts: SuflorFonts

    var isInAd: Bool {
        guard let top = layout.adTop, let bottom = layout.adBottom else { return false }
        return clock.offset >= Double(top) + Double(layout.fontSize) && clock.offset <= Double(bottom) + Double(layout.fontSize)
    }
}

/// Draws the prompter. The stage on the phone draws the text with it inside a Canvas; the floating
/// window draws the text and its own status on top into each video frame. The context is expected
/// in the layout's points, y down.
nonisolated enum SuflorPainter {
    /// The reading line, as a share of the height: high, near the camera.
    static let readingLine: CGFloat = 0.34

    // MARK: - Text

    static func drawText(_ cg: CGContext, frame: SuflorFrame, size: CGSize) {
        let layout = frame.layout
        let offset = CGFloat(frame.clock.offset)
        let reading = size.height * readingLine
        let fade = size.height * 0.16

        // The ad glows up from below while it is on the reading line.
        if frame.isInAd {
            let colors = [SuflorInk.accent(0.22), SuflorInk.accent(0)] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
                cg.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: size.width / 2, y: size.height * 1.05), startRadius: 0,
                    endCenter: CGPoint(x: size.width / 2, y: size.height * 1.05), endRadius: size.height * 0.9,
                    options: []
                )
            }
        }

        cg.saveGState()
        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for line in layout.lines {
            let y = line.baseline - offset + reading
            guard y + line.descent > -8, y - line.ascent < size.height + 8 else { continue }
            let distance = line.center - offset
            var alpha: CGFloat
            if distance < -layout.fontSize * 0.62 {
                alpha = line.isLabel ? 0.22 : 0.3
            } else if distance <= layout.fontSize * 0.62 {
                alpha = 1
            } else {
                alpha = max(0.5, 0.86 - distance / size.height * 0.5)
            }
            let top = y - line.ascent
            if top < fade { alpha *= max(0, top / fade) }
            let bottom = size.height - (y + line.descent)
            if bottom < fade { alpha *= max(0, bottom / fade) }
            guard alpha > 0.01 else { continue }
            cg.setAlpha(alpha)
            cg.textPosition = CGPoint(x: SuflorLayout.inset, y: y)
            CTLineDraw(line.line, cg)
        }
        cg.restoreGState()

        // The reading line's mark: a small lime notch at the edge, where the eye returns.
        cg.saveGState()
        cg.setFillColor(SuflorInk.lime)
        let notch = CGMutablePath()
        notch.move(to: CGPoint(x: 8, y: reading - 6))
        notch.addLine(to: CGPoint(x: 15, y: reading))
        notch.addLine(to: CGPoint(x: 8, y: reading + 6))
        notch.closeSubpath()
        cg.addPath(notch)
        cg.fillPath()
        cg.restoreGState()
    }

    // MARK: - Floating window

    /// A whole frame of the floating window: ground, text, status.
    static func drawWindow(_ cg: CGContext, frame: SuflorFrame, size: CGSize) {
        cg.setFillColor(SuflorInk.screen)
        cg.fill(CGRect(origin: .zero, size: size))
        drawText(cg, frame: frame, size: size)
        drawStatus(cg, frame: frame, size: size)
    }

    private static func drawStatus(_ cg: CGContext, frame: SuflorFrame, size: CGSize) {
        let clock = frame.clock
        let fonts = frame.fonts
        let phase = clock.phase

        // Top left: live and for how long, the red dot breathing once a second.
        let pulse = 0.55 + 0.45 * CGFloat(abs(sin(clock.elapsed * .pi)))
        let title = frame.kind == .live ? frame.text.live : frame.text.video
        let liveText = "\(title)  \(SuflorSession.clock(max(0, clock.elapsed - SuflorClock.countdown)))"
        pill(cg, at: CGPoint(x: 14, y: 14), text: liveText, font: fonts.chromeBold, ink: SuflorInk.white(0.92), fill: SuflorInk.white(0.1), leadingDot: SuflorInk.accent(pulse))

        // Top right: the ad, counted down, then lit.
        if frame.isInAd {
            pill(cg, trailing: CGPoint(x: size.width - 14, y: 14), text: frame.text.ad, font: fonts.chromeBold, ink: SuflorInk.screen, fill: SuflorInk.accent)
        } else if let seconds = clock.secondsToAd {
            let urgent = seconds <= 30
            pill(
                cg, trailing: CGPoint(x: size.width - 14, y: 14),
                text: "\(frame.text.toAd) \(SuflorSession.clock(seconds.rounded(.up)))",
                font: fonts.chromeBold,
                ink: urgent ? SuflorInk.screen : SuflorInk.amber,
                fill: urgent ? SuflorInk.amber : SuflorInk.amber(0.16)
            )
        }

        // Progress along the bottom, the ad marked on it.
        let track = CGRect(x: 16, y: size.height - 12, width: size.width - 32, height: 3)
        cg.setFillColor(SuflorInk.white(0.12))
        cg.addPath(CGPath(roundedRect: track, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
        cg.fillPath()
        let end = max(1, CGFloat(frame.layout.end))
        if let top = frame.layout.adTop, let bottom = frame.layout.adBottom {
            let ad = CGRect(x: track.minX + track.width * top / end, y: track.minY, width: track.width * max(0, bottom - top) / end, height: track.height)
            cg.setFillColor(SuflorInk.accent(0.45))
            cg.fill(ad)
        }
        let done = CGRect(x: track.minX, y: track.minY, width: track.width * min(1, CGFloat(clock.offset) / end), height: track.height)
        cg.setFillColor(SuflorInk.lime)
        cg.addPath(CGPath(roundedRect: done, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
        cg.fillPath()

        switch phase {
        case .countdown:
            countdown(cg, frame: frame, size: size)
        case .holding:
            hold(cg, frame: frame, size: size)
        case .finished:
            pill(cg, center: CGPoint(x: size.width / 2, y: size.height - 40), text: frame.text.done, font: fonts.chromeBold, ink: SuflorInk.screen, fill: SuflorInk.lime)
        case .rolling:
            if !clock.isPlaying {
                pill(cg, center: CGPoint(x: size.width / 2, y: size.height - 40), text: frame.text.paused, font: fonts.chromeBold, ink: SuflorInk.white(0.92), fill: SuflorInk.white(0.16))
            }
        }
    }

    /// 3, 2, 1 — each number landing with a ring that empties with its second.
    private static func countdown(_ cg: CGContext, frame: SuflorFrame, size: CGSize) {
        let left = SuflorClock.countdown - frame.clock.elapsed
        let number = Int(left.rounded(.up))
        let share = CGFloat(left - floor(left))
        cg.setFillColor(SuflorInk.screen.copy(alpha: 0.72) ?? SuflorInk.screen)
        cg.fill(CGRect(origin: .zero, size: size))
        let center = CGPoint(x: size.width / 2, y: size.height * 0.46)
        ring(cg, center: center, radius: 58, share: share, color: SuflorInk.lime, width: 5)
        let scale = 1 + (share > 0.8 ? (share - 0.8) * 1.2 : 0)
        text(cg, "\(max(1, number))", font: frame.fonts.display, ink: SuflorInk.white(1), center: center, scale: scale)
    }

    /// Waiting at the ad: the minute counted down in a ring, gold as it nears.
    private static func hold(_ cg: CGContext, frame: SuflorFrame, size: CGSize) {
        let reading = size.height * readingLine
        let card = CGRect(x: 22, y: reading + 26, width: size.width - 44, height: 92)
        cg.setFillColor(SuflorInk.surface.copy(alpha: 0.94) ?? SuflorInk.surface)
        cg.addPath(CGPath(roundedRect: card, cornerWidth: 20, cornerHeight: 20, transform: nil))
        cg.fillPath()
        cg.setStrokeColor(SuflorInk.amber(0.4))
        cg.setLineWidth(1)
        cg.addPath(CGPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 20, cornerHeight: 20, transform: nil))
        cg.strokePath()

        let ringCenter = CGPoint(x: card.minX + 46, y: card.midY)
        if let seconds = frame.clock.secondsToAd, let adAt = frame.clock.adAt {
            let total = max(1, adAt - SuflorClock.countdown)
            let urgent = seconds <= 5
            let glow = urgent ? 0.6 + 0.4 * CGFloat(abs(sin(frame.clock.elapsed * .pi * 2))) : 1
            ring(cg, center: ringCenter, radius: 28, share: CGFloat(1 - seconds / total), color: SuflorInk.amber(glow), width: 4)
            text(cg, SuflorSession.clock(seconds.rounded(.up)), font: frame.fonts.chromeBold, ink: SuflorInk.white(1), center: ringCenter, scale: 1)
            text(cg, frame.text.hold, font: frame.fonts.chrome, ink: SuflorInk.white(0.86), left: CGPoint(x: card.minX + 90, y: card.midY), maxWidth: card.width - 104)
        } else {
            ring(cg, center: ringCenter, radius: 28, share: 1, color: SuflorInk.amber, width: 4)
            text(cg, "»", font: frame.fonts.chromeBold, ink: SuflorInk.amber, center: ringCenter, scale: 1.6)
            text(cg, frame.text.holdManual, font: frame.fonts.chrome, ink: SuflorInk.white(0.86), left: CGPoint(x: card.minX + 90, y: card.midY), maxWidth: card.width - 104)
        }
    }

    // MARK: - Pieces

    private static func ring(_ cg: CGContext, center: CGPoint, radius: CGFloat, share: CGFloat, color: CGColor, width: CGFloat) {
        cg.saveGState()
        cg.setLineWidth(width)
        cg.setLineCap(.round)
        cg.setStrokeColor(SuflorInk.white(0.12))
        cg.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        cg.strokePath()
        cg.setStrokeColor(color)
        let start = -CGFloat.pi / 2
        cg.addArc(center: center, radius: radius, startAngle: start, endAngle: start + .pi * 2 * max(0.001, min(1, share)), clockwise: false)
        cg.strokePath()
        cg.restoreGState()
    }

    private static func measure(_ string: String, font: CTFont, ink: CGColor) -> (CTLine, CGFloat, CGFloat, CGFloat) {
        let attributed = NSAttributedString(string: string, attributes: [.font: font, SuflorLayout.ink: ink, .kern: 0.6])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return (line, width, ascent, descent)
    }

    private static func text(_ cg: CGContext, _ string: String, font: CTFont, ink: CGColor, center: CGPoint, scale: CGFloat) {
        let (line, width, ascent, descent) = measure(string, font: font, ink: ink)
        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        cg.scaleBy(x: scale, y: scale)
        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        cg.textPosition = CGPoint(x: -width / 2, y: (ascent - descent) / 2)
        CTLineDraw(line, cg)
        cg.restoreGState()
    }

    private static func text(_ cg: CGContext, _ string: String, font: CTFont, ink: CGColor, left: CGPoint, maxWidth: CGFloat) {
        // Two lines at most, broken by Core Text.
        let attributed = NSAttributedString(string: string, attributes: [.font: font, SuflorLayout.ink: ink])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let tall: CGFloat = 400
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: CGRect(x: 0, y: 0, width: maxWidth, height: tall), transform: nil), nil)
        let lines = (CTFrameGetLines(frame) as? [CTLine] ?? []).prefix(2)
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: lines.count), &origins)
        guard let firstOrigin = origins.first, let lastOrigin = origins.last else { return }
        let block = firstOrigin.y - lastOrigin.y
        cg.saveGState()
        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (line, origin) in zip(lines, origins) {
            cg.textPosition = CGPoint(x: left.x, y: left.y - block / 2 + (firstOrigin.y - origin.y) + CTFontGetAscent(font) * 0.36)
            CTLineDraw(line, cg)
        }
        cg.restoreGState()
    }

    @discardableResult
    private static func pill(_ cg: CGContext, at origin: CGPoint, text string: String, font: CTFont, ink: CGColor, fill: CGColor, leadingDot: CGColor? = nil) -> CGFloat {
        let (line, width, ascent, descent) = measure(string, font: font, ink: ink)
        let dot: CGFloat = leadingDot == nil ? 0 : 14
        let rect = CGRect(x: origin.x, y: origin.y, width: width + 22 + dot, height: ascent + descent + 14)
        cg.saveGState()
        cg.setFillColor(fill)
        cg.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
        cg.fillPath()
        if let leadingDot {
            cg.setFillColor(leadingDot)
            cg.fillEllipse(in: CGRect(x: rect.minX + 11, y: rect.midY - 3.5, width: 7, height: 7))
        }
        cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        cg.textPosition = CGPoint(x: rect.minX + 11 + dot, y: rect.midY + (ascent - descent) / 2)
        CTLineDraw(line, cg)
        cg.restoreGState()
        return rect.width
    }

    private static func pill(_ cg: CGContext, trailing: CGPoint, text string: String, font: CTFont, ink: CGColor, fill: CGColor) {
        let (_, width, _, _) = measure(string, font: font, ink: ink)
        pill(cg, at: CGPoint(x: trailing.x - width - 22, y: trailing.y), text: string, font: font, ink: ink, fill: fill)
    }

    private static func pill(_ cg: CGContext, center: CGPoint, text string: String, font: CTFont, ink: CGColor, fill: CGColor) {
        let (_, width, ascent, descent) = measure(string, font: font, ink: ink)
        pill(cg, at: CGPoint(x: center.x - (width + 22) / 2, y: center.y - (ascent + descent + 14) / 2), text: string, font: font, ink: ink, fill: fill)
    }
}
