import DesignSystem
import Domain
import Foundation
import SwiftUI
import UIKit

/// What the editor asks the app for: one video, from one prompt.
public struct ClipGenerationRequest: Sendable {
    public var options: GenerateVideoOptions
    public var prompt: String

    public init(options: GenerateVideoOptions, prompt: String) {
        self.options = options
        self.prompt = prompt
    }
}

/// A made video, already copied into the project's media.
public struct GeneratedClip: Sendable {
    public var recording: Recording
    public var take: Take
    /// The first frame as JPEG, for the panel.
    public var thumbnail: Data?

    public init(recording: Recording, take: Take, thumbnail: Data?) {
        self.recording = recording
        self.take = take
        self.thumbnail = thumbnail
    }
}

/// Makes a video with the user's own key. Supplied by the app, which owns keys and storage; nil
/// in a build or a state where generating is not possible.
public typealias ClipGenerator = @MainActor (
    ClipGenerationRequest,
    _ progress: @escaping @Sendable (Double?) -> Void
) async throws -> GeneratedClip

/// Where a generated video goes.
public enum GenerationPlacement: String, Hashable, Sendable, CaseIterable {
    /// Over the main video at the moment, muted: B-roll while the voice carries on.
    case broll
    /// A clip of its own, after the clip at the moment.
    case clip
}

/// One video being made from the editor.
public struct ClipGenerationJob: Identifiable {
    public enum Phase: Hashable {
        case working, done, failed
    }

    public let id: UUID
    public var prompt: String
    public var options: GenerateVideoOptions
    public var placement: GenerationPlacement
    /// The moment of the finished video it goes to.
    public var at: Double
    public var phase: Phase = .working
    public var started: Date = .now
    public var progress: Double?
    public var failure: String?
    public var thumbnail: UIImage?

    /// Seconds it will last, as the model will make it.
    public var seconds: Double { options.modelPreset.duration(nearest: options.seconds) }
}

// MARK: - The queue

extension EditorModel {
    public var canGenerate: Bool { clipGenerator != nil }

    /// The video settings, fitted to this project's shape.
    public func fittedGenerationOptions(_ options: GenerateVideoOptions) -> GenerateVideoOptions {
        var fitted = options
        let size = project.format.renderSize
        let wanted = size.width < size.height ? "9:16" : (size.width == size.height ? "1:1" : "16:9")
        fitted.aspect = fitted.modelPreset.aspect(nearest: wanted)
        fitted.seconds = fitted.modelPreset.duration(nearest: fitted.seconds)
        fitted.resolution = fitted.modelPreset.resolution(nearest: fitted.resolution)
        return fitted
    }

    /// Starts a video in the background. The editor stays free; the timeline shows where it will
    /// land, and it lays itself in when it arrives.
    @discardableResult
    public func generateClip(
        prompt: String,
        options: GenerateVideoOptions? = nil,
        placement: GenerationPlacement? = nil,
        at time: Double? = nil
    ) -> UUID? {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canGenerate, !text.isEmpty else { return nil }
        let job = ClipGenerationJob(
            id: UUID(),
            prompt: text,
            options: fittedGenerationOptions(options ?? generationDefaults),
            placement: placement ?? generationPlacement,
            at: min(max(time ?? playhead, 0), max(duration, 0))
        )
        generationJobs.append(job)
        run(job.id)
        return job.id
    }

    private func run(_ id: UUID) {
        guard let generator = clipGenerator,
              let job = generationJobs.first(where: { $0.id == id })
        else { return }
        let request = ClipGenerationRequest(options: job.options, prompt: job.prompt)
        let sink = GenerationProgressSink(model: self, job: id)
        generationTasks[id] = Task { [weak self] in
            do {
                let clip = try await generator(request) { fraction in
                    Task { await sink.report(fraction) }
                }
                self?.arrive(clip, for: id)
            } catch is CancellationError {
                self?.dropJob(id)
            } catch {
                guard let self else { return }
                if Task.isCancelled { self.dropJob(id); return }
                self.updateJob(id) {
                    $0.phase = .failed
                    $0.failure = error.localizedDescription
                }
            }
            self?.generationTasks[id] = nil
        }
    }

    public func cancelGeneration(_ id: UUID) {
        generationTasks[id]?.cancel()
        dropJob(id)
    }

    public func retryGeneration(_ id: UUID) {
        updateJob(id) {
            $0.phase = .working
            $0.failure = nil
            $0.progress = nil
            $0.started = .now
        }
        run(id)
    }

    public func dismissGeneration(_ id: UUID) {
        dropJob(id)
    }

    func updateJob(_ id: UUID, _ change: (inout ClipGenerationJob) -> Void) {
        guard let index = generationJobs.firstIndex(where: { $0.id == id }) else { return }
        change(&generationJobs[index])
    }

    private func dropJob(_ id: UUID) {
        generationJobs.removeAll { $0.id == id }
    }

