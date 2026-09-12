import AIServices
import CaptureEngine
import MediaEngine
import Persistence
import SpeechEngine
import WorkflowEngine

/// Composition root: the only place that knows concrete implementations.
/// Features receive the protocols they need through their initializers; there is no global container.
struct AppDependencies {
    var projectStore: any ProjectStore
    var camera: any CameraCapturing
    var speech: any SpeechTranscribing
    var scriptTracker: any ScriptTracking
    var composer: any MediaComposing
    var exporter: any VideoExporting
    var ai: AICapabilityRouter
    var workflowRunner: WorkflowRunner

    /// Every engine is a placeholder until it is implemented.
    static let live = AppDependencies(
        projectStore: InMemoryProjectStore(),
        camera: UnimplementedCameraCapture(),
        speech: UnimplementedSpeechTranscriber(),
        scriptTracker: UnimplementedScriptTracker(),
        composer: UnimplementedMediaComposer(),
        exporter: UnimplementedVideoExporter(),
        ai: AICapabilityRouter(providers: [FoundationModelsProvider(), RemoteAIProvider()]),
        workflowRunner: WorkflowRunner(handlers: [])
    )
}
