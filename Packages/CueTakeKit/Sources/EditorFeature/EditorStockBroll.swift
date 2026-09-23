import DesignSystem
import Domain
import Foundation

/// A stock shot fetched and imported, ready to lay over the speaker.
public struct StockBroll: Sendable {
    public var clip: GeneratedClip
    /// What it shows, in the search's words: its title on the timeline.
    public var title: String
    public var at: Double
    public var seconds: Double

    public init(clip: GeneratedClip, title: String, at: Double, seconds: Double) {
        self.clip = clip
        self.title = title
        self.at = at
        self.seconds = seconds
    }
}

/// B-roll from a stock library: the app finds and imports the shots, the editor lays them over the
/// speaker, muted, each for the moment it illustrates. One undo step for all of them.
extension EditorModel {
    public var canFindStockBroll: Bool {
        stockBrollFinder != nil && project.segments.contains { $0.selectedTake?.transcript?.words.isEmpty == false }
    }

    @discardableResult
    public func addStockBroll(count: Int) async -> Int {
        guard let stockBrollFinder, brollSearching == false else { return 0 }
        brollSearching = true
        brollFailure = nil
        defer { brollSearching = false }
        do {
            let shots = try await stockBrollFinder(count)
            guard !shots.isEmpty else {
                brollFailure = AppLocalization.string("broll.none", bundle: .module)
                return 0
            }
            record("editor.change.broll", symbol: "photo.stack")
            var laid = 0
            for shot in shots.sorted(by: { $0.at < $1.at }) {
                guard project.videoLayers.count < VideoLayer.maximumAdditionalLayers else { break }
                project.recordings.append(shot.clip.recording)
                let start = min(max(0, shot.at), max(0, duration - 0.5))
                let length = min(shot.seconds, shot.clip.take.duration.seconds, max(0.5, duration - start))
                var layer = VideoLayer(
                    recordingID: shot.clip.recording.id,
                    title: shot.title,
                    start: MediaTime(seconds: start),
                    sourceRange: MediaTimeRange(start: shot.clip.take.sourceRange.start, duration: MediaTime(seconds: length)),
                    placement: VideoPlacement(fillsFrame: true)
                )
                layer.isMuted = true
                project.videoLayers.append(layer)
                laid += 1
            }
            project.updatedAt = .now
            return laid
        } catch {
            brollFailure = (error as? LocalizedError)?.errorDescription ?? AppLocalization.string("broll.failed", bundle: .module)
            return 0
        }
    }
}
