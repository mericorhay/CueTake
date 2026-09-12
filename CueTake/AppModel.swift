import AIServices
import AVFoundation
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
    let workflowModel = WorkflowRunModel()
    let settingsModel: SettingsModel

    private(set) var studioModel: StudioModel
    private(set) var editorModel: EditorModel
    private(set) var retakeModel: RetakeModel?

    init() {
        // `Project.sample` mints fresh identifiers on every call, so the models have to be seeded
        // from this one instance or their segment IDs would not match the project's.
        let project = Project.sample
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
            let seed = Project.sample
            try? await dependencies.projectStore.save(seed)
            adopt(seed)
            await refreshLibrary()
        }
    }

    func refreshLibrary() async {
        library = (try? await dependencies.projectStore.summaries()) ?? []
    }

    // MARK: - Import

    /// Drives the photo picker.
    var isPickingFootage = false
    /// What the app is busy with, or nil. Shown as an overlay: importing thirty clips and
    /// transcribing them takes real time, and an app that goes quiet for a minute reads as frozen.
    private(set) var busy: String?

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
    private func adopt(_ newProject: Project) {
        project = newProject
        studioModel = StudioModel(project: newProject)
        editorModel = EditorModel(project: newProject)
        retakeModel = nil
    }

    /// Applies the caption choice to the project, so it survives leaving the screen.
    func applyCaptionStyle(presetID: String, position: CaptionPosition) {
        project.captionStyle.presetID = presetID
        project.captionStyle.position = position
        project.updatedAt = .now
        scheduleSave()
    }

    /// The editor asks for playback; only this layer knows where the project's media lives.
    func prepareEditorPlayback() async {
        guard let mediaDirectory = try? await dependencies.projectStore.mediaDirectory(for: project.id) else { return }
        await editorModel.loadPlayback(mediaDirectory: mediaDirectory)
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
    private static func saveToPhotoLibrary(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        try await PHPhotoLibrary.shared().performChanges {
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
        saveTask?.cancel()
        let project = project
        let store = dependencies.projectStore
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? await store.save(project)
        }
    }

    /// Loads the most recently edited project, or writes the seeded one if there is nothing yet.
    /// Called once, when the root view appears.
    func restore() async {
        let store = dependencies.projectStore
        guard let summary = try? await store.summaries().first,
              let stored = try? await store.load(summary.id)
        else {
            try? await store.save(project)
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
        workflowModel.stopTimers()
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
            targetDuration: MediaTime(seconds: 30),
            platform: .instagramReels,
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
            var fresh = Project(title: draft.title, localeIdentifier: locale)
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
        studioModel.startRecording(writingTo: url)
    }

    /// Folds a finished capture into the project: one recording, one take per segment.
    ///
    /// The segment boundaries come from the prompter, which knew when the speaker moved on. That
    /// is the whole reason a single continuous file can be edited segment by segment — and why
    /// retaking one of them later touches nothing else.
    func adoptStudioCapture() async {
        guard let capture = studioModel.lastCapture else { return }

        let asset = AVURLAsset(url: capture.url)
        let measured = (try? await asset.load(.duration).seconds) ?? capture.duration
        guard measured > 0 else { return }

        let recording = Recording(
            relativePath: "media/\(capture.url.lastPathComponent)",
            format: project.format,
            camera: settingsModel.settings.defaultCamera,
            duration: MediaTime(seconds: measured)
        )
        project.recordings.append(recording)

        // A boundary per segment, plus the end of the file, so every segment gets a range.
        let bounds = capture.segmentStarts + [measured]
        for index in project.segments.indices {
            guard index + 1 < bounds.count else { break }
            let start = min(bounds[index], measured)
            let end = min(bounds[index + 1], measured)
            guard end > start else { continue }

            let take = Take(
                recordingID: recording.id,
                sourceRange: MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: end - start)),
                status: .ready
            )
            project.segments[index].takes.append(take)
            project.segments[index].selectedTakeID = take.id
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

        for index in project.segments.indices {
            guard let takeID = project.segments[index].selectedTakeID,
                  let takeIndex = project.segments[index].takes.firstIndex(where: { $0.id == takeID }),
                  project.segments[index].takes[takeIndex].transcript == nil,
                  let recording = recordings[project.segments[index].takes[takeIndex].recordingID]
            else { continue }

            let url = mediaDirectory.appending(
                path: (recording.relativePath as NSString).lastPathComponent,
                directoryHint: .notDirectory
            )
            guard let transcript = try? await speech.transcribeFile(at: url, localeIdentifier: locale) else { continue }

            project.segments[index].takes[takeIndex].transcript = transcript
            project.segments[index].captions = CaptionBuilder.cues(
                from: transcript,
                maxWordsPerCue: project.captionStyle.maxWordsPerCue
            )
            // The script is what the prompter shows; for imported footage there was none, so what
            // was actually said becomes it.
            if project.segments[index].script.isEmpty {
                project.segments[index].script = transcript.text
            }
        }

        project.updatedAt = .now
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

    func startRetake(of segmentID: Segment.ID) {
        guard let segment = project.segment(id: segmentID) else { return }
        retakeModel = RetakeModel(segment: segment)
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
    }

    func finishExport() {
        exportModel.reset()
        go(to: .home)
    }
}
