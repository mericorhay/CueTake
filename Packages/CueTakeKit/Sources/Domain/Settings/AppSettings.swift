import Foundation

/// User preferences that outlive a project.
///
/// Deliberately small: a setting earns a place here only when something reads it. Options for
/// engines that do not exist yet would be a promise the app cannot keep, and a settings screen
/// full of switches that change nothing is worse than one with five that do.
///
/// Decoding is lenient on purpose — every field falls back to its default, so adding a setting
/// later never invalidates what is already on disk and never needs a migration.
public struct AppSettings: Hashable, Sendable, Codable {
    /// Which camera a new recording starts on.
    public var defaultCamera: CameraPosition
    /// Capture resolution. Frame rate stays with the format the project was created at.
    public var captureResolution: VideoFormat.Resolution
    /// Off means captions are never generated; otherwise this is the preset new cues start from.
    public var captionPreset: CaptionPreference
    /// Whether work may leave the device when an on-device model cannot do the job.
    public var aiProcessing: AIProcessing
    /// Where a finished video is written.
    public var exportDestination: ExportDestination
    /// Whether the intro has been seen. Not a preference, but a second store and a second file
    /// for one Bool is worse than the small impurity of keeping it here.
    public var hasCompletedOnboarding: Bool

    public init(
        defaultCamera: CameraPosition = .front,
        captureResolution: VideoFormat.Resolution = .hd1080,
        captionPreset: CaptionPreference = .pop,
        aiProcessing: AIProcessing = .onDeviceOnly,
        exportDestination: ExportDestination = .photoLibrary,
        hasCompletedOnboarding: Bool = false
    ) {
        self.defaultCamera = defaultCamera
        self.captureResolution = captureResolution
        self.captionPreset = captionPreset
        self.aiProcessing = aiProcessing
        self.exportDestination = exportDestination
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public static let `default` = AppSettings()

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings.default
        defaultCamera = try container.decodeIfPresent(CameraPosition.self, forKey: .defaultCamera) ?? fallback.defaultCamera
        captureResolution = try container.decodeIfPresent(VideoFormat.Resolution.self, forKey: .captureResolution) ?? fallback.captureResolution
        captionPreset = try container.decodeIfPresent(CaptionPreference.self, forKey: .captionPreset) ?? fallback.captionPreset
        aiProcessing = try container.decodeIfPresent(AIProcessing.self, forKey: .aiProcessing) ?? fallback.aiProcessing
        exportDestination = try container.decodeIfPresent(ExportDestination.self, forKey: .exportDestination) ?? fallback.exportDestination
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? fallback.hasCompletedOnboarding
    }
}

public enum CaptionPreference: String, Hashable, Sendable, Codable, CaseIterable {
    case off
    case pop
    case clean
    case karaoke

    public var isEnabled: Bool { self != .off }
}

public enum AIProcessing: String, Hashable, Sendable, Codable, CaseIterable {
    /// Refuse anything the on-device models cannot do, rather than sending it away.
    case onDeviceOnly
    case allowCloud
}

extension CameraPosition: CaseIterable {
    public static var allCases: [CameraPosition] { [.front, .back] }
}

extension ExportDestination: CaseIterable {
    public static var allCases: [ExportDestination] { [.photoLibrary, .files] }
}
