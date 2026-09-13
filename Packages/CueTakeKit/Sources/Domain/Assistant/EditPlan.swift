import Foundation

/// What a model sends back after reading an `EditDocument`: a short explanation and a list of
/// edits, each one small enough to show the user and to undo.
///
/// Decoding is forgiving on purpose. Models add wrapper text, invent a field, spell a number as a
/// string or send one operation the app does not know. None of those should throw away the rest of
/// a good plan, so unknown operations are kept as `.unknown` and shown as skipped.
public struct EditPlan: Codable, Sendable, Equatable {
    public var summary: String
    public var operations: [Operation]

    public init(summary: String, operations: [Operation]) {
        self.summary = summary
        self.operations = operations
    }

    public enum Operation: Sendable, Equatable {
        /// Remove footage from a clip, seconds of its own footage (the document's word times).
        case cut(clip: String, from: Double, to: Double)
        /// Remove words by their index in the clip's word list.
        case removeWords(clip: String, words: [Int])
        /// Tighten every pause longer than `minPause` (all clips when `clip` is nil).
        case trimPauses(clip: String?, minPause: Double)
        case setSpeed(clip: String, speed: Double)
        case reverse(clip: String, on: Bool)
        case freeze(clip: String, seconds: Double?)
        case deleteClip(clip: String)
        /// The clips in their new order, by id. Clips not listed keep their relative order after.
        case reorder(clips: [String])
        case setCaptionText(caption: String, text: String)
        case captionStyle(preset: String, position: Double?)
        case voiceCleanup(on: Bool)
        case setMusicLevel(audio: String, gainDb: Double)
        case unknown(type: String)

        public var type: String {
            switch self {
            case .cut: "cut"
            case .removeWords: "removeWords"
            case .trimPauses: "trimPauses"
            case .setSpeed: "setSpeed"
            case .reverse: "reverse"
            case .freeze: "freeze"
            case .deleteClip: "deleteClip"
            case .reorder: "reorder"
            case .setCaptionText: "setCaptionText"
            case .captionStyle: "captionStyle"
            case .voiceCleanup: "voiceCleanup"
            case .setMusicLevel: "setMusicLevel"
            case .unknown(let type): type
            }
        }
    }

    /// Reads a plan out of whatever the model returned: the JSON object inside it, ignoring any text
    /// around it.
    public static func decode(from text: String) throws -> EditPlan {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "no JSON object"))
        }
        return try JSONDecoder().decode(EditPlan.self, from: Data(text[open...close].utf8))
    }

    enum CodingKeys: String, CodingKey { case summary, operations }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = (try? container.decode(String.self, forKey: .summary)) ?? ""
        operations = (try? container.decode([Operation].self, forKey: .operations)) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(summary, forKey: .summary)
        try container.encode(operations, forKey: .operations)
    }
}

extension EditPlan.Operation: Codable {
    private enum Keys: String, CodingKey {
        case op, clip, from, to, words, minPause, speed, on, seconds, clips, caption, text, preset, position, audio, gainDb
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let op = (try? c.decode(String.self, forKey: .op)) ?? "unknown"

        func string(_ key: Keys) -> String? { try? c.decode(String.self, forKey: key) }
        func number(_ key: Keys) -> Double? {
            if let value = try? c.decode(Double.self, forKey: key) { return value }
            return string(key).flatMap(Double.init)
        }
        func flag(_ key: Keys) -> Bool? {
            if let value = try? c.decode(Bool.self, forKey: key) { return value }
            return string(key).map { $0 == "true" }
        }

        switch op {
        case "cut":
            guard let clip = string(.clip), let from = number(.from), let to = number(.to), to > from else {
                self = .unknown(type: op); return
            }
            self = .cut(clip: clip, from: from, to: to)
        case "removeWords":
            guard let clip = string(.clip), let words = try? c.decode([Int].self, forKey: .words) else {
                self = .unknown(type: op); return
            }
            self = .removeWords(clip: clip, words: words)
        case "trimPauses":
            self = .trimPauses(clip: string(.clip), minPause: number(.minPause) ?? 0.6)
        case "setSpeed":
            guard let clip = string(.clip), let speed = number(.speed) else { self = .unknown(type: op); return }
            self = .setSpeed(clip: clip, speed: speed)
        case "reverse":
            guard let clip = string(.clip) else { self = .unknown(type: op); return }
            self = .reverse(clip: clip, on: flag(.on) ?? true)
        case "freeze":
            guard let clip = string(.clip) else { self = .unknown(type: op); return }
            self = .freeze(clip: clip, seconds: number(.seconds))
        case "deleteClip":
            guard let clip = string(.clip) else { self = .unknown(type: op); return }
            self = .deleteClip(clip: clip)
        case "reorder":
            guard let clips = try? c.decode([String].self, forKey: .clips) else { self = .unknown(type: op); return }
            self = .reorder(clips: clips)
        case "setCaptionText":
            guard let caption = string(.caption), let text = string(.text) else { self = .unknown(type: op); return }
            self = .setCaptionText(caption: caption, text: text)
        case "captionStyle":
            guard let preset = string(.preset) else { self = .unknown(type: op); return }
            self = .captionStyle(preset: preset, position: number(.position))
        case "voiceCleanup":
            self = .voiceCleanup(on: flag(.on) ?? true)
        case "setMusicLevel":
            guard let audio = string(.audio), let gain = number(.gainDb) else { self = .unknown(type: op); return }
            self = .setMusicLevel(audio: audio, gainDb: gain)
        default:
            self = .unknown(type: op)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(type, forKey: .op)
        switch self {
        case .cut(let clip, let from, let to):
            try c.encode(clip, forKey: .clip); try c.encode(from, forKey: .from); try c.encode(to, forKey: .to)
        case .removeWords(let clip, let words):
            try c.encode(clip, forKey: .clip); try c.encode(words, forKey: .words)
        case .trimPauses(let clip, let minPause):
            try c.encodeIfPresent(clip, forKey: .clip); try c.encode(minPause, forKey: .minPause)
        case .setSpeed(let clip, let speed):
            try c.encode(clip, forKey: .clip); try c.encode(speed, forKey: .speed)
        case .reverse(let clip, let on):
            try c.encode(clip, forKey: .clip); try c.encode(on, forKey: .on)
        case .freeze(let clip, let seconds):
            try c.encode(clip, forKey: .clip); try c.encodeIfPresent(seconds, forKey: .seconds)
        case .deleteClip(let clip):
            try c.encode(clip, forKey: .clip)
        case .reorder(let clips):
            try c.encode(clips, forKey: .clips)
        case .setCaptionText(let caption, let text):
            try c.encode(caption, forKey: .caption); try c.encode(text, forKey: .text)
        case .captionStyle(let preset, let position):
            try c.encode(preset, forKey: .preset); try c.encodeIfPresent(position, forKey: .position)
        case .voiceCleanup(let on):
            try c.encode(on, forKey: .on)
        case .setMusicLevel(let audio, let gain):
            try c.encode(audio, forKey: .audio); try c.encode(gain, forKey: .gainDb)
        case .unknown:
            break
        }
    }
}
