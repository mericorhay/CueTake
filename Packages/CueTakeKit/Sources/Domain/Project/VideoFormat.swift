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
        /// 8K. Shot on the phones that can, and on every cinema camera footage arrives from.
        /// Downscaling it on import would be deciding for the user that their best material is
        /// too good for us.
        case uhd8K

        /// The short edge. Every frame size in the app is built from this and the aspect ratio,
        /// so a new resolution is one line rather than a table of nine.
        public var shortEdge: Int {
            switch self {
            case .hd1080: 1080
            case .uhd4K: 2160
            case .uhd8K: 4320
            }
        }

        public var label: String {
            switch self {
            case .hd1080: "1080p"
            case .uhd4K: "4K"
            case .uhd8K: "8K"
            }
        }

        /// H.264 has no level that carries 4K well and none at all that carries 8K. Above 1080p
        /// the only honest answer is HEVC, which is also roughly half the file for the same eye.
        public var prefersHEVC: Bool { self != .hd1080 }
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
    /// Scaled from pixels and frames rather than looked up in a table, so an 8K 120fps project
    /// gets a bitrate that follows from what it is instead of from what somebody remembered to
    /// add to a switch statement.
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

    /// True when the project asks for more than a slow-motion capture can hold: 120fps only
    /// exists at 1080p and 4K on hardware, and claiming 8K120 would be promising a file no phone
    /// on earth writes.
    public var isPhysicallyPlausible: Bool {
        switch (resolution, frameRate) {
        case (.uhd8K, let fps) where fps > 30: false
        case (.uhd4K, let fps) where fps > 120: false
        default: true
        }
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
