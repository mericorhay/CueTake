import AIServices
import AssistantFeature
import AVFoundation
import CaptureEngine
import Domain
import EditorFeature
import LibraryFeature
import MediaEngine
import Observation
import Persistence
import Photos
import PhotosUI
import ScriptFeature
import SpeechEngine
import SettingsFeature
import StudioFeature
import SwiftUI
import WorkflowsFeature

/// Which screen is on top. Mirrors the design's screen graph one to one.
enum Screen: Hashable {
    case onboarding
    case home
    case create
    case prompt
    case blueprint
    case script
    case studio
    case complete
    case editor
    case retake
    case captions
    case export
    case projects
    case workflows
    case workflowDetail
    case settings

    /// The four screens that sit under the tab bar.
    var isRoot: Bool {
        switch self {
        case .home, .projects, .workflows, .settings: true
        default: false
        }
    }
}

/// Holds the project being worked on and the per-screen models, so state survives navigation
/// the way it does in the design (the prompter keeps its layout, the editor keeps its playhead).
///
/// Models are built when navigation happens, never while a view is drawing: reading a property
/// that writes state from inside `body` makes SwiftUI re-run the body that caused the write.
@MainActor
@Observable
final class AppModel {
    var screen: Screen = .onboarding
    var project: Project

    private(set) var dependencies = AppDependencies.live

    let promptModel = PromptModel()
    let exportModel = ExportModel()
    let settingsModel: SettingsModel

    private(set) var studioModel: StudioModel
    private(set) var editorModel: EditorModel
    private(set) var retakeModel: RetakeModel?

    init() {
        // A blank project until the library says otherwise. The models are seeded from this one
        // instance so their identifiers match the project's.
        let project = Self.blankProject()
        self.project = project
        self.studioModel = StudioModel(project: project)
        self.editorModel = EditorModel(project: project)

        // `AppDependencies.live` rather than `dependencies`: a property cannot be read off `self`
        // until every stored property is initialized, and `settingsModel` is the one being assigned
        // here. Both names refer to the same instance — `live` is a static `let`.
        let settingsModel = SettingsModel(store: AppDependencies.live.settingsStore)
        self.settingsModel = settingsModel
        // Skipping the intro for someone who has already seen it is the whole point of recording
        // that they did.
        self.screen = settingsModel.settings.hasCompletedOnboarding ? .home : .onboarding
    }

    // MARK: - Library

    /// What the store holds, newest first. The library screens read this rather than a sample.
    private(set) var library: [ProjectSummary] = []

    var recentItems: [LibraryFeature.LibraryItem] {
        library.prefix(3).enumerated().map { index, summary in
            item(for: summary, at: index, height: 210)
        }
    }

    var projectItems: [LibraryFeature.LibraryItem] {
        library.enumerated().map { index, summary in
            // The design's grid alternates tall and short cards; keeping that rhythm matters more
            // than any one card's height meaning something.
            item(for: summary, at: index, height: index % 2 == 0 ? 206 : 164)
        }
    }

    private func item(for summary: ProjectSummary, at index: Int, height: CGFloat) -> LibraryFeature.LibraryItem {
        LibraryFeature.LibraryItem(
            id: summary.id,
            title: summary.title,
            meta: summary.updatedAt.formatted(.relative(presentation: .named)),
            duration: "\(summary.segmentCount)",
            fill: .ramp(at: index),
            height: height
        )
    }

    /// Removes a project and its media.
    ///
    /// If it is the one open, the app falls back to whatever is newest rather than holding a
    /// project that no longer exists — and seeds a fresh sample if the library is now empty, so
    /// there is always something to open.
    func deleteProject(id: Project.ID) async {
        try? await dependencies.projectStore.delete(id)
        await refreshLibrary()

        guard id == project.id else { return }
        if let next = library.first, let stored = try? await dependencies.projectStore.load(next.id) {
            adopt(stored)
        } else {
            adopt(Self.blankProject())
        }
    }

    /// Nothing yet: no segments, no footage, not written to disk until something is put in it.
    static func blankProject() -> Project {
        Project(
            title: String(localized: "project.blank"),
            localeIdentifier: Locale.current.identifier
        )
    }

    func refreshLibrary() async {
        library = (try? await dependencies.projectStore.summaries()) ?? []
    }

    // MARK: - Import

