import AIServices
import DesignSystem
import Domain
import EditorFeature
import Foundation
import Persistence
import SettingsFeature
import SwiftUI
import WorkflowEngine
import WorkflowsFeature

/// Opening, saving, writing with AI and running workflows.
///
/// The run lives here rather than in `WorkflowEngine` because every useful step is an edit the
/// editor already knows how to make — trimming pauses, cutting words, changing speed — and the
/// editor model is what makes those edits undoable. Running a workflow is therefore exactly what
/// doing the same edits by hand would be, including the changes list afterwards; the engine's
/// handler protocol would have had to reimplement the editor to stay independent of it.
extension AppModel {
    // MARK: - Library

    func loadWorkflows() async {
        // Any `.running` record belongs to a process that no longer exists. Recovery only moves
        // its durable cursor back to the queue; no media work starts behind the user's back.
        _ = try? await dependencies.workflowJobQueue?.recoverInterrupted()
        guard let store = dependencies.workflowStore else {
            if workflows.isEmpty { workflows = WorkflowDefinition.builtIns }
            return
        }
        workflows = await store.all()
    }

    func openWorkflow(_ workflow: WorkflowDefinition) {
        let studio = WorkflowStudioModel(definition: workflow, clips: currentClips())
        workflowStudio = studio
        go(to: .workflowDetail)
        let projectID = project.id
        Task { [weak self, weak studio] in
            guard let queue = self?.dependencies.workflowJobQueue,
                  let pending = await queue.resumable(workflowID: workflow.id, projectID: projectID),
                  pending.state.definition.updatedAt == workflow.updatedAt
            else { return }
            studio?.setResumableProgress(pending.progress)
        }
    }

    /// A new workflow with a sensible starting shape, rather than an empty page. Three sections
    /// and the four tools almost everyone wants is easier to edit into something than nothing is.
    func createWorkflow() {
        let workflow = WorkflowDefinition(
            name: AppLocalization.string("workflow.new.name"),
            sections: [
                WorkflowSection(role: "hook", title: "Hook", seconds: 3),
                WorkflowSection(role: "point", title: "Point", seconds: 12),
                WorkflowSection(role: "cta", title: "CTA", seconds: 4),
            ],
            steps: [
                WorkflowStep(kind: .assembleSections),
                WorkflowStep(kind: .analyzeSpeech),
                WorkflowStep(kind: .trimSilences(TrimSilencesOptions())),
                WorkflowStep(kind: .generateCaptions),
            ]
        )
        openWorkflow(workflow)
        saveWorkflow()
    }

    func closeWorkflow() {
        flushWorkflowSave()
        go(to: .workflows)
        workflowStudio = nil
    }

