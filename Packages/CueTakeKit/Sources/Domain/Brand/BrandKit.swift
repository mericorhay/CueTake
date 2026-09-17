import Foundation

/// How a creator's videos look: their colours, their face, their logo.
///
/// The voice (`BrandVoice`) says what the words are; this says what the picture is. Both are kept
/// on the phone and belong to the person rather than to one project, so every video they make
/// comes out recognisably theirs without setting it up again.
public struct BrandKit: Hashable, Sendable, Codable {
    /// The colour that carries attention: keywords in captions, the accent in titles.
    public var primary: RGBAColor
    /// Behind and around: caption outlines and plates.
    public var secondary: RGBAColor
    /// The reading colour of captions and titles.
    public var ink: RGBAColor
    /// PostScript name of the face captions and titles use. Nil keeps each look's own.
    public var fontName: String?
    /// The logo, kept with the app: a file name inside its brand folder.
    public var logoFile: String?
    /// The logo's width over its height, so it is never squashed.
    public var logoAspect: Double
    public var watermark: Watermark

    public init(
        primary: RGBAColor = RGBAColor(red: 1, green: 0.353, blue: 0.31),
        secondary: RGBAColor = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.85),
        ink: RGBAColor = .white,
        fontName: String? = nil,
        logoFile: String? = nil,
        logoAspect: Double = 1,
        watermark: Watermark = Watermark()
    ) {
        self.primary = primary
        self.secondary = secondary
        self.ink = ink
        self.fontName = fontName
        self.logoFile = logoFile
        self.logoAspect = logoAspect
        self.watermark = watermark
    }

    /// Where the logo sits and how loud it is.
    public struct Watermark: Hashable, Sendable, Codable {
        public var isOn: Bool
        public var corner: Corner
        /// The logo's width as a fraction of the frame's.
        public var width: Double
        public var opacity: Double
        /// Shown for this many seconds from the start, or nil for the whole video.
        public var seconds: Double?

        public init(isOn: Bool = false, corner: Corner = .topTrailing, width: Double = 0.16, opacity: Double = 0.8, seconds: Double? = nil) {
            self.isOn = isOn
            self.corner = corner
            self.width = width
            self.opacity = opacity
            self.seconds = seconds
        }
    }

    public enum Corner: String, Hashable, Sendable, Codable, CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        /// The centre of a logo of this width, in the frame, with a margin of its own.
        public func place(width: Double, aspect: Double, in format: VideoFormat) -> (x: Double, y: Double) {
            let size = format.renderSize
            let frameAspect = size.height > 0 ? Double(size.width) / Double(size.height) : 1
            // The logo's height as a fraction of the frame's height.
            let height = aspect > 0 ? width / aspect * frameAspect : width
            let margin = 0.045
            let x = self == .topLeading || self == .bottomLeading ? margin + width / 2 : 1 - margin - width / 2
            let y = self == .topLeading || self == .topTrailing ? margin + height / 2 : 1 - margin - height / 2
            return (min(max(x, 0.02), 0.98), min(max(y, 0.02), 0.98))
        }
    }

    public var isEmpty: Bool {
        fontName == nil && logoFile == nil && !watermark.isOn
            && primary == BrandKit().primary && secondary == BrandKit().secondary && ink == BrandKit().ink
    }

    /// The name a brand logo takes inside a project's media folder, so a project can be moved
    /// without losing it and the watermark can be recognised again later.
    public static let logoInProject = "brand-logo.png"
}

extension Project {
    /// Paints the project in the brand's colours and face.
    ///
    /// Captions and titles only: the footage is the user's own and a brand kit has no business
    /// grading it. Nothing is added or removed, so this can be applied and re-applied safely.
    public mutating func apply(_ kit: BrandKit) {
        captionStyle.textColor = kit.ink
        captionStyle.keywordColor = kit.primary
        if captionStyle.strokeColor != nil || captionStyle.backgroundColor != nil {
            captionStyle.strokeColor = captionStyle.strokeColor.map { _ in kit.secondary }
            captionStyle.backgroundColor = captionStyle.backgroundColor.map { _ in kit.secondary }
        }
        if let fontName = kit.fontName {
            captionStyle.fontName = fontName
        }
        for index in overlays.indices {
            guard case .text(var text) = overlays[index].content else { continue }
            text.color = kit.ink
            if text.background != nil { text.background = kit.secondary }
            if let fontName = kit.fontName { text.fontName = fontName }
            overlays[index].content = .text(text)
        }
    }

    /// Puts the brand's logo in its corner, or takes it away.
    ///
    /// - Parameter aspect: the logo's width over its height, measured from the file.
    public mutating func setWatermark(_ kit: BrandKit, aspect: Double? = nil, totalSeconds: Double) {
        overlays.removeAll { overlay in
            if case .image(let path, _) = overlay.content { return path == BrandKit.logoInProject }
            return false
        }
        guard kit.watermark.isOn, kit.logoFile != nil, totalSeconds > 0.2 else { return }
        let ratio = aspect ?? kit.logoAspect
        let place = kit.watermark.corner.place(width: kit.watermark.width, aspect: ratio, in: format)
        let seconds = min(kit.watermark.seconds ?? totalSeconds, totalSeconds)
        overlays.append(
            Overlay(
                content: .image(relativePath: BrandKit.logoInProject, aspect: ratio),
                start: .zero,
                duration: MediaTime(seconds: max(Overlay.shortest, seconds)),
                transform: OverlayTransform(
                    x: place.x,
                    y: place.y,
                    // `scale` 1 means half the frame's width.
                    scale: min(max(kit.watermark.width / 0.5, OverlayTransform.scaleRange.lowerBound), OverlayTransform.scaleRange.upperBound),
                    opacity: min(max(kit.watermark.opacity, 0.05), 1)
                ),
                animation: .fade
            )
        )
    }

    /// Whether this project is carrying the brand's logo.
    public var hasWatermark: Bool {
        overlays.contains { overlay in
            if case .image(let path, _) = overlay.content { return path == BrandKit.logoInProject }
            return false
        }
    }
}
