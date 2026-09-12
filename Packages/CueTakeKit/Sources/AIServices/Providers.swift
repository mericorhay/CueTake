import Foundation

/// Apple Foundation Models (on-device). Will adopt capability protocols as they are implemented;
/// structured output via `@Generable` maps directly onto `ScriptDraft`.
public struct FoundationModelsProvider: AIProvider {
    public let descriptor = AIProviderDescriptor(id: "apple.foundation-models", location: .onDevice)

    public init() {}

    public func availability(for capability: AICapability, localeIdentifier: String) async -> AIAvailability {
        .unavailable(.notImplemented)
    }
}

/// CueTake backend. The app talks only to our server, which holds third-party model keys.
public struct RemoteAIProvider: AIProvider {
    public let descriptor = AIProviderDescriptor(id: "cuetake.remote", location: .remote)
    public let baseURL: URL?

    public init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    public func availability(for capability: AICapability, localeIdentifier: String) async -> AIAvailability {
        baseURL == nil ? .unavailable(.notConfigured) : .unavailable(.notImplemented)
    }
}
