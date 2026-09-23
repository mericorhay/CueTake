import Foundation

public struct VideoFormat: Hashable, Sendable, Codable {
    public enum AspectRatio: String, Hashable, Sendable, Codable, CaseIterable {
        case portrait9x16
        case landscape16x9
        case square1x1
    }

    public enum Resolution: String, Hashable, Sendable, Codable, CaseIterable {
        case hd1080
        case uhd4K

        /// The short edge. Every frame size in the app is built from this and the aspect ratio,
        /// so a new resolution is one line rather than a table of nine.
        public var shortEdge: Int {
            switch self {
            case .hd1080: 1080
            case .uhd4K: 2160
            }
        }

        public var label: String {
            switch self {
            case .hd1080: "1080p"
            case .uhd4K: "4K"
            }
        }

        /// Above 1080p HEVC keeps the file practical while preserving detail.
        public var prefersHEVC: Bool { self != .hd1080 }

        /// Older projects could persist the retired ultra-high-resolution option.
        /// Open those projects safely at the highest format CueTake now supports.
        public init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer().decode(String.self)
            switch value {
            case Self.hd1080.rawValue:
                self = .hd1080
            case Self.uhd4K.rawValue, "uhd8K":
                self = .uhd4K
            default:
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Unsupported video resolution: \(value)")
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    /// What the frame-rate control offers. 24 for the film look, 30 as the default everything
    /// expects, 60 for motion, 120 for slow motion with frames to spare.
    public static let frameRateChoices = [24, 30, 60, 120]

    public var aspectRatio: AspectRatio
    public var resolution: Resolution
    public var frameRate: Int

    public init(aspectRatio: AspectRatio, resolution: Resolution, frameRate: Int = 30) {
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.frameRate = frameRate
    }

    /// Reels / Shorts / TikTok.
    public static let vertical1080 = VideoFormat(aspectRatio: .portrait9x16, resolution: .hd1080)
    public static let horizontal1080 = VideoFormat(aspectRatio: .landscape16x9, resolution: .hd1080)

    public var renderSize: PixelSize {
        let short = resolution.shortEdge
        let long = short * 16 / 9
        switch aspectRatio {
        case .portrait9x16: return PixelSize(width: short, height: long)
        case .landscape16x9: return PixelSize(width: long, height: short)
        case .square1x1: return PixelSize(width: short, height: short)
        }
    }
}

extension VideoFormat {
    /// Roughly how many bits a second this frame costs at a quality nobody complains about.
    ///
    /// Scaled from pixels and frames rather than looked up in a table.
    public var suggestedBitRate: Int {
        let pixels = Double(renderSize.width * renderSize.height)
        let rate = Double(max(24, frameRate))
        // ~0.07 bits per pixel per frame for HEVC, ~0.13 for H.264.
        let perPixel = resolution.prefersHEVC ? 0.07 : 0.13
        return Int(pixels * rate * perPixel)
    }

    public var label: String {
        "\(resolution.label) · \(frameRate)fps"
    }

    /// CueTake keeps 4K at a broadly reliable delivery ceiling. High-frame-rate
    /// slow motion remains available at 1080p.
    public var isPhysicallyPlausible: Bool {
        switch (resolution, frameRate) {
        case (.uhd4K, let fps) where fps > 60: false
        default: true
        }
    }

    /// A format that the shared capture/render pipeline can promise on every supported device.
    /// Model-authored workflows and older documents can contain arbitrary frame rates, so the
    /// boundary normalizes them before AVFoundation sees them.
    public var deliveryCompatible: VideoFormat {
        let ceiling = resolution == .uhd4K ? 60 : 120
        let allowed = Self.frameRateChoices.filter { $0 <= ceiling }
        let nearest = allowed.min { abs($0 - frameRate) < abs($1 - frameRate) } ?? 30
        return VideoFormat(aspectRatio: aspectRatio, resolution: resolution, frameRate: nearest)
    }
}

public struct PixelSize: Hashable, Sendable, Codable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum CameraPosition: String, Hashable, Sendable, Codable {
    case front
    case back
}
