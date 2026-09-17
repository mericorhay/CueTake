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
    /// Scripts kept for reuse and the brand voice the AI writes in.
    let scriptLibrary = ScriptLibraryStore()
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
    /// Library covers drawn from each project's footage. See `ProjectCovers`.
    var covers: [Project.ID: UIImage] = [:]

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
            height: height,
            cover: covers[summary.id]
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
        Task { await refreshCovers() }
    }

    // MARK: - Import

    /// Drives the photo picker.
    var isPickingFootage = false
    /// A movie picked for a simultaneous video layer in the open project.
    var isPickingVideoLayer = false
    /// What the app is busy with, or nil. Shown as an overlay: importing thirty clips and
    /// transcribing them takes real time, and an app that goes quiet for a minute reads as frozen.
    var busy: String?
    /// The workflow run in progress, kept so it can be stopped.
    var workflowRunTask: Task<Void, Never>?
    /// Where a workflow's export step sends the video, for the length of that step.
    var exportDestinationOverride: ExportDestination?
    /// What the last workflow run wrote and what its API answered.
    var workflowVideo: URL?
    var workflowDeliveryResult: StudioDeliveryResult?
    /// Work going on in the background that does not stop anyone — listening to new clips.
    var activity: String?
    /// A short message that fades by itself: how listening went, what was restored.
    var notice: String?
    /// What the app takes on the phone, once measured.
    var storageBytes: Int64?
    /// Where the script screen and the studio go back to: the plan they came from, or Create.
    var scriptReturn: Screen = .blueprint
    var studioReturn: Screen = .blueprint
    var noticeTask: Task<Void, Never>?

    // MARK: - Workflow state (behaviour in AppModel+Workflows)

    /// Every stored workflow, most recently edited first.
    var workflows: [WorkflowDefinition] = []
    /// The workflow open in the studio, if any.
    var workflowStudio: WorkflowStudioModel?
    /// Set when clips are being picked from inside a workflow, so the import comes back to it.
    var importReturnsToWorkflow = false
    var workflowSaveTask: Task<Void, Never>?

    // MARK: - Assistant & journey state (behaviour in AppModel+Assistant)

    // Privacy defaults to on-device only. The assistant becomes connected in `wireAssistant`
    // only when both its endpoint and the user's cloud permission are present.
    let assistant = AssistantModel(isConnected: false)
    var isAssistantOpen = false
    /// The journey map: where the user is, what is next, and the way to ask.
    var isJourneyOpen = false
    var isAssistantWired = false

    /// Copies a selected movie into the open project as a second video track. It does not create a
    /// new segment: the layer is timed independently and can play beside the main cut.
    func importVideoLayer(_ item: PhotosPickerItem) async {
        // Checked before copying: a file copied only to be refused is a minute wasted and space used.
        takeEditorEditsIfEditing()
        guard project.videoLayers.count < VideoLayer.maximumAdditionalLayers else {
            show(notice: String(localized: "editor.video.limit"))
            return
        }
        guard let mediaDirectory = try? await dependencies.projectStore.mediaDirectory(for: project.id) else { return }
        busy = String(localized: "busy.importing")
        defer { busy = nil }
        guard let movie = try? await item.loadTransferable(type: ImportedMovie.self),
              let imported = try? await MediaImporter().importClip(from: movie.url, into: mediaDirectory)
        else {
            show(notice: String(localized: "editor.video.importFailed"))
            return
        }
        try? FileManager.default.removeItem(at: movie.url)
        // The editor may have changed while the file was copied.
        takeEditorEditsIfEditing()
        project.recordings.append(imported.recording)
        // Starts where the playhead is: that is the moment the user was looking at when they
        // chose to add a video there.
        let start = min(max(0, editorModel.playhead), max(0, editorModel.duration - 0.2))
        let layer = VideoLayer(
            recordingID: imported.recording.id,
            title: imported.suggestedTitle,
            start: MediaTime(seconds: start),
            sourceRange: imported.take.sourceRange,
            placement: project.videoLayers.isEmpty ? .inset : VideoPlacement(x: 0.05, y: 0.64, width: 0.31, height: 0.31, fillsFrame: true)
        )
        project.videoLayers.append(layer)
        project.updatedAt = .now
        editorModel.project = project
        editorModel.select(videoLayer: layer.id)
        scheduleSave()
    }

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
        // Your look, not the default one, if you have one.
        settingsModel.settings.applyStyle(to: &fresh)
        try? await store.save(fresh)

        guard let mediaDirectory = try? await store.mediaDirectory(for: fresh.id) else { return }

        // Three at a time rather than one after another. Most of an import is waiting on Photos
        // to hand over a file — often from iCloud — and those waits do not need to queue.
        busy = String(localized: "busy.importing.progress \(0) \(items.count)")
        var loaded: [Int: MediaImporter.ImportedClip] = [:]
        await withTaskGroup(of: (Int, MediaImporter.ImportedClip?).self) { group in
            var next = 0
            func enqueue() {
                guard next < items.count else { return }
                let index = next
                let item = items[index]
                next += 1
                group.addTask {
                    guard let movie = try? await item.loadTransferable(type: ImportedMovie.self) else { return (index, nil) }
                    let clip = try? await MediaImporter().importClip(from: movie.url, into: mediaDirectory)
                    try? FileManager.default.removeItem(at: movie.url)
                    return (index, clip)
                }
            }
            for _ in 0..<3 { enqueue() }
            var done = 0
            for await (index, clip) in group {
                done += 1
                busy = String(localized: "busy.importing.progress \(done) \(items.count)")
                if let clip { loaded[index] = clip }
                enqueue()
            }
        }

        for index in items.indices {
            guard let clip = loaded[index] else { continue }

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

        // Structure is part of the import result, not a best-effort screen effect. Doing this before
        // save/adopt also prevents the quiet transcription task below from restoring the numbered
        // pre-analysis copy over Hook/Point when a movie has no usable audio.
        SegmentRoleAnalyzer.applyAutomatically(
            to: &fresh.segments,
            localeIdentifier: fresh.localeIdentifier
        )
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
        busy = nil
        await transcribeNewTakes(quietly: true)
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
        // Reopening an older project must run the same role migration as the current project.
        // Otherwise clips imported before automatic roles existed keep their temporary 1/2 labels.
        openEditor()
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

    /// Applies a whole look — preset plus every adjustment — to every caption in the project.
    ///
    /// Words per line decides where cues break, so a change to it regroups captions from the
    /// transcript, except in clips where the user has typed their own.
    func applyCaptionStyle(_ style: CaptionStyle) {
        let previous = project.captionStyle
        project.captionStyle = style
        if previous.maxWordsPerCue != style.maxWordsPerCue {
            for index in project.segments.indices {
                guard project.segments[index].selectedTake?.transcript?.words.isEmpty == false,
                      !project.segments[index].captions.contains(where: \.isUserEdited)
                else { continue }
                project.segments[index].refreshCaptions(maxWordsPerCue: style.maxWordsPerCue)
            }
        }
        project.updatedAt = .now
        editorModel.project = project
        scheduleSave()

        if let preference = CaptionPreference(rawValue: style.presetID) {
            settingsModel.update(\.captionPreset, to: preference)
        }
        settingsModel.update(\.captionPosition, to: style.position)
    }

    /// Applies a preset to the project, so it survives leaving the screen.
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

        // Remembered for the next project. The Settings default and the last choice are the same
        // thing now: whatever you picked most recently is what you get.
        if let preference = CaptionPreference(rawValue: presetID) {
            settingsModel.update(\.captionPreset, to: preference)
        }
        settingsModel.update(\.captionPosition, to: position)
    }

    /// The editor asks for playback; only this layer knows where the project's media lives.
    func prepareEditorPlayback() async {
        connectEditorGeneration()
        connectEditorShorts()
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
    func exportProject(burnCaptions: Bool = true) async {
        guard !exportModel.isRunning else { return }
        exportModel.begin()

        let store = dependencies.projectStore
        guard let mediaDirectory = try? await store.mediaDirectory(for: project.id) else {
            exportModel.fail(String(localized: "export.failed.media"))
            return
        }

        let composer = VideoComposer()
        var project = project
        if !burnCaptions {
            for index in project.segments.indices { project.segments[index].captions = [] }
        }
        // Named after the project, so a shared file says what it is.
        let name = Self.exportFileName(for: project)
        let folder = FileManager.default.temporaryDirectory.appending(path: "exports", directoryHint: .isDirectory)
        // Earlier renders already went to Photos or were shared; the phone keeps only this one.
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: "\(name).mov", directoryHint: .notDirectory)

        let assembled: VideoComposer.Assembled
        do {
            assembled = try await composer.compose(project: project, mediaDirectory: mediaDirectory)
        } catch {
            exportModel.fail(Self.composeFailureMessage(error), detail: String(describing: error))
            return
        }
        exportModel.advance(to: 2)

        let written: VideoComposer.WriteResult
        do {
            written = try await composer.writeResilient(assembled, to: destination) { [exportModel] value in
                exportModel.report(value)
            }
        } catch {
            let detail: String
            if case VideoComposer.ComposeError.exportFailed(let reason) = error { detail = reason } else { detail = String(describing: error) }
            exportModel.fail(String(localized: "export.failed.generic"), detail: detail)
            return
        }
        exportModel.advance(to: 3)

        // The file exists whatever Photos says: a refused or failed save is reported, not fatal.
        var saved: ExportModel.Destination = .fileOnly
        if (exportDestinationOverride ?? settingsModel.settings.exportDestination) == .photoLibrary {
            saved = ((try? await Self.saveToPhotoLibrary(written.url)) ?? false) ? .photos : .photosRefused
        }
        exportModel.succeed(url: written.url, destination: saved, format: project.format, droppedCaptions: written.droppedCaptions)
    }

    /// A file name people can read, from the project title.
    static func exportFileName(for project: Project) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = String(project.title.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        let base = cleaned.isEmpty ? "CueTake" : String(cleaned.prefix(60))
        return "\(base) \(Int(Date.now.timeIntervalSince1970) % 100_000)"
    }

    /// Why a video could not be put together, in words that say what to do.
    static func composeFailureMessage(_ error: any Error) -> String {
        switch error {
        case VideoComposer.ComposeError.nothingToCompose:
            String(localized: "export.failed.empty")
        case VideoComposer.ComposeError.missingMedia, VideoComposer.ComposeError.noVideoTrack:
            String(localized: "export.failed.media")
        default:
            String(localized: "export.failed.generic")
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
    /// Returns whether the video reached Photos. A refused permission used to return quietly, and
    /// the export screen then said "ready" about a video that had gone nowhere.
    nonisolated private static func saveToPhotoLibrary(_ url: URL) async throws -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
        return true
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
        guard projectHasContent else { return }
        saveTask?.cancel()
        let project = project
        let store = dependencies.projectStore
        isSaving = true
        saveFailed = false
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                try await store.save(project)
                savedAt = .now
            } catch {
                saveFailed = true
            }
            isSaving = false
        }
    }

    /// True while a write is pending or in flight.
    private(set) var isSaving = false
    /// True when the last disk write failed. A failed autosave must never be labelled as saved.
    private(set) var saveFailed = false
    /// When the project last reached disk, or nil if it has not since the app opened.
    private(set) var savedAt: Date?

    /// What the editor says about the file on disk.
    ///
    /// The app saves by itself and should: nobody should lose an edit to a button they did not
    /// press. But an app that never mentions saving leaves people wondering whether it did, and
    /// wondering is worse than a button — so it says so, in a sentence, where it can be checked.
    var saveLabel: String {
        if isSaving { return String(localized: "save.saving") }
        if saveFailed { return String(localized: "save.failed") }
        guard let savedAt else { return String(localized: "save.never") }
        return String(localized: "save.saved \(savedAt.formatted(date: .omitted, time: .shortened))")
    }

    /// Writes now instead of in four hundred milliseconds. What the save button does.
    func saveNow() {
        saveTask?.cancel()
        let project = project
        let store = dependencies.projectStore
        isSaving = true
        saveFailed = false
        saveTask = Task {
            do {
                try await store.save(project)
                savedAt = .now
            } catch {
                saveFailed = true
            }
            isSaving = false
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
        // The export screen opens ready to render. A finished or failed export from an earlier
        // visit used to stay on it, with its old file and no render button.
        if screen == .export, self.screen != .export, !exportModel.isRunning {
            if self.screen == .editor, !editorModel.isAIDriving { adoptEditorEdits() }
            exportModel.reset()
        }
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
            if settingsModel.settings.aiProcessing == .allowCloud,
               dependencies.assistantClient.isConfigured {
                let brief = ScriptBrief(
                    topic: promptModel.promptText,
                    targetDuration: MediaTime(seconds: Double(promptModel.lengthSeconds)),
                    platform: promptModel.platform,
                    tone: promptModel.tone.briefValue,
                    localeIdentifier: locale,
                    brand: scriptLibrary.activeBrand
                )
                await generateScriptOnServer(brief, localeIdentifier: locale)
                return
            }
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
            localeIdentifier: locale,
            brand: scriptLibrary.activeBrand
        )

        do {
            var draft: ScriptDraft?
            for try await partial in writer.writeScript(brief, localeIdentifier: locale) {
                draft = partial
            }
            // The length asked for is the length delivered.
            guard let draft = draft.map({ ScriptBudget.fit($0, seconds: brief.targetDuration.seconds, localeIdentifier: locale) }),
                  !draft.segments.isEmpty
            else {
                promptModel.fail(String(localized: "prompt.failed.empty"))
                return
            }

            promptModel.advance(to: 3)
            // Framed for where it is going: a YouTube script is a landscape project from the start.
            var fresh = Project(title: draft.title, format: promptModel.platform.defaultFormat, localeIdentifier: locale)
            fresh.segments = draft.segments.map(Segment.init(draft:))
            settingsModel.settings.applyStyle(to: &fresh)

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
        let studio = studioModel
        guard await studio.prepareCapture() else { return }
        guard let mediaDirectory = try? await dependencies.projectStore.mediaDirectory(for: project.id) else {
            studio.failCapture("studio.capture.storage")
            return
        }
        let url = mediaDirectory.appending(
            path: "\(UUID().uuidString).mov",
            directoryHint: .notDirectory
        )
        // The countdown the reader chose, to get back into frame, then rolling.
        studio.beginCountdown(writingTo: url)
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
        // Recorded without a script: one beat to hold the take, its words filled in once heard.
        if project.segments.isEmpty {
            project.segments = [Segment(role: .mainPoint, script: "")]
        }

        busy = String(localized: "busy.aligning")
        let versions = try? await listen(
            to: capture.url,
            localeIdentifier: project.localeIdentifier,
            script: project.segments.map(\.script).joined(separator: " ")
        )
        let heard = versions?.merged
        if let versions, let stored = project.recordings.firstIndex(where: { $0.id == recording.id }) {
            project.recordings[stored].speech = versions
        }
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
            if project.segments[index].script.isEmpty, let words = take.transcript?.words, !words.isEmpty {
                project.segments[index].script = words.map(\.text).joined(separator: " ")
            }
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
        guard await retakeModel.prepareCapture() else { return }
        guard let mediaDirectory = try? await dependencies.projectStore.mediaDirectory(for: project.id) else {
            retakeModel.failCapture("studio.capture.storage")
            return
        }
        retakeModel.start(
            writingTo: mediaDirectory.appending(path: "\(UUID().uuidString).mov", directoryHint: .notDirectory)
        )
    }

    /// Transcribes every take that has no transcript yet, and writes the captions that follow.
    ///
    /// - Parameter quietly: listen in the background, with a small status instead of the blocking
    ///   overlay. What an import uses: the clips are already on the timeline and can be worked with
    ///   while the words arrive — making someone wait a minute to see footage they just picked was
    ///   most of why importing felt slow.
    ///
    /// Always says how it went. Listening used to fail in silence — an unsupported language, a file
    /// without sound — and the button looked broken.
    func transcribeNewTakes(quietly: Bool = false) async {
        guard let mediaDirectory = try? await dependencies.projectStore.mediaDirectory(for: project.id) else { return }
        takeEditorEditsIfEditing()

        let maxWords = project.captionStyle.maxWordsPerCue
        var repaired = false
        var pending: [Recording.ID] = []
        for index in project.segments.indices {
            guard let take = project.segments[index].selectedTake else { continue }
            if take.transcript != nil {
                // Already heard, but without captions — earlier builds cleared them on every cut.
                if project.segments[index].captions.isEmpty {
                    project.segments[index].refreshCaptions(maxWordsPerCue: maxWords)
                    repaired = repaired || !project.segments[index].captions.isEmpty
                }
            } else if !pending.contains(take.recordingID) {
                pending.append(take.recordingID)
            }
        }
        if repaired {
            project.updatedAt = .now
            editorModel.project = project
            scheduleSave()
        }
        guard !pending.isEmpty else {
            if !quietly {
                show(notice: repaired
                    ? String(localized: "speech.restored")
                    : String(localized: "speech.nothingNew"))
            }
            return
        }

        if quietly {
            activity = String(localized: "activity.listening")
        } else {
            busy = String(localized: "busy.transcribing")
        }
        defer {
            activity = nil
            busy = nil
        }

        // One listen per file. A studio recording is one file behind every segment.
        let locale = project.localeIdentifier
        let recordings = Dictionary(uniqueKeysWithValues: project.recordings.map { ($0.id, $0) })
        var heard: [Recording.ID: Transcript] = [:]
        var heardVersions: [Recording.ID: TranscriptVersions] = [:]
        var failure: (any Error)?
        for recordingID in pending {
            guard let recording = recordings[recordingID] else { continue }
            let url = mediaDirectory.appending(
                path: (recording.relativePath as NSString).lastPathComponent,
                directoryHint: .notDirectory
            )
            // What the speaker meant to say in this file, as a hint for both the server listener
            // and the judge.
            let script = project.segments
                .filter { $0.takes.contains { $0.recordingID == recordingID } }
                .map(\.script)
                .joined(separator: " ")
            do {
                let versions = try await listen(to: url, localeIdentifier: locale, script: script)
                let transcript = versions.merged
                if !transcript.words.isEmpty {
                    heard[recordingID] = transcript
                    heardVersions[recordingID] = versions
                }
            } catch {
                failure = error
            }
        }

        // Applied to the project as it is now, not as it was when listening began: the user may
        // have cut, trimmed or reordered in the meantime, and those edits must survive.
        takeEditorEditsIfEditing()
        // Both versions kept with the file, so either can be chosen later.
        for (recordingID, versions) in heardVersions {
            if let stored = project.recordings.firstIndex(where: { $0.id == recordingID }) {
                project.recordings[stored].speech = versions
            }
        }
        var captioned = 0
        for index in project.segments.indices {
            guard let takeID = project.segments[index].selectedTakeID,
                  let takeIndex = project.segments[index].takes.firstIndex(where: { $0.id == takeID }),
                  project.segments[index].takes[takeIndex].transcript == nil,
                  let transcript = heard[project.segments[index].takes[takeIndex].recordingID]
            else { continue }

            // The transcriber reads the whole file; a take is a window into it. Word times are
            // stored relative to the take.
            let take = project.segments[index].takes[takeIndex]
            let aligned = Transcript(
                localeIdentifier: transcript.localeIdentifier,
                words: Self.words(of: transcript, within: take.sourceRange)
            )
            project.segments[index].takes[takeIndex].transcript = aligned
            if project.segments[index].metadata[Self.trimToSpeechKey] == take.id.uuidString {
                project.segments[index].metadata[Self.trimToSpeechKey] = nil
                if let trimmed = project.segments[index].takes[takeIndex].trimmedToSpeech() {
                    project.segments[index].takes[takeIndex] = trimmed
                    project.segments[index].estimatedDuration = trimmed.sourceRange.duration
                }
            }
            project.segments[index].refreshCaptions(maxWordsPerCue: maxWords, carrying: project.segments[index].captions)
            captioned += project.segments[index].captions.count
            // The script is what the prompter shows; for imported footage there was none, so what
            // was actually said becomes it.
            if project.segments[index].script.isEmpty {
                project.segments[index].script = aligned.text
            }
        }

        project.updatedAt = .now
        // A transcript can refine Hook/Intro/Point/Example/CTA, but it must refine the project that
        // is about to replace the editor's copy. Applying it here closes the async race that used to
        // restore numbered roles after the editor had already analysed them.
        SegmentRoleAnalyzer.applyAutomatically(
            to: &project.segments,
            localeIdentifier: project.localeIdentifier
        )
        editorModel.project = project
        scheduleSave()

        if captioned > 0 {
            show(notice: String(localized: "speech.done \(captioned)"))
        } else {
            switch failure as? SpeechError {
            case .localeNotSupported:
                show(notice: String(localized: "speech.failed.language"))
            case .noAudio:
                show(notice: String(localized: "speech.failed.noAudio"))
            case .notAuthorized:
                show(notice: String(localized: "speech.failed.permission"))
            default:
                if let failure {
                    // The system's own words, so a failure nobody anticipated can still be reported.
                    show(notice: String(localized: "speech.failed.error \(failure.localizedDescription)"))
                } else {
                    show(notice: String(localized: "speech.failed.nothingHeard"))
                }
            }
        }
    }

    /// The editor's copy wins only while the editor is the screen being used. The captions screen
    /// edits the project directly, and taking the editor's older copy then would undo its edits.
    func takeEditorEditsIfEditing() {
        if screen == .editor { adoptEditorEdits() }
    }

    /// A line that appears at the top and goes away by itself.
    func show(notice text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func openStudio() {
        if studioModel.project.segments != project.segments {
            studioModel = StudioModel(project: project)
        }
        go(to: .studio)
    }

    /// The editor keeps its playhead and inspector; it only needs the current project.
    func openEditor() {
        let changed = SegmentRoleAnalyzer.applyAutomatically(
            to: &project.segments,
            localeIdentifier: project.localeIdentifier
        )
        if changed > 0 {
            project.updatedAt = .now
            scheduleSave()
        }
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
        if project.voiceEffects != editorModel.project.voiceEffects {
            settingsModel.update(\.voiceEffects, to: editorModel.project.voiceEffects)
        }
        project = editorModel.project
    }

    /// Marks a kept retake whose silence before and after the speech is still to be trimmed.
    static let trimToSpeechKey = "retake.trimToSpeech"

    func startRetake(of segmentID: Segment.ID) {
        guard let segment = project.segment(id: segmentID) else { return }
        retakeModel = RetakeModel(segment: segment, localeIdentifier: project.localeIdentifier)
        // Matched to the rest of the project, or the retake comes back a different shape from the
        // shot it is replacing.
        retakeModel?.format = project.format
        if let retake = retakeModel, let take = segment.selectedTake,
           let recording = project.recordings.first(where: { $0.id == take.recordingID }) {
            let projectID = project.id
            Task {
                guard let directory = try? await dependencies.projectStore.mediaDirectory(for: projectID) else { return }
                retake.originalRecordingURL = directory.deletingLastPathComponent().appending(path: recording.relativePath)
            }
        }
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
        if let retakeModel, retakeModel.choice == .new,
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
            // Once its words are known, the reach to the shutter and back is trimmed off.
            project.segments[index].metadata[Self.trimToSpeechKey] = take.id.uuidString
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
