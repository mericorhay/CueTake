import AVFoundation
import Domain
import Foundation
import MediaEngine

/// Replacing backgrounds without holding up the preview.
///
/// The preview plays a clip as shot until its processed copy exists; the render runs here, one clip
/// after another, with progress, and when a copy is ready the preview is rebuilt to use it. It used
/// to run inside the preview build, where a render that stalled left the picture black for good.
extension EditorModel {
    /// The file a clip's background replacement is written to, or nil when it has none.
    func backgroundCacheName(for segment: Segment) -> String? {
        guard let background = segment.background, let take = segment.selectedTake else { return nil }
        let reversed = segment.playback.isReversed && segment.playback.freeze == nil
        return BackgroundRemover.cacheName(take: take, reversed: reversed, background: background)
    }

    /// Says on the picture, for a few seconds, that a clip keeps its own background.
    func showBackgroundFailure() {
        backgroundFailed = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.backgroundFailed = false
        }
    }

    /// Renders every missing background replacement, unless the same set is already under way.
    func prepareBackgrounds() {
        guard let mediaDirectory else { return }

        var pending: [(name: String, source: URL, range: CMTimeRange, background: ClipBackground, destination: URL)] = []
        for segment in project.segments {
            guard let name = backgroundCacheName(for: segment),
                  let background = segment.background,
                  let take = segment.selectedTake,
                  let recording = project.recordings.first(where: { $0.id == take.recordingID })
            else { continue }
            guard !failedBackgrounds.contains(name) else { continue }
            let destination = mediaDirectory.appending(path: name, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                readyBackgrounds.insert(name)
                continue
            }

            let length = CMTime(seconds: take.sourceRange.duration.seconds, preferredTimescale: 600)
            if segment.playback.isReversed, segment.playback.freeze == nil {
                // A reversed clip's background is taken from its reversed copy, which the preview
                // build writes first; until it exists there is nothing to process.
                let key = "\(take.id.uuidString)-\(Int(take.sourceRange.start.seconds * 1000))-\(Int(take.sourceRange.duration.seconds * 1000))"
                let reversed = mediaDirectory.appending(path: "\(key)-rev.mov", directoryHint: .notDirectory)
                guard FileManager.default.fileExists(atPath: reversed.path(percentEncoded: false)) else { continue }
                pending.append((name, reversed, CMTimeRange(start: .zero, duration: length), background, destination))
            } else {
                let source = mediaDirectory.appending(
                    path: (recording.relativePath as NSString).lastPathComponent,
                    directoryHint: .notDirectory
                )
                let start = CMTime(seconds: take.sourceRange.start.seconds, preferredTimescale: 600)
                pending.append((name, source, CMTimeRange(start: start, duration: length), background, destination))
            }
        }

        let key = pending.map(\.name).joined(separator: ",")
        guard !pending.isEmpty else {
            backgroundJob?.cancel()
            backgroundJob = nil
            backgroundJobKey = ""
            backgroundProgress = nil
            return
        }
        guard key != backgroundJobKey || backgroundJob == nil else { return }

        backgroundJob?.cancel()
        backgroundJobKey = key
        backgroundProgress = 0
        let work = pending
        // Below the preview and the interface: the render gives way to them, never the reverse.
        backgroundJob = Task(priority: .utility) { [weak self] in
            guard let model = self else { return }
            let count = Double(work.count)
            for (index, item) in work.enumerated() {
                guard !Task.isCancelled else { return }
                let done = Double(index)
                let url = await BackgroundRemover().render(
                    source: item.source,
                    range: item.range,
                    background: item.background,
                    destination: item.destination
                ) { [weak model] value in
                    Task { @MainActor in
                        guard let model, model.backgroundJobKey == key else { return }
                        model.backgroundProgress = (done + value) / count
                    }
                }
                guard !Task.isCancelled else { return }
                if url != nil {
                    model.readyBackgrounds.insert(item.name)
                } else {
                    model.failedBackgrounds.insert(item.name)
                    model.showBackgroundFailure()
                }
            }
            guard model.backgroundJobKey == key else { return }
            model.backgroundProgress = nil
            model.backgroundJob = nil
            model.backgroundJobKey = ""
            if model.recoverAfterBackgrounds, let directory = model.mediaDirectory {
                model.recoverAfterBackgrounds = false
                await model.loadPlayback(mediaDirectory: directory)
            }
        }
    }
}
