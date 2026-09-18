import AVFoundation
import CoreImage
import Domain
import Foundation
import Testing
@testable import MediaEngine

/// A background that has been rendered is what the preview plays: the render, the file's name and
/// the composition agree. On the phone a finished render once left the preview as shot.
@Suite(.serialized)
struct BackgroundPlaybackTests {
    private typealias Clips = TransitionRendererTests

    private func project(effectFrom from: Double, to: Double, settings: BackgroundSettings) -> Project {
        let red = Recording(relativePath: "red.mov", format: .vertical1080, camera: .back, duration: MediaTime(seconds: 2))
        var project = Project(title: "t", localeIdentifier: "en-US", segments: [Clips.segment(red)], recordings: [red])
        project.effects = [TimelineEffect(
            start: MediaTime(seconds: from),
            duration: MediaTime(seconds: to - from),
            kind: .background(settings)
        )]
        return project
    }

    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "background-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A finished copy beside the footage is played in place of the footage, over the whole clip
    /// and over part of it.
    @Test(arguments: [[0.0, 2.0], [0.5, 1.5]])
    func aFinishedCopyIsWhatPlays(_ edges: [Double]) async throws {
        let span = (edges[0], edges[1])
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await Clips.writeClip(named: "red.mov", red: 1, green: 0, blue: 0, in: folder)
        let project = project(effectFrom: span.0, to: span.1, settings: BackgroundSettings(style: .dim))

        // Stand in for the render: a blue copy under the name the render would give it.
        let job = try #require(BackgroundRemover.jobs(for: project, in: folder).first)
        try await Clips.writeClip(named: job.name, red: 0, green: 0, blue: 1, in: folder)

        let assembled = try await VideoComposer().compose(project: project, mediaDirectory: folder, renderBackgrounds: false)
        Self.describe(assembled, label: "span \(span)")
        for moment in [0.1, 1.0, 1.9] {
            let colour = try? await Clips.averageColour(of: assembled, at: moment)
            print("DIAG span \(span) at \(moment): \(String(describing: colour))")
        }
        let inside = try await Clips.averageColour(of: assembled, at: (span.0 + span.1) / 2)
        #expect(inside.blue > 0.8 && inside.red < 0.2, "inside the effect the preview shows \(inside)")
        if span.0 > 0 {
            let before = try await Clips.averageColour(of: assembled, at: span.0 / 2)
            #expect(before.red > 0.8, "before the effect the preview shows \(before)")
        }
    }

    /// What the composition is made of, printed for the log.
    static func describe(_ assembled: VideoComposer.Assembled, label: String) {
        let composition = assembled.composition
        print("DIAG \(label) duration \(composition.duration.seconds)")
        for track in composition.tracks {
            print("DIAG \(label) track \(track.trackID) \(track.mediaType.rawValue)")
            for segment in track.segments {
                let map = segment.timeMapping
                print("DIAG \(label)   source \(map.source.start.seconds)+\(map.source.duration.seconds) -> \(map.target.start.seconds)+\(map.target.duration.seconds) empty=\(segment.isEmpty)")
            }
        }
        for case let instruction as AVVideoCompositionInstruction in assembled.videoComposition.instructions {
            print("DIAG \(label) instruction \(instruction.timeRange.start.seconds)+\(instruction.timeRange.duration.seconds)")
            for layer in instruction.layerInstructions {
                var a = CGAffineTransform.identity, b = CGAffineTransform.identity, range = CMTimeRange.invalid
                let ramp = layer.getTransformRamp(for: instruction.timeRange.start, start: &a, end: &b, timeRange: &range)
                var cropA = CGRect.zero, cropB = CGRect.zero, cropRange = CMTimeRange.invalid
                let crop = layer.getCropRectangleRamp(for: instruction.timeRange.start, startCropRectangle: &cropA, endCropRectangle: &cropB, timeRange: &cropRange)
                print("DIAG \(label)   layer \(layer.trackID) transform(\(ramp)) \(a) crop(\(crop)) \(cropA)")
            }
        }
        print("DIAG \(label) render \(assembled.videoComposition.renderSize) custom \(String(describing: assembled.videoComposition.customVideoCompositorClass))")
    }

    /// The real render, start to end: red keyed out as the screen, black behind it, and the
    /// composition then shows black.
    @Test func aRenderedBackgroundIsShown() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await Clips.writeClip(named: "red.mov", red: 1, green: 0, blue: 0, in: folder)
        let settings = BackgroundSettings(
            style: .black,
            cutout: .color,
            key: ChromaKey(color: RGBAColor(red: 1, green: 0, blue: 0), tolerance: 0.5, softness: 0.1)
        )
        let project = project(effectFrom: 0, to: 2, settings: settings)
        let job = try #require(BackgroundRemover.jobs(for: project, in: folder).first)
        let written = await BackgroundRemover().render(
            source: job.source,
            range: job.range,
            settings: job.settings,
            destination: job.destination
        )
        #expect(written != nil)
        let file = try await Clips.averageColour(of: job.destination, at: 1)
        #expect(file.red < 0.2, "the render wrote \(file)")

        let assembled = try await VideoComposer().compose(project: project, mediaDirectory: folder, renderBackgrounds: false)
        let shown = try await Clips.averageColour(of: assembled, at: 1)
        #expect(shown.red < 0.2, "the preview shows \(shown)")
    }
}
