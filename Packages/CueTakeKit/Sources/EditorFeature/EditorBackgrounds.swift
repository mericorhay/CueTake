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

extension EditorModel {
    /// Writes the transition films the edit needs, below everything else, and shows them as they
    /// arrive. Until then the preview plays those cuts as cuts.
    ///
    /// The cut nearest the playhead is drawn first, and finished films are shown a few at a time:
    /// a preview rebuilt after every one of fifty would never stop blinking.
    func prepareTransitions() {
        guard let mediaDirectory else { return }
        let jobs = TransitionRenderer.jobs(for: project, in: mediaDirectory)
        let ready = Set(jobs.filter(\.isReady).map(\.name))
        if !ready.isSubset(of: readyTransitions) {
            readyTransitions.formUnion(ready)
        }
        let missing = jobs.filter { !ready.contains($0.name) }
        let key = missing.map(\.name).joined(separator: ",")
        guard !missing.isEmpty else {
            transitionJob?.cancel()
            transitionJob = nil
            transitionJobKey = ""
            return
        }
        guard key != transitionJobKey || transitionJob == nil else { return }
        transitionJob?.cancel()
        transitionJobKey = key
        let snapshot = project
        let nearest = playhead
        let inbox = TransitionInbox()
        transitionJob = Task(priority: .utility) { [weak self] in
            // A moment's wait: a duration slider sends many values, and only the last is drawn.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let flusher = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard let self, self.transitionJobKey == key else { return }
                    self.showTransitions(inbox.take())
                }
            }
            await TransitionRenderer.renderMissing(
                for: snapshot,
                in: mediaDirectory,
                renderBackgrounds: false,
                nearest: nearest,
                onFilm: { inbox.add($0) }
            )
            flusher.cancel()
            guard !Task.isCancelled, let self, self.transitionJobKey == key else { return }
            self.transitionJob = nil
            self.transitionJobKey = ""
            self.showTransitions(inbox.take())
        }
    }

    private func showTransitions(_ names: [String]) {
        let fresh = Set(names).subtracting(readyTransitions)
        guard !fresh.isEmpty else { return }
        readyTransitions.formUnion(fresh)
    }
}

/// Film names handed from the renderer to the editor, collected until the editor looks.
private nonisolated final class TransitionInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    func add(_ name: String) {
        lock.withLock { names.append(name) }
    }

    func take() -> [String] {
        lock.withLock {
            defer { names.removeAll() }
            return names
        }
    }
}
