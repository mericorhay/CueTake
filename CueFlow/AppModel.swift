import Domain
import EditorFeature
import Observation
import ScriptFeature
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
@MainActor
@Observable
final class AppModel {
    var screen: Screen = .onboarding
    var project: Project = .sample

    private(set) var dependencies = AppDependencies.live

    let promptModel = PromptModel()
    let exportModel = ExportModel()
    let workflowModel = WorkflowRunModel()

    private var studioModelStorage: StudioModel?
    private var editorModelStorage: EditorModel?
    private(set) var retakeModel: RetakeModel?

    /// Recreated whenever the script changes, so the prompter always shows the current segments.
    var studioModel: StudioModel {
        if let studioModelStorage, studioModelStorage.project.segments == project.segments {
            return studioModelStorage
        }
        let model = StudioModel(project: project)
        studioModelStorage = model
        return model
    }

    var editorModel: EditorModel {
        if let editorModelStorage {
            editorModelStorage.project = project
            return editorModelStorage
        }
        let model = EditorModel(project: project)
        editorModelStorage = model
        return model
    }

    func go(to screen: Screen) {
        withAnimation(nil) { self.screen = screen }
    }

    func startRetake(of segmentID: Segment.ID) {
        guard let segment = project.segment(id: segmentID) ?? project.segments.first else { return }
        retakeModel = RetakeModel(segment: segment)
        go(to: .retake)
    }

    func startRetakeOfFirstSegment() {
        guard let first = project.segments.first else { return }
        startRetake(of: first.id)
    }

    /// Keeping a take is the only thing a retake changes; the rest of the cut is untouched.
    func keepRetake() {
        retakeModel = nil
        go(to: .editor)
    }

    func finishExport() {
        exportModel.reset()
        go(to: .home)
    }
}
