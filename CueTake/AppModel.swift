import Domain
import EditorFeature
import MediaEngine
import Observation
import Persistence
import Photos
import PhotosUI
import ScriptFeature
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

    // MARK: - Import

    /// Drives the photo picker.
    var isPickingFootage = false
    private(set) var isImporting = false

    /// Turns picked clips into segments, in the order they were chosen.
    ///
    /// One segment per clip, because that is what the user is telling us: these are the beats, in
    /// this order. Everything downstream — trimming, reordering, retaking one of them — then works
    /// without knowing the footage was not shot here.
    func importFootage(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }

        let store = dependencies.projectStore
        guard let mediaDirectory = try? await store.mediaDirectory(for: project.id) else { return }
        let importer = MediaImporter()

        for item in items {
            guard let movie = try? await item.loadTransferable(type: ImportedMovie.self),
                  let clip = try? await importer.importClip(from: movie.url, into: mediaDirectory)
            else { continue }

            try? FileManager.default.removeItem(at: movie.url)

            project.recordings.append(clip.recording)
            var segment = Segment(
                role: .custom(clip.suggestedTitle),
                title: clip.suggestedTitle,
                script: "",
                estimatedDuration: clip.take.duration,
                takes: [clip.take],
                selectedTakeID: clip.take.id
            )
            segment.selectedTakeID = clip.take.id
            project.segments.append(segment)
        }

        project.updatedAt = .now
        scheduleSave()
        openEditor()
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
            let composition = try await composer.compose(project: project, mediaDirectory: mediaDirectory)
            exportModel.advance(to: 2)

            let url = try await composer.write(
                composition,
                preset: ExportPreset(
                    format: project.segments.first?.selectedTake != nil
                        ? .vertical1080
                        : ExportPreset.shortFormVertical.format,
                    burnsInCaptions: false,
                    destination: settingsModel.settings.exportDestination
                ),
                to: destination
            )
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
            return
        }
        project = stored
        studioModel = StudioModel(project: stored)
        editorModel = EditorModel(project: stored)
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
    func keepRetake() {
        retakeModel = nil
        openEditor()
    }

    func finishExport() {
        exportModel.reset()
        go(to: .home)
    }
}
