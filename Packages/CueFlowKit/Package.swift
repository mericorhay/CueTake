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
    "CaptureEngine", "SpeechEngine", "MediaEngine", "AIServices", "Persistence", "WorkflowEngine",
    "DesignSystem", "Teleprompter",
    "LibraryFeature", "ScriptFeature", "StudioFeature", "EditorFeature", "WorkflowsFeature", "SettingsFeature",
]

func engine(_ name: String, _ dependencies: [Target.Dependency] = ["Domain"]) -> Target {
    .target(name: name, dependencies: dependencies, swiftSettings: concurrency)
}

func uiModule(_ name: String, _ dependencies: [Target.Dependency]) -> Target {
    .target(name: name, dependencies: dependencies, resources: [.process("Resources")], swiftSettings: ui)
}

let package = Package(
    name: "CueFlowKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "CueFlowKit", targets: modules),
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

        // Shared UI.
        uiModule("DesignSystem", []),
        uiModule("Teleprompter", ["Domain", "DesignSystem"]),

        // Features never import each other; the app target routes between them.
        uiModule("LibraryFeature", ["Domain", "DesignSystem", "Persistence"]),
        uiModule("ScriptFeature", ["Domain", "DesignSystem", "AIServices"]),
        uiModule("StudioFeature", ["Domain", "DesignSystem", "Teleprompter", "CaptureEngine", "SpeechEngine"]),
        uiModule("EditorFeature", ["Domain", "DesignSystem", "MediaEngine"]),
        uiModule("WorkflowsFeature", ["Domain", "DesignSystem", "WorkflowEngine"]),
        uiModule("SettingsFeature", ["Domain", "DesignSystem"]),

        .testTarget(name: "DomainTests", dependencies: ["Domain"], swiftSettings: concurrency),
        .testTarget(name: "WorkflowEngineTests", dependencies: ["Domain", "WorkflowEngine"], swiftSettings: concurrency),
    ]
)
