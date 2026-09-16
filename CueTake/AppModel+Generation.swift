import AVFoundation
import Domain
import EditorFeature
import Foundation
import GenerationEngine
import MediaEngine
import Persistence
import UIKit
import WorkflowsFeature

/// Making footage with video models, on the user's own keys.
extension AppModel {
    /// The workflow's "Generate video" step: one video per prompt, a few at a time, each laid in
    /// as a clip in prompt order. With no prompts, every section still waiting for footage is
    /// made from its own title and script.
    ///
    /// One failed video does not fail the rest: the step finishes with what was made and says how
    /// many did not come back, and why the first one failed.
    func generateVideos(_ options: GenerateVideoOptions, step: WorkflowStep.ID) async -> StudioStepState {
        let preset = options.modelPreset
        let provider = preset.provider
        guard !options.resolvedModel.isEmpty else {
            return .skipped(String(localized: "workflow.skip.noModel"))
        }
        guard let key = ProviderKeyStore().key(for: provider) else {
            return .skipped(String(localized: "workflow.skip.noKey \(provider.displayName)"))
        }

        let jobs = generationJobs(for: options)
        guard !jobs.isEmpty else { return .skipped(String(localized: "workflow.skip.noPrompts")) }

        let store = dependencies.projectStore
        try? await store.save(project)
        guard let media = try? await store.mediaDirectory(for: project.id) else {
            return .skipped(String(localized: "workflow.skip.exportFailed"))
        }
        let staging = media.appending(path: "generated", directoryHint: .isDirectory)
        let service = VideoGenerationService()
        let total = jobs.count
        var made: [Int: MediaImporter.ImportedClip] = [:]
        var firstError: String?

        // The studio shows a tile per video instead of covering the app while they are made.
        let board = GenerationBoard(
            stepID: step,
            modelTitle: preset.isCustom ? options.resolvedModel : preset.title,
            aspect: VideoModelPreset.ratio(preset.aspect(nearest: options.aspect)),
            prompts: jobs.map(\.prompt)
        )
        workflowStudio?.generation = board

        await withTaskGroup(of: (Int, MediaImporter.ImportedClip?, Data?, String?).self) { group in
            var next = 0
            // Returns the job it started; the board is told by the caller, on the main actor.
            func enqueue() -> Int? {
                guard next < jobs.count else { return nil }
                let index = next
                next += 1
                let request = VideoGenerationRequest.fitted(options, prompt: jobs[index].prompt)
                group.addTask {
                    do {
                        let file = try await service.generate(request, provider: provider, key: key, into: staging) { fraction in
                            Task { @MainActor in board.progress(index, fraction) }
                        }
                        defer { try? FileManager.default.removeItem(at: file) }
                        let clip = try await MediaImporter().importClip(from: file, into: media)
                        let thumbnail = await AppModel.thumbnail(of: file)
                        return (index, clip, thumbnail, nil)
                    } catch is CancellationError {
                        return (index, nil, nil, nil)
                    } catch {
                        if Task.isCancelled { return (index, nil, nil, nil) }
                        return (index, nil, nil, error.localizedDescription)
                    }
                }
                return index
            }
            for _ in 0..<min(max(options.parallel, 1), 6) {
                if let started = enqueue() { board.start(started) }
            }
            for await (index, clip, thumbnail, failure) in group {
                if let clip {
                    made[index] = clip
                    board.finish(index, thumbnail: thumbnail)
                } else {
                    board.fail(index, message: failure ?? String(localized: "workflow.skip.stopped"))
                }
                if firstError == nil, let failure { firstError = failure }
                // A stopped run starts nothing new.
                if !Task.isCancelled, let started = enqueue() { board.start(started) }
            }
        }
        if Task.isCancelled { board.cancelWaiting() }
        try? FileManager.default.removeItem(at: staging)

        layIn(made, for: jobs)

        if made.isEmpty {
            return .skipped(firstError.map { "\(provider.displayName): \($0)" } ?? String(localized: "workflow.skip.noVideos"))
        }
        if made.count < total {
            show(notice: String(localized: "workflow.generate.partial \(made.count) \(total) \(firstError ?? "")"))
        }
        return .done
    }

