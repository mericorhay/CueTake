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
    /// The language CueTake uses. Automatic follows the phone; an explicit choice updates the
    /// whole view tree immediately and is also used by programmatic status and error copy.
    public var language: AppLanguage
    /// Whether new projects start with the look of the last one: caption style and position, and
    /// voice cleanup. On by default — a creator's second video almost always looks like their first.
    public var remembersStyle: Bool
    /// Where captions sat last time. Nil until someone has placed them.
    public var captionPosition: CaptionPosition?
    /// The voice cleanup used last time.
    public var voiceEffects: AudioEffects
    /// Whether the intro has been seen. Not a preference, but a second store and a second file
    /// for one Bool is worse than the small impurity of keeping it here.
    public var hasCompletedOnboarding: Bool

    public init(
        defaultCamera: CameraPosition = .front,
        captureResolution: VideoFormat.Resolution = .hd1080,
        captionPreset: CaptionPreference = .pop,
        aiProcessing: AIProcessing = .onDeviceOnly,
        exportDestination: ExportDestination = .photoLibrary,
        language: AppLanguage = .automatic,
        remembersStyle: Bool = true,
        captionPosition: CaptionPosition? = nil,
        voiceEffects: AudioEffects = AudioEffects(),
        hasCompletedOnboarding: Bool = false
    ) {
        self.remembersStyle = remembersStyle
        self.captionPosition = captionPosition
        self.voiceEffects = voiceEffects
        self.defaultCamera = defaultCamera
        self.captureResolution = captureResolution
        self.captionPreset = captionPreset
        self.aiProcessing = aiProcessing
        self.exportDestination = exportDestination
        self.language = language
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
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? fallback.language
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? fallback.hasCompletedOnboarding
        remembersStyle = try container.decodeIfPresent(Bool.self, forKey: .remembersStyle) ?? fallback.remembersStyle
        captionPosition = try container.decodeIfPresent(CaptionPosition.self, forKey: .captionPosition)
        voiceEffects = try container.decodeIfPresent(AudioEffects.self, forKey: .voiceEffects) ?? fallback.voiceEffects
    }
}

public enum AppLanguage: String, Hashable, Sendable, Codable, CaseIterable {
    case automatic
    case english = "en"
    case spanish = "es"
    case turkish = "tr"

    public var localeIdentifier: String? {
        switch self {
        case .automatic: nil
        case .english: "en"
        case .spanish: "es"
        case .turkish: "tr"
        }
    }

    public var locale: Locale {
        localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }
}

public enum CaptionPreference: String, Hashable, Sendable, Codable, CaseIterable {
    case off
    case pop
    case clean
    case karaoke
    case bold
    case boxed
    case minimal
    case neon
    case story

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

extension AppSettings {
    /// The look a new project starts with.
    public var startingCaptionStyle: CaptionStyle {
        let preset = captionPreset == .off ? "pop" : captionPreset.rawValue
        return CaptionStyle.preset(preset, position: remembersStyle ? (captionPosition ?? .lowerThird) : .lowerThird)
    }

    /// Everything a new project takes from Settings. The recording quality applies whether or not
    /// the look is remembered: it was chosen once, on purpose, and the studio records whatever
    /// the project's format says — before this the picker changed nothing at all.
    public func applyNewProjectDefaults(to project: inout Project) {
        project.format.resolution = captureResolution
        applyStyle(to: &project)
    }

    /// Gives a new project the remembered look. Does nothing when remembering is off.
    public func applyStyle(to project: inout Project) {
        guard remembersStyle else { return }
        project.captionStyle = startingCaptionStyle
        project.voiceEffects = voiceEffects
    }
}
