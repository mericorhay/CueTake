import AIServices
import Persistence
import SpeechEngine

/// Composition root: the only place that knows concrete implementations.
/// Features receive the protocols they need through their initializers; there is no global container.
struct AppDependencies {
    var projectStore: any ProjectStore
    var settingsStore: any SettingsStore
    var speech: any SpeechTranscribing
    var ai: AICapabilityRouter
    /// Nil only when Application Support cannot be opened, in which case workflows live for the
    /// session and the studio still works.
    var workflowStore: WorkflowStore?
    var workflowAuthor: FoundationModelsWorkflowAuthor
    var assistantStore: AssistantStore?
    var assistantClient: AssistantClient

    /// Falls back to memory if Application Support cannot be opened. Losing projects is bad;
    /// refusing to launch over it is worse, and the fallback keeps the session usable.
    private static func makeProjectStore() -> any ProjectStore {
        if let store = try? FileProjectStore.inApplicationSupport() {
            return store
        }
        return InMemoryProjectStore()
    }

    /// The concrete capabilities the app runs on. Placeholders that used to stand here for engines
    /// not yet built are gone: the camera, composer and exporter are used directly by the features
    /// that own them, and a dependency nothing reads is a dependency that lies about the design.
    static let live = AppDependencies(
        projectStore: makeProjectStore(),
        settingsStore: UserDefaultsSettingsStore(),
        speech: SystemSpeechTranscriber(),
        ai: AICapabilityRouter(providers: [FoundationModelsScriptWriter(), RemoteAIProvider()]),
        workflowStore: try? WorkflowStore.inApplicationSupport(),
        workflowAuthor: FoundationModelsWorkflowAuthor(),
        assistantStore: try? AssistantStore.inApplicationSupport(),
        assistantClient: AssistantClient.bundled()
    )
}
