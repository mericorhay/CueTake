import Foundation

/// Every AI feature is a separate capability. A provider implements any subset of them,
/// so on-device and remote models can split the work (e.g. on-device segmentation,
/// remote script writing) and new capabilities never touch existing ones.
public enum AICapability: String, Hashable, Sendable, Codable, CaseIterable {
    case scriptWriting
    case scriptSegmentation
    case speechAlignment
    case captionGeneration
    case videoAnalysis
    case workflowAI
}

public enum AIExecutionLocation: String, Hashable, Sendable {
    /// Apple Foundation Models. Private, free, offline; limited by device and language.
    case onDevice
    /// CueFlow's own backend. API keys live there, never in the app.
    case remote
}

public struct AIProviderDescriptor: Hashable, Sendable {
    public var id: String
    public var location: AIExecutionLocation

    public init(id: String, location: AIExecutionLocation) {
        self.id = id
        self.location = location
    }
}

public enum AIAvailability: Hashable, Sendable {
    case available
    case unavailable(AIUnavailableReason)
}

public enum AIUnavailableReason: Hashable, Sendable {
    case deviceNotEligible
    case modelNotReady
    case localeNotSupported
    case notConfigured
    case offline
    case notImplemented
}

public enum AIError: Error, Hashable, Sendable {
    case noProvider(AICapability)
    case invalidResponse
}

public protocol AIProvider: Sendable {
    var descriptor: AIProviderDescriptor { get }
    func availability(for capability: AICapability, localeIdentifier: String) async -> AIAvailability
}

/// Picks the first available provider for a capability, in preference order.
///
///     let writer = await router.provider(.scriptWriting, as: (any ScriptWriting).self, localeIdentifier: "tr-TR")
public struct AICapabilityRouter: Sendable {
    public var providers: [any AIProvider]

    public init(providers: [any AIProvider]) {
        self.providers = providers
    }

    public func provider<Capability: Sendable>(
        _ capability: AICapability,
        as _: Capability.Type,
        localeIdentifier: String
    ) async -> Capability? {
        for provider in providers {
            guard let typed = provider as? Capability else { continue }
            if await provider.availability(for: capability, localeIdentifier: localeIdentifier) == .available {
                return typed
            }
        }
        return nil
    }
}
