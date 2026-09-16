import Foundation

/// A service that makes video from text or a picture, reached with the user's own API key.
///
/// The key belongs to the user and stays on their phone; requests go straight from the phone to
/// the provider. Adding a provider is a case here and a generator in `GenerationEngine`.
public enum GenerationProviderID: String, CaseIterable, Hashable, Sendable, Codable, Identifiable {
    /// fal.ai: one key for hundreds of models (Seedance, Kling, Veo, Wan, Hailuo…).
    case fal
    /// Google Gemini API: Veo.
    case google
    /// OpenAI: Sora.
    case openai
    /// Replicate: one key for any public model.
    case replicate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fal: "fal.ai"
        case .google: "Google Gemini (Veo)"
        case .openai: "OpenAI (Sora)"
        case .replicate: "Replicate"
        }
    }

    /// Where the user gets a key.
    public var keyPage: URL {
        switch self {
        case .fal: URL(string: "https://fal.ai/dashboard/keys")!
        case .google: URL(string: "https://aistudio.google.com/apikey")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        case .replicate: URL(string: "https://replicate.com/account/api-tokens")!
        }
    }

    /// What a key usually looks like, as a hint in the field.
    public var keyHint: String {
        switch self {
        case .fal: "xxxxxxxx-xxxx-…:xxxxxxxx"
        case .google: "AIza…"
        case .openai: "sk-…"
        case .replicate: "r8_…"
        }
    }

    /// True when the provider serves any model by its id, not only its own.
    public var acceptsAnyModel: Bool { self == .fal || self == .replicate }
}

/// A ready-made choice of model, with what it can do. `custom` presets take a model id.
public struct VideoModelPreset: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var provider: GenerationProviderID
    /// The provider's model id; empty for a custom preset.
    public var model: String
    /// The model id used when a starting picture is given, when the provider splits them.
    public var imageModel: String?
    /// Seconds the model accepts. Requests are rounded to the nearest.
    public var durations: [Double]
    public var aspects: [String]
    public var resolutions: [String]
    /// Makes its own synchronized sound.
    public var makesAudio: Bool
    public var acceptsImage: Bool
    public var isCustom: Bool

    public init(
        id: String,
        title: String,
        provider: GenerationProviderID,
        model: String,
        imageModel: String? = nil,
        durations: [Double],
        aspects: [String],
        resolutions: [String],
        makesAudio: Bool,
        acceptsImage: Bool,
        isCustom: Bool = false
    ) {
        self.id = id
        self.title = title
        self.provider = provider
        self.model = model
        self.imageModel = imageModel
        self.durations = durations
        self.aspects = aspects
        self.resolutions = resolutions
        self.makesAudio = makesAudio
        self.acceptsImage = acceptsImage
        self.isCustom = isCustom
    }

    public static let catalog: [VideoModelPreset] = [
        VideoModelPreset(
            id: "seedance-2.5", title: "Seedance 2.5", provider: .fal,
            model: "bytedance/seedance-2.5/text-to-video",
            imageModel: "bytedance/seedance-2.5/image-to-video",
            durations: Array(stride(from: 4.0, through: 30.0, by: 1.0)),
            aspects: ["9:16", "16:9", "1:1", "4:3", "3:4", "21:9"],
            resolutions: ["480p", "720p", "1080p"],
            makesAudio: true, acceptsImage: true
        ),
        VideoModelPreset(
            id: "veo-3.1", title: "Veo 3.1", provider: .google,
            model: "veo-3.1-generate-preview",
            durations: [4, 6, 8], aspects: ["9:16", "16:9"], resolutions: ["720p", "1080p"],
            makesAudio: true, acceptsImage: true
        ),
        VideoModelPreset(
            id: "veo-3.1-fast", title: "Veo 3.1 Fast", provider: .google,
            model: "veo-3.1-fast-generate-preview",
            durations: [4, 6, 8], aspects: ["9:16", "16:9"], resolutions: ["720p", "1080p"],
            makesAudio: true, acceptsImage: true
        ),
        VideoModelPreset(
            id: "veo-3.1-lite", title: "Veo 3.1 Lite", provider: .google,
            model: "veo-3.1-lite-generate-preview",
            durations: [4, 6, 8], aspects: ["9:16", "16:9"], resolutions: ["720p"],
            makesAudio: true, acceptsImage: true
        ),
        VideoModelPreset(
            id: "sora-2", title: "Sora 2", provider: .openai,
            model: "sora-2",
            durations: [4, 8, 12], aspects: ["9:16", "16:9"], resolutions: ["720p"],
            makesAudio: true, acceptsImage: true
        ),
        VideoModelPreset(
            id: "sora-2-pro", title: "Sora 2 Pro", provider: .openai,
            model: "sora-2-pro",
            durations: [4, 8, 12], aspects: ["9:16", "16:9"], resolutions: ["720p", "1080p"],
            makesAudio: true, acceptsImage: true
        ),
        VideoModelPreset(
            id: "fal-custom", title: "fal.ai · any model", provider: .fal,
            model: "",
            durations: Array(stride(from: 3.0, through: 30.0, by: 1.0)),
            aspects: ["9:16", "16:9", "1:1"], resolutions: ["720p", "1080p"],
            makesAudio: false, acceptsImage: true, isCustom: true
        ),
        VideoModelPreset(
            id: "replicate-custom", title: "Replicate · any model", provider: .replicate,
            model: "",
            durations: Array(stride(from: 3.0, through: 30.0, by: 1.0)),
            aspects: ["9:16", "16:9", "1:1"], resolutions: ["720p", "1080p"],
            makesAudio: false, acceptsImage: true, isCustom: true
        ),
    ]

    public static func preset(id: String) -> VideoModelPreset {
        catalog.first { $0.id == id } ?? catalog[0]
    }

    /// The accepted length nearest to the one asked for.
    public func duration(nearest seconds: Double) -> Double {
        durations.min { abs($0 - seconds) < abs($1 - seconds) } ?? seconds
    }

    public func aspect(nearest wanted: String) -> String {
        if aspects.contains(wanted) { return wanted }
        let ratio = Self.ratio(wanted)
        return aspects.min { abs(Self.ratio($0) - ratio) < abs(Self.ratio($1) - ratio) } ?? wanted
    }

    public func resolution(nearest wanted: String) -> String {
        resolutions.contains(wanted) ? wanted : (resolutions.last { Self.lines($0) <= Self.lines(wanted) } ?? resolutions.first ?? wanted)
    }

    public static func ratio(_ text: String) -> Double {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[1] > 0 else { return 9.0 / 16.0 }
        return parts[0] / parts[1]
    }

    /// Picture height from a name: `720p` is 720, `4k` is 2160.
    public static func lines(_ text: String) -> Int {
        let number = Int(text.filter(\.isNumber)) ?? 720
        return text.lowercased().hasSuffix("k") ? number * 540 : number
    }
}

