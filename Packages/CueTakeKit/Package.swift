// swift-tools-version: 6.2
import PackageDescription

// Swift 6 language mode is the default for tools 6.x.
// Domain and engines stay nonisolated; UI modules default to the main actor.
let concurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]
let ui: [SwiftSetting] = concurrency + [.defaultIsolation(MainActor.self)]

let modules: [String] = [
    "Domain",
    "CaptureEngine", "SpeechEngine", "MediaEngine", "AIServices", "Persistence", "WorkflowEngine", "GenerationEngine", "TeamSync",
    "DesignSystem", "Teleprompter", "BumpKit",
    "OnboardingFeature", "LibraryFeature", "ScriptFeature", "StudioFeature", "EditorFeature", "WorkflowsFeature", "SettingsFeature", "AssistantFeature", "TeamFeature",
]

func engine(_ name: String, _ dependencies: [Target.Dependency] = ["Domain"]) -> Target {
    .target(name: name, dependencies: dependencies, swiftSettings: concurrency)
}

func uiModule(_ name: String, _ dependencies: [Target.Dependency]) -> Target {
    .target(name: name, dependencies: dependencies, resources: [.process("Resources")], swiftSettings: ui)
}

let package = Package(
    name: "CueTakeKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "CueTakeKit", targets: modules),
    ],
    targets: [
        // Pure models and pure logic. Foundation only.
        engine("Domain", []),

        // Capabilities. No SwiftUI, no dependencies on each other.
        engine("CaptureEngine"),
        engine("SpeechEngine"),
        engine("MediaEngine"),
        engine("AIServices"),
        engine("Persistence"),
        engine("WorkflowEngine"),
        // Video models on the user's own keys: fal, Veo, Sora, Replicate.
        engine("GenerationEngine"),
        // Shared team projects through iCloud: no server of ours. Compiled always, started only
        // in builds that carry the iCloud entitlement.
        engine("TeamSync", ["Domain", "Persistence"]),

        // Shared UI.
        uiModule("DesignSystem", []),
        uiModule("Teleprompter", ["Domain", "DesignSystem"]),
        // The light two phones make when they touch. No dependencies, and nothing depends on it
        // but the screen that shows it: the showiest code in the app must not be able to break
        // anything else.
        .target(name: "BumpKit", swiftSettings: ui),

        // Features never import each other; the app target routes between them.
        uiModule("OnboardingFeature", ["DesignSystem"]),
        uiModule("LibraryFeature", ["Domain", "DesignSystem", "Persistence"]),
        uiModule("ScriptFeature", ["Domain", "DesignSystem", "AIServices"]),
        uiModule("StudioFeature", ["Domain", "DesignSystem", "Teleprompter", "CaptureEngine", "SpeechEngine"]),
        uiModule("EditorFeature", ["Domain", "DesignSystem", "MediaEngine"]),
        uiModule("WorkflowsFeature", ["Domain", "DesignSystem", "WorkflowEngine", "Persistence"]),
        // MediaEngine for the format converter, which is the one piece of Settings that does
        // real work to a file.
        uiModule("AssistantFeature", ["Domain", "DesignSystem"]),
        // Teams: making one, joining one, and the light that plays when two phones meet.
        uiModule("TeamFeature", ["Domain", "DesignSystem", "BumpKit"]),
        uiModule("SettingsFeature", ["Domain", "DesignSystem", "Persistence", "MediaEngine", "GenerationEngine"]),

        .testTarget(name: "DomainTests", dependencies: ["Domain"], swiftSettings: concurrency),
        .testTarget(name: "WorkflowEngineTests", dependencies: ["Domain", "WorkflowEngine"], swiftSettings: concurrency),
        .testTarget(name: "GenerationEngineTests", dependencies: ["Domain", "GenerationEngine"], swiftSettings: concurrency),
        .testTarget(name: "MediaEngineTests", dependencies: ["Domain", "MediaEngine"], swiftSettings: concurrency),
        .testTarget(name: "PersistenceTests", dependencies: ["Domain", "Persistence"], swiftSettings: concurrency),
        .testTarget(name: "TeamSyncTests", dependencies: ["Domain", "Persistence", "TeamSync"], swiftSettings: concurrency),
        .testTarget(name: "EditorFeatureTests", dependencies: ["Domain", "EditorFeature"], swiftSettings: ui),
    ]
)
