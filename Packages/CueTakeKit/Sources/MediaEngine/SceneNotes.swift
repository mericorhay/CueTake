import AVFoundation
import Foundation
import Vision

/// What a stretch of footage shows, in a few words, for the AI editor to read.
///
/// The model that edits reads words and times; without this it has never seen the video, and the
/// titles it writes are about nothing in particular. A few frames are looked at on the phone:
/// what kind of scene it is, how many faces, and any writing in the picture (a product name, a
/// sign, a price). Nothing leaves the phone but the resulting line of text.
public enum SceneNotes {
    /// A short line such as `faces 1; scene: kitchen, food, indoor; text: "SALE 50%"`, or nil when
    /// nothing could be read.
    @concurrent public static func describe(_ url: URL, from start: Double, duration: Double) async -> String? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let length = max(0.1, duration)
        let moments = duration < 3 ? [0.5] : [0.15, 0.5, 0.85]
        var frames: [CGImage] = []
        for fraction in moments {
            let time = CMTime(seconds: start + length * fraction, preferredTimescale: 600)
            if let result = try? await generator.image(at: time) { frames.append(result.image) }
        }
        guard !frames.isEmpty else { return nil }
        return read(frames)
    }

    private static func read(_ frames: [CGImage]) -> String? {
        var labels: [String: Float] = [:]
        var faces = 0
        var writing: [String] = []

        for frame in frames {
            let classify = VNClassifyImageRequest()
            let faceRequest = VNDetectFaceRectanglesRequest()
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .fast
            text.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: frame, options: [:])
            try? handler.perform([classify, faceRequest, text])

            for observation in classify.results ?? [] where observation.confidence > 0.3 {
                labels[observation.identifier] = max(labels[observation.identifier] ?? 0, observation.confidence)
            }
            faces = max(faces, faceRequest.results?.count ?? 0)
            for observation in text.results ?? [] {
                guard let best = observation.topCandidates(1).first, best.confidence > 0.5 else { continue }
                let line = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.count >= 3, !writing.contains(line) { writing.append(line) }
            }
        }

        var parts: [String] = []
        if faces > 0 { parts.append("faces \(faces)") }
        let scene = labels
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { $0.key.replacingOccurrences(of: "_", with: " ") }
        if !scene.isEmpty { parts.append("scene: " + scene.joined(separator: ", ")) }
        let shown = writing.joined(separator: " / ")
        if !shown.isEmpty { parts.append("text: \"" + String(shown.prefix(80)) + "\"") }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }
}
