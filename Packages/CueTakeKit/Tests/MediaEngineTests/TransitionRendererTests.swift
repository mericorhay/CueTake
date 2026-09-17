import AVFoundation
import CoreImage
import Domain
import Foundation
import Testing
@testable import MediaEngine

/// Every transition, rendered for real between a red clip and a blue one, and looked at.
@Suite(.serialized)
struct TransitionRendererTests {
    struct Colour {
        var red: Double
        var green: Double
        var blue: Double
    }

    @Test(arguments: ClipTransition.Kind.allCases)
    func everyTransitionRendersFromTheFirstClipToTheSecond(_ kind: ClipTransition.Kind) async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "transition-test-\(kind.rawValue)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try await Self.writeClip(named: "red.mov", red: 1, green: 0, blue: 0, in: folder)
        try await Self.writeClip(named: "blue.mov", red: 0, green: 0, blue: 1, in: folder)

        let red = Recording(relativePath: "red.mov", format: .vertical1080, camera: .back, duration: MediaTime(seconds: 2))
        let blue = Recording(relativePath: "blue.mov", format: .vertical1080, camera: .back, duration: MediaTime(seconds: 2))
        var project = Project(
            title: "t",
            localeIdentifier: "en-US",
            segments: [Self.segment(red), Self.segment(blue)],
            recordings: [red, blue]
        )
        project.setTransition(after: project.segments[0].id, kind: kind, duration: 0.4)

        let job = try #require(TransitionRenderer.jobs(for: project, in: folder).first)
        #expect(!job.isReady)
        await TransitionRenderer.renderMissing(for: project, in: folder, renderBackgrounds: false)
        #expect(job.isReady, "\(kind.rawValue) wrote no film")

        let length = try await AVURLAsset(url: job.destination).load(.duration).seconds
        #expect(abs(length - 0.4) < 0.1, "\(kind.rawValue) lasts \(length)")

        let first = try await Self.averageColour(of: job.destination, at: 0)
        let middle = try await Self.averageColour(of: job.destination, at: length / 2)
        let last = try await Self.averageColour(of: job.destination, at: max(0, length - 0.02))

        // It starts on the leaving clip and ends on the arriving one.
        #expect(first.red > 0.8 && first.blue < 0.2, "\(kind.rawValue) starts on \(first)")
        // A dip to white blends in linear light: the last few percent of white still read brighter.
        let leftover = kind == .fadeWhite ? 0.5 : 0.3
        #expect(last.blue > 0.7 && last.red < leftover, "\(kind.rawValue) ends on \(last)")
        // Halfway it is neither: mixed, dipped, or split.
        let isRed = middle.red > 0.9 && middle.blue < 0.1
        let isBlue = middle.blue > 0.9 && middle.red < 0.1
        #expect(!isRed && !isBlue, "\(kind.rawValue) does not move: \(middle)")
        if kind == .fadeWhite {
            #expect(middle.green > 0.3, "fadeWhite halfway is \(middle)")
        }
        if kind == .fadeBlack {
            #expect(middle.red + middle.blue < 0.6, "fadeBlack halfway is \(middle)")
        }

        // Laid over its cut in the composition, and the composition plays.
        let assembled = try await VideoComposer().compose(project: project, mediaDirectory: folder, renderBackgrounds: false)
        #expect(assembled.composition.tracks(withMediaType: .video).count == 2)
        let cutColour = try await Self.averageColour(of: assembled, at: job.cut)
        let plainCutIsBlue = cutColour.blue > 0.9 && cutColour.red < 0.1
        #expect(!plainCutIsBlue, "\(kind.rawValue) is not shown over the cut: \(cutColour)")
        let afterColour = try await Self.averageColour(of: assembled, at: 3.5)
        #expect(afterColour.blue > 0.8 && afterColour.red < 0.2, "the clip after \(kind.rawValue) is \(afterColour)")
    }

    // MARK: - Helpers

    static func segment(_ recording: Recording) -> Segment {
        let take = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 2)),
            status: .ready
        )
        return Segment(role: .hook, script: "", takes: [take], selectedTakeID: take.id)
    }

    /// Two seconds of one colour, portrait.
    static func writeClip(named name: String, red: Double, green: Double, blue: Double, in folder: URL) async throws {
        let url = folder.appending(path: name, directoryHint: .notDirectory)
        let width = 270, height = 480
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let context = CIContext()
        let colour = CIImage(color: CIColor(red: red, green: green, blue: blue))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        for frame in 0..<60 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            let pool = try #require(adaptor.pixelBufferPool)
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            let pixels = try #require(buffer)
            context.render(colour, to: pixels)
            #expect(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }

    @concurrent
    static func averageColour(of assembled: VideoComposer.Assembled, at seconds: Double) async throws -> Colour {
        let generator = AVAssetImageGenerator(asset: assembled.composition)
        generator.videoComposition = assembled.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        return average(CIImage(cgImage: image))
    }

    @concurrent
    static func averageColour(of url: URL, at seconds: Double) async throws -> Colour {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        return average(CIImage(cgImage: image))
    }

    static func average(_ image: CIImage) -> Colour {
        let averaged = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            averaged,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return Colour(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }
}