    /// The first frame, small, as JPEG.
    nonisolated static func thumbnail(of video: URL) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: 0.2, preferredTimescale: 600)) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.72)
    }

    // MARK: - In the editor

    /// Gives the editor its video generator and, when the model it would use has no key, moves it
    /// to the first model whose provider has one.
    func connectEditorGeneration() {
        let keys = ProviderKeyStore()
        editorModel.generationHasKey = { keys.hasKey(for: $0) }
        editorModel.clipGenerator = makeClipGenerator()
        let current = editorModel.generationDefaults.modelPreset
        if !keys.hasKey(for: current.provider),
           let usable = VideoModelPreset.catalog.first(where: { !$0.isCustom && keys.hasKey(for: $0.provider) }) {
            editorModel.generationDefaults.preset = usable.id
        }
    }

    private func makeClipGenerator() -> ClipGenerator {
        { [weak self] request, progress in
            guard let self else { throw CancellationError() }
            let preset = request.options.modelPreset
            guard let key = ProviderKeyStore().key(for: preset.provider) else {
                throw GenerationError.missingKey(preset.provider)
            }
            let store = self.dependencies.projectStore
            let projectID = self.editorModel.project.id
            guard let media = try? await store.mediaDirectory(for: projectID) else {
                throw GenerationError.failed(String(localized: "workflow.skip.exportFailed"))
            }
            let staging = media.appending(path: "generated", directoryHint: .isDirectory)
            let file = try await VideoGenerationService().generate(
                VideoGenerationRequest.fitted(request.options, prompt: request.prompt),
                provider: preset.provider,
                key: key,
                into: staging,
                progress: progress
            )
            defer { try? FileManager.default.removeItem(at: file) }
            let clip = try await MediaImporter().importClip(from: file, into: media)
            let thumbnail = await AppModel.thumbnail(of: file)
            return GeneratedClip(recording: clip.recording, take: clip.take, thumbnail: thumbnail)
        }
    }

    private struct GenerationJob {
        var prompt: String
        /// The planned section this video fills, when it was made from one.
        var segment: Segment.ID?
    }

    private func generationJobs(for options: GenerateVideoOptions) -> [GenerationJob] {
        if !options.prompts.isEmpty {
            return options.prompts.map { GenerationJob(prompt: $0, segment: nil) }
        }
        return project.segments.compactMap { segment in
            guard segment.selectedTake == nil else { return nil }
            let text = [segment.title, segment.script]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ". ")
            return text.isEmpty ? nil : GenerationJob(prompt: text, segment: segment.id)
        }
    }

    /// Adds the made videos in the order they were asked for.
    private func layIn(_ made: [Int: MediaImporter.ImportedClip], for jobs: [GenerationJob]) {
        guard !made.isEmpty else { return }
        for index in jobs.indices {
            guard let clip = made[index] else { continue }
            project.recordings.append(clip.recording)
            if let id = jobs[index].segment,
               let segment = project.segments.firstIndex(where: { $0.id == id }) {
                project.segments[segment].takes.append(clip.take)
                project.segments[segment].selectedTakeID = clip.take.id
                project.segments[segment].estimatedDuration = clip.take.duration
            } else {
                project.segments.append(
                    Segment(
                        role: .custom("\(project.segments.count + 1)"),
                        title: String(jobs[index].prompt.prefix(48)),
                        script: "",
                        estimatedDuration: clip.take.duration,
                        takes: [clip.take],
                        selectedTakeID: clip.take.id,
                        metadata: ["generatedBy": "video-model"]
                    )
                )
            }
        }
        project.updatedAt = .now
        editorModel.project = project
    }
}
