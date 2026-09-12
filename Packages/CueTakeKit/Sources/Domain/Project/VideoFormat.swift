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
    }

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
        let (short, long) = resolution == .hd1080 ? (1080, 1920) : (2160, 3840)
        switch aspectRatio {
        case .portrait9x16: return PixelSize(width: short, height: long)
        case .landscape16x9: return PixelSize(width: long, height: short)
        case .square1x1: return PixelSize(width: short, height: short)
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
