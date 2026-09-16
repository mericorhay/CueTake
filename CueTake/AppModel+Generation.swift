import Domain
import EditorFeature
import Foundation
import GenerationEngine
import MediaEngine
import Persistence
import WorkflowsFeature

/// Making footage with video models, on the user's own keys.
extension AppModel {
    /// The workflow's "Generate video" step: one video per prompt, a few at a time, each laid in
    /// as a clip in prompt order. With no prompts, every section still waiting for footage is
    /// made from its own title and script.
    ///
    /// One failed video does not fail the rest: the step finishes with what was made and says how
    /// many did not come back, and why the first one failed.
    func generateVideos(_ options: GenerateVideoOptions) async -> StudioStepState {
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

        busy = String(localized: "workflow.generating \(0) \(total) \(preset.title)")
        await withTaskGroup(of: (Int, MediaImporter.ImportedClip?, String?).self) { group in
            var next = 0
            func enqueue() {
                guard next < jobs.count else { return }
                let index = next
                next += 1
                let request = VideoGenerationRequest.fitted(options, prompt: jobs[index].prompt)
                group.addTask {
                    do {
                        let file = try await service.generate(request, provider: provider, key: key, into: staging)
                        defer { try? FileManager.default.removeItem(at: file) }
                        let clip = try await MediaImporter().importClip(from: file, into: media)
                        return (index, clip, nil)
                    } catch is CancellationError {
                        return (index, nil, nil)
                    } catch {
                        return (index, nil, error.localizedDescription)
                    }
                }
            }
            for _ in 0..<min(max(options.parallel, 1), 6) { enqueue() }
            var finished = 0
            for await (index, clip, failure) in group {
                finished += 1
                if let clip { made[index] = clip }
                if firstError == nil, let failure { firstError = failure }
                busy = String(localized: "workflow.generating \(finished) \(total) \(preset.title)")
                enqueue()
            }
        }
        busy = nil
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
