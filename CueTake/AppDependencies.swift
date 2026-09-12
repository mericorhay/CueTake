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
    var settingsStore: any SettingsStore
    var camera: any CameraCapturing
    var speech: any SpeechTranscribing
    var scriptTracker: any ScriptTracking
    var composer: any MediaComposing
    var exporter: any VideoExporting
    var ai: AICapabilityRouter
    var workflowRunner: WorkflowRunner

    /// Falls back to memory if Application Support cannot be opened. Losing projects is bad;
    /// refusing to launch over it is worse, and the fallback keeps the session usable.
    private static func makeProjectStore() -> any ProjectStore {
        if let store = try? FileProjectStore.inApplicationSupport() {
            return store
        }
        return InMemoryProjectStore()
    }

    /// Every engine is a placeholder until it is implemented. Storage is not.
    static let live = AppDependencies(
        projectStore: makeProjectStore(),
        settingsStore: UserDefaultsSettingsStore(),
        camera: UnimplementedCameraCapture(),
        speech: UnimplementedSpeechTranscriber(),
        scriptTracker: UnimplementedScriptTracker(),
        composer: UnimplementedMediaComposer(),
        exporter: UnimplementedVideoExporter(),
        ai: AICapabilityRouter(providers: [FoundationModelsProvider(), RemoteAIProvider()]),
        workflowRunner: WorkflowRunner(handlers: [])
    )
}