/// The "Generate video" workflow step: one video per prompt, made by the chosen model.
public struct GenerateVideoOptions: Hashable, Sendable, Codable {
    /// A `VideoModelPreset` id.
    public var preset: String
    /// The provider's model id, for the custom presets.
    public var customModel: String
    /// One video per line. Empty uses each section's title and script instead.
    public var prompts: [String]
    /// Added to every prompt: the look all the videos share.
    public var styleNote: String
    public var seconds: Double
    public var aspect: String
    public var resolution: String
    /// Ask for the model's own sound when it can make it.
    public var audio: Bool
    /// How many videos are made at the same time.
    public var parallel: Int

    public init(
        preset: String = "seedance-2.5",
        customModel: String = "",
        prompts: [String] = [],
        styleNote: String = "",
        seconds: Double = 8,
        aspect: String = "9:16",
        resolution: String = "720p",
        audio: Bool = true,
        parallel: Int = 3
    ) {
        self.preset = preset
        self.customModel = customModel
        self.prompts = prompts
        self.styleNote = styleNote
        self.seconds = seconds
        self.aspect = aspect
        self.resolution = resolution
        self.audio = audio
        self.parallel = parallel
    }

    private enum CodingKeys: String, CodingKey {
        case preset, model, customModel, prompts, prompt, styleNote, style, seconds, duration, aspect, resolution, audio, parallel
    }

    /// Forgiving: a model writing `{"model": "veo-3.1", "prompt": "…", "duration": 8}` is understood.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = GenerateVideoOptions()
        func text(_ key: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: key) }
        func number(_ key: CodingKeys) -> Double? {
            (try? c.decodeIfPresent(Double.self, forKey: key)) ?? text(key).flatMap { Double($0) }
        }
        let named = text(.preset) ?? text(.model)
        if let named, VideoModelPreset.catalog.contains(where: { $0.id == named }) {
            preset = named
            customModel = text(.customModel) ?? ""
        } else if let named, named.contains("/") {
            // A provider model id, such as fal's `fal-ai/kling-video/...`.
            preset = "fal-custom"
            customModel = named
        } else {
            preset = fallback.preset
            customModel = text(.customModel) ?? ""
        }
        var list = (try? c.decodeIfPresent([String].self, forKey: .prompts)) ?? []
        if list.isEmpty, let single = text(.prompt) { list = [single] }
        prompts = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        styleNote = text(.styleNote) ?? text(.style) ?? ""
        seconds = number(.seconds) ?? number(.duration) ?? fallback.seconds
        aspect = text(.aspect) ?? fallback.aspect
        resolution = text(.resolution) ?? fallback.resolution
        audio = (try? c.decodeIfPresent(Bool.self, forKey: .audio)) ?? fallback.audio
        let wanted = (try? c.decodeIfPresent(Int.self, forKey: .parallel)) ?? fallback.parallel
        parallel = min(max(wanted, 1), 6)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(preset, forKey: .preset)
        if !customModel.isEmpty { try c.encode(customModel, forKey: .customModel) }
        try c.encode(prompts, forKey: .prompts)
        if !styleNote.isEmpty { try c.encode(styleNote, forKey: .styleNote) }
        try c.encode(seconds, forKey: .seconds)
        try c.encode(aspect, forKey: .aspect)
        try c.encode(resolution, forKey: .resolution)
        try c.encode(audio, forKey: .audio)
        try c.encode(parallel, forKey: .parallel)
    }

    public var modelPreset: VideoModelPreset { VideoModelPreset.preset(id: preset) }

    /// The provider's model id this step will call.
    public var resolvedModel: String {
        let base = modelPreset
        return base.isCustom ? customModel.trimmingCharacters(in: .whitespacesAndNewlines) : base.model
    }

    /// The prompt as sent: the line, then the shared style.
    public func fullPrompt(_ line: String) -> String {
        let note = styleNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? line : "\(line)\n\(note)"
    }
}