    /// Debounced: typing a section title should not write the file forty times.
    func saveWorkflow() {
        guard let definition = workflowStudio?.definition else { return }
        if let index = workflows.firstIndex(where: { $0.id == definition.id }) {
            workflows[index] = definition
        } else {
            workflows.insert(definition, at: 0)
        }

        workflowSaveTask?.cancel()
        let store = dependencies.workflowStore
        workflowSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            try? await store?.save(definition)
        }
    }

    func flushWorkflowSave() {
        guard let definition = workflowStudio?.definition else { return }
        workflowSaveTask?.cancel()
        let store = dependencies.workflowStore
        Task { try? await store?.save(definition) }
    }

    /// Removes a workflow from the list, without opening it first.
    func deleteWorkflow(id: WorkflowDefinition.ID) async {
        await dependencies.workflowStore?.delete(id: id)
        withAnimation(DS.Motion.settle) {
            workflows.removeAll { $0.id == id }
        }
    }

    /// A copy to change without touching the original.
    func duplicateWorkflow(_ workflow: WorkflowDefinition) async {
        guard var copy = try? WorkflowDefinition.decode(json: (try? workflow.jsonString()) ?? "") else { return }
        // Decoding without an id gives a fresh one; the copy is named as a copy.
        copy = WorkflowDefinition(
            name: workflow.name + " " + AppLocalization.string("workflow.copySuffix"),
            summary: copy.summary,
            origin: .user,
            sections: copy.sections,
            style: copy.style,
            variables: copy.variables,
            steps: copy.steps
        )
        try? await dependencies.workflowStore?.save(copy)
        withAnimation(DS.Motion.settle) {
            workflows.insert(copy, at: 0)
        }
    }

    /// Writes a workflow from a sentence and opens it in the studio. Returns a message when it
    /// could not, for the sheet to show.
    func createWorkflowWithAI(_ description: String) async -> String? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var written: WorkflowDefinition?
        var failure: (any Error)?
        if settingsModel.settings.aiProcessing == .allowCloud,
           dependencies.assistantClient.isConfigured {
            do {
                written = try await dependencies.assistantClient.workflow(
                    from: text,
                    clipCount: currentClips().count,
                    localeIdentifier: project.localeIdentifier
                )
            } catch {
                failure = error
            }
        }
        if written == nil, dependencies.workflowAuthor.isAvailable {
            written = try? await dependencies.workflowAuthor.author(request: text, current: nil, clipCount: currentClips().count)
        }
        guard let written else {
            return failure.map { Self.assistantFailureMessage($0) } ?? AppLocalization.string("workflow.ai.failed")
        }

        try? await dependencies.workflowStore?.save(written)
        workflows.removeAll { $0.id == written.id }
        workflows.insert(written, at: 0)
        openWorkflow(written)
        return nil
    }

    func deleteWorkflow() async {
        guard let id = workflowStudio?.definition.id else { return }
        workflowSaveTask?.cancel()
        await dependencies.workflowStore?.delete(id: id)
        workflows.removeAll { $0.id == id }
        go(to: .workflows)
        workflowStudio = nil
    }

    // MARK: - Clips

    /// The open project's footage, as numbered clips.
    ///
    /// Named after the segment that first used the recording, because that is the name the import
    /// gave it — the file's own name — and a raw UUID on a chip means nothing to anybody.
    func currentClips() -> [StudioClip] {
        project.recordings.enumerated().map { index, recording in
            let title = project.segments
                .first { $0.takes.contains { $0.recordingID == recording.id } }?
                .title
            return StudioClip(
                slot: index + 1,
                name: (title?.isEmpty == false ? title : nil)
                    ?? AppLocalization.string("workflow.clip \(index + 1)"),
                seconds: recording.duration.seconds
            )
        }
    }

    func refreshWorkflowClips() {
        workflowStudio?.clips = currentClips()
    }

    func pickClipsForWorkflow() {
        importReturnsToWorkflow = true
        isPickingFootage = true
    }

    // MARK: - AI

    func askWorkflowAI() async {
        guard let studio = workflowStudio else { return }
        let request = studio.aiRequest
        studio.beginAuthoring()

        // An empty workflow is a request for a new one; anything else is a request to change it.
        let current = studio.definition.sections.isEmpty && studio.definition.steps.isEmpty
            ? nil
            : studio.definition

        // The server model first: it writes far better workflows than the on-device one. The
        // on-device model stays as the way it works offline or in a build without the assistant.
        if settingsModel.settings.aiProcessing == .allowCloud,
           dependencies.assistantClient.isConfigured {
            let description = current.map {
                "Change this workflow as requested and return the whole workflow.\nCurrent: \((try? $0.jsonString()) ?? "")\nRequest: \(request)"
            } ?? request
            if let written = try? await dependencies.assistantClient.workflow(
                from: description,
                clipCount: studio.clips.count,
                localeIdentifier: project.localeIdentifier
            ) {
                studio.finishAuthoring(with: written)
                if let current, current.id != written.id {
                    workflows.removeAll { $0.id == current.id }
                    await dependencies.workflowStore?.delete(id: current.id)
                }
                saveWorkflow()
                return
            }
        }

        let author = dependencies.workflowAuthor
        guard author.isAvailable else {
            studio.finishAuthoring(with: nil)
            return
        }

        let written = try? await author.author(
            request: request,
            current: current,
            clipCount: studio.clips.count
        )
        studio.finishAuthoring(with: written)
        if written != nil { saveWorkflow() }
    }

    // MARK: - Run

    /// Runs the workflow against the open project, step by step, where the user can watch it.
    ///
    /// A short pause between steps is deliberate. The work itself is often instant, and a pipeline
    /// that finishes before the first card has lit up tells the user nothing about what happened
    /// to their video — the rail filling one step at a time is the report.
    func startWorkflowRun() {
        guard workflowRunTask == nil else { return }
        workflowRunTask = Task { [weak self] in
            await self?.runWorkflow()
            self?.workflowRunTask = nil
        }
    }

    /// Stops after the step under way lets go: generation requests are cancelled, nothing
    /// half-made is laid in, and every step not reached is marked as stopped.
    func stopWorkflowRun() {
        workflowRunTask?.cancel()
    }

    func runWorkflow() async {
        guard let studio = workflowStudio, !studio.isRunning else { return }
        var definition = studio.definition
        let queue = dependencies.workflowJobQueue
        var job: WorkflowJob?

        if let queue {
            if let pending = await queue.resumable(workflowID: definition.id, projectID: project.id),
               pending.state.definition.updatedAt == definition.updatedAt {
                job = try? await queue.start(pending.id)
                definition = pending.state.definition
            } else {
                if let stale = await queue.resumable(workflowID: definition.id, projectID: project.id) {
                    try? await queue.cancel(stale.id)
                }
                let queued = try? await queue.enqueue(
                    workflow: definition,
                    projectID: project.id,
                    variables: workflowRuntimeVariables()
                )
                if let queued { job = try? await queue.start(queued.id) }
            }
        }

        var state = job?.state ?? WorkflowRunState(
            definition: definition,
            variables: definition.variables.merging(workflowRuntimeVariables()) { _, runtime in runtime }
        )
        // Runtime facts may have changed while a recovered job was waiting. User-authored values
        // stay intact; facts owned by the open project are refreshed.
        state.variables.merge(workflowRuntimeVariables()) { _, runtime in runtime }
        studio.beginRun(resumingAt: state.nextStepIndex)

        // The whole run is one edit the editor can undo: assembling sections replaces the clips,
        // and a workflow run on a project someone had already edited used to lose that work.
        if screen == .editor { adoptEditorEdits() }
        let before = project
        editorModel.project = project
        editorModel.beginBatch()
        workflowDeliveryResult = nil
        workflowVideo = nil

        // The style's size and frame rate are what the run writes; the closing export shows them.
        project.format = definition.style.format
        project.updatedAt = .now

        var wasPaused = false
        while let step = state.nextStep {
            if Task.isCancelled {
                studio.mark(step.id, .skipped(AppLocalization.string("workflow.skip.stopped")))
                if let queue, let job { try? await queue.pause(job.id, state: state) }
                wasPaused = true
                break
            }
            guard step.isEnabled else {
                studio.mark(step.id, .skipped(AppLocalization.string("workflow.skip.disabled")))
                state = state.advanced()
                if let queue, let job {
                    _ = try? await queue.checkpoint(job.id, state: state, kind: .stepSkipped, step: step, message: "disabled")
                }
                continue
            }

            if let condition = step.when, !condition.evaluate(in: state.variables) {
                studio.mark(step.id, .skipped(AppLocalization.string("workflow.skip.condition")))
                state = state.advanced()
                if let queue, let job {
                    _ = try? await queue.checkpoint(job.id, state: state, kind: .stepSkipped, step: step, message: "conditionFalse")
                }
                continue
            }

            let items: [WorkflowValue?]
            if let loop = step.forEach {
                items = (state.variables[loop.source]?.arrayValue ?? []).map(Optional.some)
                if items.isEmpty {
                    studio.mark(step.id, .skipped(AppLocalization.string("workflow.skip.emptyLoop")))
                    state = state.advanced()
                    if let queue, let job {
                        _ = try? await queue.checkpoint(job.id, state: state, kind: .stepSkipped, step: step, message: "emptyLoop")
                    }
                    continue
                }
            } else {
                items = [nil]
            }

            studio.mark(step.id, .running)
            if let queue, let job {
                _ = try? await queue.checkpoint(job.id, state: state, kind: .stepStarted, step: step)
            }

            var finalOutcome: StudioStepState = .done
            let resumeIndex = min(state.iterationIndex, items.count)
            for index in resumeIndex..<items.count {
                if Task.isCancelled {
                    if let queue, let job { try? await queue.pause(job.id, state: state) }
                    wasPaused = true
                    break
                }
                if let loop = step.forEach, let item = items[index] {
                    state.variables[loop.itemVariable] = item
                }
                try? await Task.sleep(for: .milliseconds(220))
                let outcome = await perform(step.kind, step: step.id, in: definition)
                finalOutcome = outcome

                if let loop = step.forEach {
                    state.variables.removeValue(forKey: loop.itemVariable)
                }

                // Media and cursor are both durable at every element boundary. Built-in editing
                // tools are setters or deterministic transforms, so replaying the current element
                // after a crash is safe; completed elements are never repeated.
                try? await dependencies.projectStore.save(project)
                state = state.advancedIteration()
                if let queue, let job {
                    let kind: WorkflowRunJournalEntry.Kind
                    if case .skipped = outcome { kind = .stepSkipped } else { kind = .stepCompleted }
                    _ = try? await queue.checkpoint(job.id, state: state, kind: kind, step: step)
                }
                try? await Task.sleep(for: .milliseconds(160))
            }
            if wasPaused { break }

            studio.mark(step.id, finalOutcome)
            let completed: Bool
            if case .done = finalOutcome { completed = true } else { completed = false }
            state.variables["\(step.kind.typeName).completed"] = .bool(completed)
            state.variables["step.\(step.id.uuidString).completed"] = .bool(completed)
            state = state.advanced()
            if let queue, let job {
                _ = try? await queue.checkpoint(job.id, state: state, step: step)
            }
        }

        editorModel.project = project
        editorModel.endBatch(startingFrom: before)
        scheduleSave()
        await refreshLibrary()
        studio.finishRun(video: workflowVideo, delivery: workflowDeliveryResult)
        if !wasPaused {
            if let queue, let job { try? await queue.complete(job.id, state: state) }
            noteCertifiedWorkflowRun()
        }
        if before.segments != project.segments {
            show(notice: AppLocalization.string("workflow.undoable"))
        }
    }

    /// Stable facts that conditions can use without an AI or a tool having to rediscover them.
    private func workflowRuntimeVariables() -> [String: WorkflowValue] {
        [
            "project.id": .string(project.id.uuidString),
            "project.locale": .string(project.localeIdentifier),
            "project.segmentCount": .number(Double(project.segments.count)),
            "project.recordingCount": .number(Double(project.recordings.count)),
            "project.hasSpeech": .bool(hasTranscripts),
            "project.hasMusic": .bool(project.audio.contains { $0.role == .music }),
            "project.hasVideoLayers": .bool(!project.videoLayers.isEmpty),
        ]
    }

    private func perform(_ kind: WorkflowStepKind, step: WorkflowStep.ID, in definition: WorkflowDefinition) async -> StudioStepState {
        switch kind {
        case .assembleSections:
            return assemble(definition.sections)

        case .analyzeSpeech:
            await transcribeNewTakes()
            return hasTranscripts ? .done : .skipped(AppLocalization.string("workflow.skip.noSpeech"))

        case .trimSilences(let options):
            guard hasTranscripts else { return .skipped(AppLocalization.string("workflow.skip.needsSpeech")) }
            editorModel.project = project
            for index in editorModel.project.segments.indices.reversed() {
                editorModel.tightenSilences(at: index, threshold: options.minPause, pad: options.padding)
            }
            project = editorModel.project
            return .done

        case .cutWords(let options):
            guard hasTranscripts else { return .skipped(AppLocalization.string("workflow.skip.needsSpeech")) }
            editorModel.project = project
            cutWords(options.words)
            project = editorModel.project
            return .done

        case .setSpeed(let options):
            editorModel.project = project
            let wanted = WorkflowSection(role: options.target).segmentRole
            var changed = 0
            for index in editorModel.project.segments.indices {
                guard options.target == "all" || editorModel.project.segments[index].role == wanted else { continue }
                editorModel.updatePlayback(at: index) { $0.speed = options.speed }
                changed += 1
            }
            project = editorModel.project
            return changed > 0 ? .done : .skipped(AppLocalization.string("workflow.skip.noSection"))

        case .cleanAudio(let options):
            let effects = AudioEffects(
                noiseReduction: options.denoise,
                voiceEnhance: options.enhanceVoice,
                deRumble: options.removeRumble
            )
            // The voice in the footage first — that is what almost always needs it — and any added
            // audio with it.
            project.voiceEffects = effects
            for index in project.audio.indices {
                project.audio[index].effects = effects
            }
            return .done

        case .musicBed(let options):
            let music = project.audio.indices.filter { project.audio[$0].role == .music }
            guard !music.isEmpty else { return .skipped(AppLocalization.string("workflow.skip.noMusic")) }
            for index in music {
                project.audio[index].setDecibels(options.levelDB)
                project.audio[index].ducksUnderVoice = options.ducking
                project.audio[index].fadeIn = MediaTime(seconds: options.fadeIn)
                project.audio[index].fadeOut = MediaTime(seconds: options.fadeOut)
            }
            return .done

        case .generateCaptions:
            guard definition.style.captions else { return .skipped(AppLocalization.string("workflow.skip.captionsOff")) }
            if !hasTranscripts { await transcribeNewTakes() }
            rebuildCaptions()
            return project.segments.contains { !$0.captions.isEmpty }
                ? .done
                : .skipped(AppLocalization.string("workflow.skip.needsSpeech"))

        case .applyCaptionStyle(let preset):
            guard definition.style.captions else { return .skipped(AppLocalization.string("workflow.skip.captionsOff")) }
            applyCaptionStyle(presetID: preset, position: definition.style.position)
            return .done

        case .export(let preset):
            project.format = definition.style.format
            editorModel.project = project
            exportDestinationOverride = preset.destination
            defer { exportDestinationOverride = nil }
            exportModel.reset()
            // Captions off in the workflow: the file is written without them, the project keeps them.
            await exportProject(burnCaptions: definition.style.captions && preset.burnsInCaptions)
            guard let video = exportModel.outputURL else {
                let reason = exportModel.failureDetail.map { AppLocalization.string("workflow.skip.exportFailed") + " · " + $0 }
                    ?? AppLocalization.string("workflow.skip.exportFailed")
                return .skipped(reason)
            }
            workflowVideo = video
            if let delivery = preset.delivery, delivery.isEnabled {
                workflowStudio?.note(AppLocalization.string("workflow.delivery.sending"), for: step)
                let result = await deliverWorkflowVideo(video, delivery: delivery, definition: definition)
                workflowDeliveryResult = result
                workflowStudio?.note(nil, for: step)
                if case .failed(let reason) = result {
                    return .skipped(AppLocalization.string("workflow.delivery.failed \(reason)"))
                }
            }
            return .done

        case .generateVideo(let options):
            return await generateVideos(options, step: step)

        case .generateScript, .segmentScript:
            return .skipped(AppLocalization.string("workflow.skip.script"))

        case .record:
            return .skipped(AppLocalization.string("workflow.skip.record"))

        case .unsupported:
            return .skipped(AppLocalization.string("workflow.skip.unsupported"))
        }
    }

    /// Sends the finished video to the workflow's own API.
    func deliverWorkflowVideo(_ video: URL, delivery: WorkflowDelivery, definition: WorkflowDefinition) async -> StudioDeliveryResult {
        let size = project.format.renderSize
        let bytes = (try? video.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        let report = WorkflowDeliveryReport(
            workflowID: definition.id,
            workflowName: definition.name,
            projectID: project.id,
            projectTitle: project.title,
            seconds: editorModel.duration,
            width: size.width,
            height: size.height,
            frameRate: project.format.frameRate,
            fileName: video.lastPathComponent,
            fileBytes: bytes,
            captions: project.segments.flatMap(\.captions).map(\.text).joined(separator: " ")
        )
        let secret = WorkflowSecretStore().secret(for: definition.id)
        do {
            let outcome = try await WorkflowDeliveryClient().deliver(delivery, video: video, report: report, secret: secret)
            return .sent(status: outcome.status)
        } catch {
            return .failed(StudioDeliveryText.describe(error))
        }
    }

    /// The result card's "send again", with the video the last run wrote.
    func resendWorkflowDelivery() {
        guard let studio = workflowStudio, let video = studio.lastRunSummary?.video,
              let delivery = studio.definition.delivery, delivery.isEnabled
        else { return }
        let definition = studio.definition
        studio.updateRunDelivery(.sending)
        Task {
            let result = await deliverWorkflowVideo(video, delivery: delivery, definition: definition)
            studio.updateRunDelivery(result)
        }
    }

    /// The result card's "open in editor".
    func openWorkflowResult() {
        flushWorkflowSave()
        openEditor()
    }

    private var hasTranscripts: Bool {
        project.segments.contains { $0.selectedTake?.transcript?.words.isEmpty == false }
    }

    /// Lays the footage into the workflow's sections.
    ///
    /// A section names a clip by its number. Sections that name none take the clips nobody claimed,
    /// in order, so a workflow written without clip numbers still assembles the video the user
    /// imported rather than replacing it with empty placeholders. Sections left with no footage at
    /// all are dropped: a segment with no take is a hole in the video, and the run used to leave
    /// the project as "point, point, cta" with nothing in them.
    ///
    /// A section's take points at its whole clip and keeps any transcript that clip already has,
    /// so re-running a workflow does not listen to the same footage twice.
    private func assemble(_ sections: [WorkflowSection]) -> StudioStepState {
        guard !sections.isEmpty else { return .skipped(AppLocalization.string("workflow.skip.noSections")) }
        guard !project.recordings.isEmpty else { return .skipped(AppLocalization.string("workflow.skip.noClips")) }

        // Clips named by a section, and the ones left over for the sections that name none.
        var claimed = Set<Int>()
        for section in sections {
            if let slot = section.clip, project.recordings.indices.contains(slot - 1) {
                claimed.insert(slot - 1)
            }
        }
        var spare = project.recordings.indices.filter { !claimed.contains($0) }

        let existingTakes = project.segments.flatMap(\.takes)
        var segments: [Segment] = []
        var unused = 0

        for section in sections {
            var slot: Int?
            if let named = section.clip, project.recordings.indices.contains(named - 1) {
                slot = named - 1
            } else if !spare.isEmpty {
                slot = spare.removeFirst()
            }
            guard let slot else {
                unused += 1
                continue
            }

            let recording = project.recordings[slot]
            let previous = existingTakes.first {
                $0.recordingID == recording.id && $0.sourceRange.start.seconds < 0.01
                    && abs($0.sourceRange.duration.seconds - recording.duration.seconds) < 0.05
            }
            let take = Take(
                recordingID: recording.id,
                sourceRange: MediaTimeRange(start: .zero, duration: recording.duration),
                status: .ready,
                transcript: previous?.transcript
            )
            segments.append(
                Segment(
                    role: section.segmentRole,
                    title: section.title,
                    script: take.transcript?.text ?? "",
                    estimatedDuration: take.duration,
                    takes: [take],
                    selectedTakeID: take.id
                )
            )
        }

        guard !segments.isEmpty else { return .skipped(AppLocalization.string("workflow.skip.noClips")) }

        project.segments = segments
        project.transitions.removeAll { transition in
            !segments.contains { $0.id == transition.after }
        }
        project.updatedAt = .now
        editorModel.project = project
        if unused > 0 {
            // Sections with no footage left are dropped rather than left as holes in the video.
            show(notice: AppLocalization.string("workflow.assembled \(segments.count) \(unused)"))
        }
        return .done
    }

    /// Removes filler words wherever they are said on their own.
    ///
    /// Compared without case, accents or punctuation, so "Eee," and "eee" are the same word.
    /// Runs back to front within each segment: removing a stretch rebuilds the segment into the
    /// part before it and the part after, and the part before keeps its own timings — so the
    /// earlier matches are still where the transcript says they are.
    private func cutWords(_ fillers: [String]) {
        let targets = Set(fillers.map(Self.normalized))
        guard !targets.isEmpty else { return }

        for index in editorModel.project.segments.indices.reversed() {
            let words = editorModel.spokenWords(at: index)
            let hits = words.indices.filter { targets.contains(Self.normalized(words[$0].text)) }
            guard !hits.isEmpty else { continue }

            // Adjacent fillers ("ııı eee") become one cut rather than two splices a frame apart.
            var ranges: [(start: Double, end: Double)] = []
            for hit in hits {
                let start = words[hit].range.start.seconds
                let end = words[hit].range.end.seconds
                if let last = ranges.last, start - last.end < 0.08 {
                    ranges[ranges.count - 1].end = end
                } else {
                    ranges.append((start, end))
                }
            }

            for range in ranges.reversed() {
                editorModel.removeSpoken(at: index, from: range.start, to: range.end)
            }
        }
    }

    private static func normalized(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    /// Captions from the transcripts that already exist. Trimming clears captions on purpose —
    /// their timings describe footage that is gone — so this is what brings them back afterwards
    /// without listening to anything again.
    private func rebuildCaptions() {
        for index in project.segments.indices {
            guard let transcript = project.segments[index].selectedTake?.transcript,
                  !transcript.words.isEmpty
            else { continue }
            project.segments[index].captions = CaptionBuilder.cues(
                from: transcript,
                maxWordsPerCue: project.captionStyle.maxWordsPerCue
            )
        }
        project.updatedAt = .now
        editorModel.project = project
    }
}