    /// Drives the photo picker.
    var isPickingFootage = false
    /// What the app is busy with, or nil. Shown as an overlay: importing thirty clips and
    /// transcribing them takes real time, and an app that goes quiet for a minute reads as frozen.
    var busy: String?

    // MARK: - Workflow state (behaviour in AppModel+Workflows)

    /// Every stored workflow, most recently edited first.
    var workflows: [WorkflowDefinition] = []
    /// The workflow open in the studio, if any.
    var workflowStudio: WorkflowStudioModel?
    /// Set when clips are being picked from inside a workflow, so the import comes back to it.
    var importReturnsToWorkflow = false
    var workflowSaveTask: Task<Void, Never>?

    // MARK: - Assistant & journey state (behaviour in AppModel+Assistant)

    let assistant = AssistantModel(isConnected: AppDependencies.live.assistantClient.isConfigured)
    var isAssistantOpen = false
    /// The journey map: where the user is, what is next, and the way to ask.
    var isJourneyOpen = false
    var isAssistantWired = false

    /// Turns picked clips into segments, in the order they were chosen.
    ///
    /// One segment per clip, because that is what the user is telling us: these are the beats, in
    /// this order. Everything downstream — trimming, reordering, retaking one of them — then works
    /// without knowing the footage was not shot here.
    func importFootage(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        busy = String(localized: "busy.importing")
        defer { busy = nil }

        let store = dependencies.projectStore

        // A fresh project rather than an append. Dropping clips into whatever happened to be open
        // is how the library ends up with one project that grows forever, and how an import lands
        // in a timeline next to segments from an unrelated script.
        var fresh = Project(
            title: String(localized: "project.untitled \(Date.now.formatted(date: .abbreviated, time: .shortened))"),
            localeIdentifier: Locale.current.identifier
        )
        try? await store.save(fresh)

        guard let mediaDirectory = try? await store.mediaDirectory(for: fresh.id) else { return }
        let importer = MediaImporter()

        for (index, item) in items.enumerated() {
            busy = String(localized: "busy.importing.progress \(index + 1) \(items.count)")
            guard let movie = try? await item.loadTransferable(type: ImportedMovie.self),
                  let clip = try? await importer.importClip(from: movie.url, into: mediaDirectory)
            else { continue }

            try? FileManager.default.removeItem(at: movie.url)

            if fresh.recordings.isEmpty {
                // Otherwise every import would be forced into the default vertical frame, which is
                // how a landscape clip came back letterboxed into a shape nobody asked for.
                fresh.format = clip.recording.format
            }
            fresh.recordings.append(clip.recording)
            fresh.segments.append(
                Segment(
                    // Numbered, not named after the file: "IMG_4821" on a timeline clip tells the
                    // user nothing they can use, and the order is the thing that matters.
                    role: .custom("\(index + 1)"),
                    title: clip.suggestedTitle,
                    script: "",
                    estimatedDuration: clip.take.duration,
                    takes: [clip.take],
                    selectedTakeID: clip.take.id
                )
            )
        }

        guard !fresh.segments.isEmpty else {
            // Nothing came through — leaving an empty project behind would be litter.
            try? await store.delete(fresh.id)
            return
        }

        fresh.updatedAt = .now
        try? await store.save(fresh)
        adopt(fresh)
        await refreshLibrary()

        // Clips picked from inside a workflow go back to the workflow. The user was dragging
        // footage onto sections; dropping them into the editor instead would lose their place.
        if importReturnsToWorkflow {
            importReturnsToWorkflow = false
            refreshWorkflowClips()
            go(to: .workflowDetail)
            return
        }

        go(to: .editor)
        await transcribeNewTakes()
    }

    /// Opens a project from the library. The one the user tapped, which is not always the one
    /// already loaded — the library used to ignore the tap and reopen whatever was current.
    func openProject(id: Project.ID) async {
        guard id != project.id else {
            openEditor()
            return
        }
        guard let stored = try? await dependencies.projectStore.load(id) else { return }
        adopt(stored)
        go(to: .editor)
    }

    /// Makes a project the one being worked on. Every per-screen model is rebuilt, because they
    /// hold segment identifiers that mean nothing in a different project.
    func adopt(_ newProject: Project) {
        project = newProject
        studioModel = StudioModel(project: newProject)
        editorModel = EditorModel(project: newProject)
        retakeModel = nil
    }