    private func arrive(_ clip: GeneratedClip, for id: UUID) {
        guard let job = generationJobs.first(where: { $0.id == id }) else { return }
        guard let target = layInGenerated(clip, prompt: job.prompt, at: job.at, placement: job.placement, recordingEdit: true) else {
            updateJob(id) {
                $0.phase = .failed
                $0.failure = String(localized: "editor.generate.noRoom", bundle: .module)
            }
            return
        }
        updateJob(id) {
            $0.phase = .done
            $0.progress = 1
            $0.thumbnail = clip.thumbnail.flatMap(UIImage.init(data:))
        }
        aiBeat += 1
        glow([target])
        // The finished tile stays a moment so the arrival is seen, then clears itself.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(DS.Motion.settle) { self?.dropJob(id) }
        }
    }

    /// Puts a made video into the project. Returns what it touched, or nil when there was no room.
    @discardableResult
    func layInGenerated(
        _ clip: GeneratedClip,
        prompt: String,
        at time: Double,
        placement: GenerationPlacement,
        recordingEdit: Bool
    ) -> AITarget? {
        let title = String(prompt.prefix(40))
        switch placement {
        case .broll:
            guard project.videoLayers.count < VideoLayer.maximumAdditionalLayers else { return nil }
            if recordingEdit { record("editor.change.generated", symbol: "wand.and.stars") }
            project.recordings.append(clip.recording)
            let start = min(max(0, time), max(0, duration - 0.2))
            // Never past the end of the video it covers.
            let length = min(clip.take.duration.seconds, max(0.2, duration - start))
            var layer = VideoLayer(
                recordingID: clip.recording.id,
                title: title,
                start: MediaTime(seconds: start),
                sourceRange: MediaTimeRange(start: clip.take.sourceRange.start, duration: MediaTime(seconds: length)),
                placement: VideoPlacement(fillsFrame: true)
            )
            // B-roll shows while the speaker keeps talking.
            layer.isMuted = true
            project.videoLayers.append(layer)
            project.updatedAt = .now
            return .videoLayer(layer.id)

        case .clip:
            if recordingEdit { record("editor.change.generated", symbol: "wand.and.stars") }
            project.recordings.append(clip.recording)
            var position = project.segments.count
            var running = 0.0
            for (index, segment) in project.segments.enumerated() {
                running += segment.barWeight
                if time < running - 0.001 {
                    position = index + 1
                    break
                }
            }
            let segment = Segment(
                role: .custom("AI"),
                title: title,
                script: "",
                estimatedDuration: clip.take.duration,
                takes: [clip.take],
                selectedTakeID: clip.take.id,
                metadata: ["generatedBy": "video-model"]
            )
            project.segments.insert(segment, at: min(position, project.segments.count))
            project.updatedAt = .now
            return .clip(segment.id)
        }
    }
}

/// A video found before an AI step lays it in.
final class AIGeneratedClipBox {
    var clip: GeneratedClip?
}

extension EditorModel {
    /// The model the AI would use, or nil when generating is not possible.
    var aiVideoModel: String? {
        guard canGenerate else { return nil }
        let preset = generationDefaults.modelPreset
        guard generationHasKey(preset.provider), !generationDefaults.resolvedModel.isEmpty else { return nil }
        return preset.isCustom ? generationDefaults.resolvedModel : preset.id
    }

    /// Makes the AI's video now, with a placeholder on the timeline while it is made.
    func aiGenerate(_ request: GenerateClipRequest) async -> GeneratedClip? {
        guard let generator = clipGenerator else { return nil }
        var options = generationDefaults
        if let model = request.model, VideoModelPreset.catalog.contains(where: { $0.id == model && !$0.isCustom }),
           generationHasKey(VideoModelPreset.preset(id: model).provider) {
            options.preset = model
        }
        if let seconds = request.seconds { options.seconds = seconds }
        options = fittedGenerationOptions(options)

        let job = ClipGenerationJob(
            id: UUID(),
            prompt: request.prompt,
            options: options,
            placement: request.asClip ? .clip : .broll,
            at: min(max(request.at ?? playhead, 0), max(duration, 0))
        )
        withAnimation(DS.Motion.settle) { generationJobs.append(job) }
        defer { withAnimation(DS.Motion.settle) { generationJobs.removeAll { $0.id == job.id } } }
        let sink = GenerationProgressSink(model: self, job: job.id)
        return try? await generator(ClipGenerationRequest(options: options, prompt: request.prompt)) { fraction in
            Task { await sink.report(fraction) }
        }
    }
}

/// Carries progress from the network back to the editor without holding the editor.
@MainActor
final class GenerationProgressSink {
    private weak var model: EditorModel?
    private let job: UUID

    init(model: EditorModel, job: UUID) {
        self.model = model
        self.job = job
    }

    func report(_ fraction: Double?) {
        guard let fraction else { return }
        model?.updateJob(job) { $0.progress = fraction }
    }
}
