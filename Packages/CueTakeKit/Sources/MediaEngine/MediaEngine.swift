import AVFoundation
import Domain
import Foundation

// Offline media work over finished files: Timeline → AVComposition, caption layout, export.
// Playback and export consume the same composition, so what you preview is what you export.

public struct MediaComposition: @unchecked Sendable {
    // AVFoundation composition objects are treated as immutable once built.
    public let composition: AVComposition
    public let videoComposition: AVVideoComposition?

    public init(composition: AVComposition, videoComposition: AVVideoComposition?) {
        self.composition = composition
        self.videoComposition = videoComposition
    }
}

public enum MediaError: Error, Hashable, Sendable {
    case missingRecording(Recording.ID)
    case emptyTimeline
    case notImplemented
}

public protocol MediaComposing: Sendable {
    func makeComposition(
        for timeline: Timeline,
        format: VideoFormat,
        recordingURLs: [Recording.ID: URL]
    ) async throws -> MediaComposition
}

public enum ExportEvent: Hashable, Sendable {
    case progress(Double)
    case finished(URL)
}

public protocol VideoExporting: Sendable {
    func export(
        _ timeline: Timeline,
        of project: Project,
        preset: ExportPreset,
        recordingURLs: [Recording.ID: URL]
    ) -> AsyncThrowingStream<ExportEvent, any Error>
}

/// One caption layout for both the editor overlay and the export burn-in.
public protocol CaptionRendering: Sendable {
    func layout(
        _ caption: Timeline.PlacedCaption,
        style: CaptionStyle,
        localeIdentifier: String,
        renderSize: PixelSize
    ) -> CaptionLayout
}

public struct CaptionLayout: Hashable, Sendable {
    public struct Line: Hashable, Sendable {
        public var text: String
        /// Normalized to the render size, (0, 0) top-left.
        public var frame: NormalizedRect

        public init(text: String, frame: NormalizedRect) {
            self.text = text
            self.frame = frame
        }
    }

    public var lines: [Line]

    public init(lines: [Line]) {
        self.lines = lines
    }
}

public struct NormalizedRect: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct UnimplementedMediaComposer: MediaComposing {
    public init() {}

    public func makeComposition(
        for timeline: Timeline,
        format: VideoFormat,
        recordingURLs: [Recording.ID: URL]
    ) async throws -> MediaComposition {
        throw MediaError.notImplemented
    }
}

public struct UnimplementedVideoExporter: VideoExporting {
    public init() {}

    public func export(
        _ timeline: Timeline,
        of project: Project,
        preset: ExportPreset,
        recordingURLs: [Recording.ID: URL]
    ) -> AsyncThrowingStream<ExportEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: MediaError.notImplemented) }
    }
}
