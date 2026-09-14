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
    /// What the preview knows about the processed copies: which exist, which are still to come.
    var backgroundSignature: String {
        guard let mediaDirectory else { return "" }
        return BackgroundRemover.jobs(for: project, in: mediaDirectory)
            .map { "\($0.name):\(readyBackgrounds.contains($0.name) ? "ready" : "pending")" }
            .joined(separator: ",")
    }

    /// Whether a processed copy with this look is being rendered right now.
    func isRenderingBackground(_ settings: BackgroundSettings) -> Bool {
        backgroundJob != nil && backgroundJobKey.contains("-bg-" + settings.token + ".mov")
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

        var pending: [BackgroundRemover.Job] = []
        for job in BackgroundRemover.jobs(for: project, in: mediaDirectory) {
            guard !failedBackgrounds.contains(job.name) else { continue }
            if FileManager.default.fileExists(atPath: job.destination.path(percentEncoded: false)) {
                if !readyBackgrounds.contains(job.name) { readyBackgrounds.insert(job.name) }
                continue
            }
            // A reversed clip's background is taken from its reversed copy, which the preview
            // build writes first; until it exists there is nothing to process.
            guard !job.waitsForReverse else { continue }
            pending.append(job)
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
            for (index, job) in work.enumerated() {
                guard !Task.isCancelled else { return }
                let done = Double(index)
                let url = await BackgroundRemover().render(
                    source: job.source,
                    range: job.range,
                    settings: job.settings,
                    destination: job.destination
                ) { [weak model] value in
                    Task { @MainActor in
                        guard let model, model.backgroundJobKey == key else { return }
                        model.backgroundProgress = (done + value) / count
                    }
                }
                guard !Task.isCancelled else { return }
                if url != nil {
                    model.readyBackgrounds.insert(job.name)
                } else {
                    model.failedBackgrounds.insert(job.name)
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