    /// The words of a whole recording, narrowed to one take and rebased on its start.
    ///
    /// A take is a window into a file; the transcript covers the file. Without this a take that
    /// begins thirty seconds in — anything produced by a split — carries word times pointing at
    /// somebody else's sentence, and editing by transcript would cut the wrong footage with
    /// complete confidence.
    private static func words(of transcript: Transcript, within range: MediaTimeRange) -> [TimedWord] {
        let start = range.start.seconds
        let end = range.end.seconds
        // A whole-file take is the common case and needs no work.
        guard start > 0.01 else {
            return transcript.words.filter { $0.range.start.seconds < end + 0.01 }
        }
        return transcript.words.compactMap { word in
            guard word.range.start.seconds >= start - 0.01, word.range.end.seconds <= end + 0.01 else {
                return nil
            }
            var shifted = word
            shifted.range = MediaTimeRange(
                start: MediaTime(seconds: word.range.start.seconds - start),
                duration: word.range.duration
            )
            return shifted
        }
    }

    /// Applies the caption choice to the project, so it survives leaving the screen.
    func applyCaptionStyle(presetID: String, position: CaptionPosition) {
        // The preset is the whole look now, not a label: face, size, colours, plate and how many
        // words sit on screen at once. Position is the user's own choice and is kept.
        let previous = project.captionStyle
        project.captionStyle = CaptionStyle.preset(presetID, position: position)

        // A different number of words per cue means different cues. Regrouped from the
        // transcript — but never over a segment where the user has typed their own captions,
        // which would silently throw their edits away.
        if previous.maxWordsPerCue != project.captionStyle.maxWordsPerCue {
            for index in project.segments.indices {
                guard let transcript = project.segments[index].selectedTake?.transcript,
                      !transcript.words.isEmpty,
                      !project.segments[index].captions.contains(where: \.isUserEdited)
                else { continue }
                project.segments[index].captions = CaptionBuilder.cues(
                    from: transcript,
                    maxWordsPerCue: project.captionStyle.maxWordsPerCue
                )
            }
        }

        project.updatedAt = .now
        editorModel.project = project
        scheduleSave()
    }

    /// The editor asks for playback; only this layer knows where the project's media lives.
    func prepareEditorPlayback() async {
        guard let mediaDirectory = try? await dependencies.projectStore.mediaDirectory(for: project.id) else { return }

        // Reversing is the one thing here that writes a file, and the first build of a reversed
        // clip is measured in seconds rather than milliseconds. Said out loud, because a preview
        // that goes quiet for ten seconds is indistinguishable from a broken one.
        let reversing = editorModel.project.segments.contains { $0.playback.isReversed }
        let cleaning = VoiceCleaner().needsWork(
            for: editorModel.project.recordings,
            effects: editorModel.project.voiceEffects,
            in: mediaDirectory
        )
        if reversing { busy = String(localized: "busy.reversing") }
        if cleaning { busy = String(localized: "busy.cleaningVoice") }
        await editorModel.loadPlayback(mediaDirectory: mediaDirectory)
        if reversing || cleaning { busy = nil }
        // After playback, not before: the waveforms are for looking at and the player is for
        // working with, and reading three minutes of song should never be what delays a play.
        await editorModel.loadWaveforms(mediaDirectory: mediaDirectory)
        await editorModel.loadThumbnails(mediaDirectory: mediaDirectory)
    }

    // MARK: - Audio

    /// Drives the audio file picker.
    var isPickingAudio = false

    /// Brings music, a voiceover or an effect into the open project.
    ///
    /// Dropped at the playhead rather than at zero: someone adding a sound is almost always adding
    /// it *here*, at the moment they are looking at, and a clip that lands at the start of the
    /// video every time is a clip that has to be dragged back every time.
    func importAudio(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        busy = String(localized: "busy.importing.audio")
        defer { busy = nil }

        guard let mediaDirectory = try? await dependencies.projectStore.mediaDirectory(for: project.id) else { return }
        let importer = MediaImporter()
        let at = MediaTime(seconds: editorModel.playhead)

        for url in urls {
            guard let imported = try? await importer.importAudio(
                from: url,
                startingAt: at,
                into: mediaDirectory
            ) else { continue }
            editorModel.addAudio(imported.clip)
        }

        project = editorModel.project
        scheduleSave()
        // The mix changed, so what the preview plays is now wrong until it is rebuilt.
        await prepareEditorPlayback()
    }

    // MARK: - Export

    /// Composes the timeline and writes it out, moving the export screen's stages as it goes.
    ///
    /// The screen does not know how to build a video and should not learn; it asks, and this
    /// answers. Stages are advanced from the work rather than a timer, so a long write shows as a
    /// long stage instead of a progress bar that finishes before the file does.
    func exportProject() async {
        exportModel.begin()

        let store = dependencies.projectStore
        guard let mediaDirectory = try? await store.mediaDirectory(for: project.id) else {
            exportModel.fail(String(localized: "export.failed.media"))
            return
        }

        let composer = VideoComposer()
        let project = project
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "\(project.id.uuidString).mov", directoryHint: .notDirectory)

        do {
            let assembled = try await composer.compose(project: project, mediaDirectory: mediaDirectory)
            exportModel.advance(to: 2)

            let url = try await composer.write(assembled, to: destination) { [exportModel] value in
                exportModel.report(value)
            }
            exportModel.advance(to: 3)

            if settingsModel.settings.exportDestination == .photoLibrary {
                try await Self.saveToPhotoLibrary(url)
            }
            exportModel.succeed(url: url)
        } catch {
            exportModel.fail(String(localized: "export.failed.generic"))
        }
    }

    /// Asks only for permission to add, never to read: the app writes one video and has no business
    /// with the rest of someone's library.
    ///
    /// `nonisolated`, and the change block explicitly `@Sendable`, because this was the export
    /// crash. The app target is main-actor by default, so a closure written here was inferred to
    /// belong to the main actor — and PhotoKit runs the change block on its own queue. Swift 6
    /// checks that at runtime and traps, which is why the export got all the way to the end,
    /// wrote the file, and then took the app down at the moment it saved to Photos.
    nonisolated private static func saveToPhotoLibrary(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    // MARK: - Persistence

    private var saveTask: Task<Void, Never>?

    /// Coalesces the writes that a drag or a text edit produces into one.
    ///
    /// Driven from the root view's `onChange` rather than a `didSet` on `project`: property
    /// observers and the `@Observable` macro's generated accessors do not mix, and the view layer
    /// already knows precisely when the value it is bound to has changed.
    func scheduleSave() {
        // An empty project is not written. It exists so the app has something to hold before
        // anything has been made, and saving it would put an empty card in the library.
        guard !(project.segments.isEmpty && project.recordings.isEmpty && project.audio.isEmpty) else { return }
        saveTask?.cancel()
        let project = project
        let store = dependencies.projectStore
        isSaving = true
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? await store.save(project)
            isSaving = false
            savedAt = .now
        }
    }

    /// True while a write is pending or in flight.
    private(set) var isSaving = false
    /// When the project last reached disk, or nil if it has not since the app opened.
    private(set) var savedAt: Date?

    /// What the editor says about the file on disk.
    ///
    /// The app saves by itself and should: nobody should lose an edit to a button they did not
    /// press. But an app that never mentions saving leaves people wondering whether it did, and
    /// wondering is worse than a button — so it says so, in a sentence, where it can be checked.
    var saveLabel: String {
        if isSaving { return String(localized: "save.saving") }
        guard let savedAt else { return String(localized: "save.never") }
        return String(localized: "save.saved \(savedAt.formatted(date: .omitted, time: .shortened))")
    }

    /// Writes now instead of in four hundred milliseconds. What the save button does.
    func saveNow() {
        saveTask?.cancel()
        let project = project
        let store = dependencies.projectStore
        isSaving = true
        saveTask = Task {
            try? await store.save(project)
            isSaving = false
            savedAt = .now
        }
    }

    /// Loads the most recently edited project, or writes the seeded one if there is nothing yet.
    /// Called once, when the root view appears.
    func restore() async {
        let store = dependencies.projectStore
        guard let summary = try? await store.summaries().first,
              let stored = try? await store.load(summary.id)
        else {
            // A first launch starts empty. It used to write a sample review reel into the library,
            // so a new user's first project was someone else's — and the first thing they had to
            // do in the app was work out what to delete.
            await refreshLibrary()
            return
        }
        project = stored
        studioModel = StudioModel(project: stored)
        editorModel = EditorModel(project: stored)
        await refreshLibrary()
    }

    func completeOnboarding() {
        settingsModel.update(\.hasCompletedOnboarding, to: true)
        go(to: .home)
    }

    func go(to screen: Screen) {
        stopTimers()
        self.screen = screen
    }

    /// The design clears every interval on navigation, so nothing keeps ticking behind a screen
    /// you have left: playback, the generation run, the export and the workflow all stop.
    private func stopTimers() {
        studioModel.stopTimers()
        editorModel.pause()
        promptModel.stopTimers()
        exportModel.stopTimers()
        retakeModel?.stopTimers()
    }

    /// Rebuilds the studio only when the script actually changed, so the prompter keeps its
    /// layout, size and mode between visits.
    /// Writes a script from the brief and turns it into a project.
    ///
    /// The four steps are the real stages of the work, not a countdown: checking the model is
    /// there, writing, turning beats into segments, saving. If the device cannot run the model the
    /// user is told which of those two reasons it is, because "unavailable" is not an answer.
    func generateScript() async {
        promptModel.begin()

        let locale = Locale.current.identifier

        // The router only returns a provider that is ready, so a nil answer is the interesting
        // case: the user deserves to know whether the model is missing or merely still arriving.
        guard let writer = await dependencies.ai.provider(
            .scriptWriting,
            as: (any ScriptWriting).self,
            localeIdentifier: locale
        ) else {
            let reason = await FoundationModelsScriptWriter()
                .availability(for: .scriptWriting, localeIdentifier: locale)
            promptModel.fail(
                reason == .unavailable(.modelNotReady)
                    ? String(localized: "prompt.failed.notReady")
                    : String(localized: "prompt.failed.unavailable")
            )
            return
        }

        promptModel.advance(to: 2)
        let brief = ScriptBrief(
            topic: promptModel.promptText,
            targetDuration: MediaTime(seconds: Double(promptModel.lengthSeconds)),
            platform: promptModel.platform,
            tone: promptModel.tone.briefValue,
            localeIdentifier: locale
        )

        do {
            var draft: ScriptDraft?
            for try await partial in writer.writeScript(brief, localeIdentifier: locale) {
                draft = partial
            }
            guard let draft, !draft.segments.isEmpty else {
                promptModel.fail(String(localized: "prompt.failed.empty"))
                return
            }

            promptModel.advance(to: 3)
            // Framed for where it is going: a YouTube script is a landscape project from the start.
            var fresh = Project(title: draft.title, format: promptModel.platform.defaultFormat, localeIdentifier: locale)
            fresh.segments = draft.segments.map(Segment.init(draft:))

            promptModel.advance(to: 4)
            try? await dependencies.projectStore.save(fresh)
            adopt(fresh)
            await refreshLibrary()
            promptModel.finish()
            go(to: .blueprint)
        } catch {
            promptModel.fail(String(localized: "prompt.failed.generic"))
        }
    }

    /// Hands the studio a file to write into, so a take is a recording rather than a timer.
    func beginStudioCapture() async {
        guard let mediaDirectory = try? await dependencies.projectStore.mediaDirectory(for: project.id) else {
            studioModel.startRecording()
            return
        }
        let url = mediaDirectory.appending(
            path: "\(UUID().uuidString).mov",
            directoryHint: .notDirectory
        )
        // Three seconds to get back into frame, then rolling.
        studioModel.beginCountdown(writingTo: url)
    }

    /// Folds a finished capture into the project: one recording, one take per segment.
    ///
    /// The file is listened to once, and what was said decides where each segment begins: the
    /// transcript is matched against the script, which is accurate to the word where the live
    /// prompter could only be accurate to the moment it heard it. Where a segment cannot be found
    /// the live boundary stands. Both ends are tightened too — the reach back from the shutter
    /// before the first word, and the reach for stop after the last — which is the trim every
    /// take used to need by hand.
    func adoptStudioCapture() async {
        guard let capture = studioModel.lastCapture else { return }

        let asset = AVURLAsset(url: capture.url)
        let measured = (try? await asset.load(.duration).seconds) ?? capture.duration
        guard measured > 0 else { return }

        // A take without sound while the microphone was allowed means listening got in the way of
        // recording on this phone. Listening is switched off for good; the sound matters more.
        let soundTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        if soundTracks.isEmpty, CameraSession.tapsAudio,
           CameraSession.authorization(for: .audio) == .authorized {
            CameraSession.disableAudioTap()
        }

        let recording = Recording(
            relativePath: "media/\(capture.url.lastPathComponent)",
            format: project.format,
            camera: settingsModel.settings.defaultCamera,
            duration: MediaTime(seconds: measured)
        )
        project.recordings.append(recording)

        busy = String(localized: "busy.aligning")
        let heard = try? await dependencies.speech.transcribeFile(at: capture.url, localeIdentifier: project.localeIdentifier)
        busy = nil

        var starts: [Double] = project.segments.indices.map { index in
            capture.segmentStarts.indices.contains(index) ? capture.segmentStarts[index] : measured
        }
        var end = measured
        if let heard, !heard.words.isEmpty {
            let found = ScriptAligner.segmentStarts(
                scripts: project.segments.map(\.script),
                words: heard.words,
                locale: project.locale
            )
            for index in starts.indices where found.indices.contains(index) {
                if let start = found[index] { starts[index] = start }
            }
            if let first = heard.words.first, !starts.isEmpty {
                starts[0] = max(0, min(starts[0], first.range.start.seconds) - 0.3)
            }
            if let last = heard.words.last {
                end = min(measured, last.range.end.seconds + 0.6)
            }
        }
        // Never backwards: a segment cannot begin before the one it follows.
        for index in starts.indices.dropFirst() {
            starts[index] = max(starts[index], starts[index - 1])
        }

        let edges = starts + [end]
        for index in project.segments.indices {
            let start = min(edges[index], end)
            let stop = min(edges[index + 1], end)
            // A segment the speaker never reached gets no take, rather than a sliver of silence.
            guard stop - start > 0.25 else { continue }

            var take = Take(
                recordingID: recording.id,
                sourceRange: MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: stop - start)),
                status: .ready
            )
            take.transcript = heard?.slice(from: start, to: stop)
            project.segments[index].takes.append(take)
            project.segments[index].selectedTakeID = take.id
            project.segments[index].refreshCaptions(maxWordsPerCue: project.captionStyle.maxWordsPerCue)
        }

        project.updatedAt = .now
        scheduleSave()
        await refreshLibrary()
        await transcribeNewTakes()
    }

    /// The studio finished. Fold the capture in before the Complete screen claims there is one.
    func finishStudioCapture() async {
        await adoptStudioCapture()
        go(to: .complete)
    }

    func beginRetakeCapture() async {
        guard let retakeModel else { return }
        guard let mediaDirectory = try? await dependencies.projectStore.mediaDirectory(for: project.id) else {
            retakeModel.start()
            return
        }
        retakeModel.start(
            writingTo: mediaDirectory.appending(path: "\(UUID().uuidString).mov", directoryHint: .notDirectory)
        )
    }

    /// Transcribes every take that has no transcript yet, and writes the captions that follow.
    ///
    /// Runs after footage arrives rather than on demand: by the time the user opens the captions
    /// screen they expect words to be there, and a spinner at that moment reads as the app not
    /// having bothered until asked.
    func transcribeNewTakes() async {
        guard let mediaDirectory = try? await dependencies.projectStore.mediaDirectory(for: project.id) else { return }
        busy = String(localized: "busy.transcribing")
        defer { busy = nil }
        let speech = dependencies.speech
        let locale = project.localeIdentifier
        let recordings = Dictionary(uniqueKeysWithValues: project.recordings.map { ($0.id, $0) })

        // One listen per file. A studio recording is one file behind every segment, and it used to
        // be transcribed again for each of them — five segments, five full passes over the same take.
        var heard: [Recording.ID: Transcript] = [:]

        for index in project.segments.indices {
            guard let takeID = project.segments[index].selectedTakeID,
                  let takeIndex = project.segments[index].takes.firstIndex(where: { $0.id == takeID })
            else { continue }

            if project.segments[index].takes[takeIndex].transcript != nil {
                // Already heard, but without captions — earlier builds cleared them on every cut.
                // Asking to transcribe is how the user says "where did my captions go", so they are
                // read back from the words that are still there.
                if project.segments[index].captions.isEmpty {
                    project.segments[index].refreshCaptions(maxWordsPerCue: project.captionStyle.maxWordsPerCue)
                }
                continue
            }

            guard let recording = recordings[project.segments[index].takes[takeIndex].recordingID] else { continue }

            let transcript: Transcript
            if let cached = heard[recording.id] {
                transcript = cached
            } else {
                let url = mediaDirectory.appending(
                    path: (recording.relativePath as NSString).lastPathComponent,
                    directoryHint: .notDirectory
                )
                guard let fresh = try? await speech.transcribeFile(at: url, localeIdentifier: locale) else { continue }
                heard[recording.id] = fresh
                transcript = fresh
            }

            // The transcriber reads the whole file; a take is a window into it. Word times are
            // stored relative to the take, so a take that starts thirty seconds in — anything
            // that has been split — would otherwise carry timings pointing at somebody else's
            // sentence.
            let take = project.segments[index].takes[takeIndex]
            let aligned = Transcript(
                localeIdentifier: transcript.localeIdentifier,
                words: Self.words(of: transcript, within: take.sourceRange)
            )

            project.segments[index].takes[takeIndex].transcript = aligned
            project.segments[index].refreshCaptions(
                maxWordsPerCue: project.captionStyle.maxWordsPerCue,
                carrying: project.segments[index].captions
            )
            // The script is what the prompter shows; for imported footage there was none, so what
            // was actually said becomes it.
            if project.segments[index].script.isEmpty {
                project.segments[index].script = aligned.text
            }
        }

        project.updatedAt = .now
        // The editor is holding its own copy and is very likely the screen that asked for this.
        // Without this line the transcript lands in the project and the panel that requested it
        // goes on saying there is nothing to read.
        editorModel.project = project
        scheduleSave()
    }

    func openStudio() {
        if studioModel.project.segments != project.segments {
            studioModel = StudioModel(project: project)
        }
        go(to: .studio)
    }

    /// The editor keeps its playhead and inspector; it only needs the current project.
    func openEditor() {
        editorModel.project = project
        go(to: .editor)
    }

    /// Takes the editor's edits back.
    ///
    /// The editor owns its own copy of the project while it is open — that is what lets it hold a
    /// playhead and a selection across navigation — and a copy that is never read back is a copy
    /// that loses work. Everything the editor does, cuts and audio alike, arrives here and from
    /// here goes to disk and to the exporter.
    func adoptEditorEdits() {
        guard project != editorModel.project else { return }
        project = editorModel.project
    }

    func startRetake(of segmentID: Segment.ID) {
        guard let segment = project.segment(id: segmentID) else { return }
        retakeModel = RetakeModel(segment: segment, localeIdentifier: project.localeIdentifier)
        // Matched to the rest of the project, or the retake comes back a different shape from the
        // shot it is replacing.
        retakeModel?.format = project.format
        go(to: .retake)
    }

    /// Complete offers a retake without naming a segment; the design lands on the main point.
    func startRetakeFromComplete() {
        let segment = project.segments.count > 2 ? project.segments[2] : project.segments.first
        guard let segment else { return }
        startRetake(of: segment.id)
    }

    /// Keeping a take is the only thing a retake changes; the rest of the cut is untouched.
    ///
    /// Which is the point of the whole model: a retake appends to one segment's takes and moves
    /// its selection. No other segment's range shifts, because no absolute time was ever stored.
    func keepRetake() {
        if let retakeModel,
           let capture = retakeModel.lastCapture,
           let index = project.segments.firstIndex(where: { $0.id == retakeModel.segment.id }) {
            let recording = Recording(
                relativePath: "media/\(capture.url.lastPathComponent)",
                format: project.format,
                camera: settingsModel.settings.defaultCamera,
                duration: MediaTime(seconds: capture.duration)
            )
            let take = Take(
                recordingID: recording.id,
                sourceRange: MediaTimeRange(start: .zero, duration: recording.duration),
                status: .ready
            )
            project.recordings.append(recording)
            project.segments[index].takes.append(take)
            project.segments[index].selectedTakeID = take.id
            project.updatedAt = .now
            scheduleSave()
        }
        retakeModel = nil
        openEditor()
        // A kept retake is new speech with no words yet: without this its captions stayed empty
        // and editing it by text said there was nothing to read.
        Task { await transcribeNewTakes() }
    }

    func finishExport() {
        exportModel.reset()
        go(to: .home)
    }
}
