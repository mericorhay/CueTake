import Foundation

/// What a model sends back after reading an `EditDocument`: a short explanation and a list of
/// edits, each one small enough to show the user and to undo.
///
/// The vocabulary covers the whole studio — footage, speed, order, every caption and its timing,
/// the caption look down to colour and size, the window captions show in, text over the picture,
/// sound levels and fades, voice repair, the title. Anything a person can do with the editor's
/// controls, a plan can ask for; nothing a person could not do is in here.
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
        // Footage
        /// Remove footage from a clip, seconds of its own footage (the document's word times).
        case cut(clip: String, from: Double, to: Double)
        /// Remove words by their index in the clip's word list.
        case removeWords(clip: String, words: [Int])
        /// Tighten every pause longer than `minPause` (all clips when `clip` is nil).
        case trimPauses(clip: String?, minPause: Double)
        /// Keep only `start…end` of the clip's footage. Either side nil leaves that end alone.
        case trimClip(clip: String, start: Double?, end: Double?)
        /// Cut the clip in two at a second of its footage.
        case splitClip(clip: String, at: Double)
        case duplicateClip(clip: String)
        case deleteClip(clip: String)
        /// The clips in their new order, by id. Clips not listed keep their relative order after.
        case reorder(clips: [String])

        // Playback
        case setSpeed(clip: String, speed: Double)
        case reverse(clip: String, on: Bool)

        // Captions
        case setCaptionText(caption: String, text: String)
        /// New start and end for one caption, in seconds of its clip's footage.
        case captionTiming(caption: String, start: Double?, end: Double?)
        case splitCaption(caption: String)
        case mergeCaption(caption: String)
        case removeCaption(caption: String)
        case captionStyle(preset: String, position: Double?)
        /// Any part of the caption look.
        case captionLook(CaptionLook)
        /// Captions only between two moments of the finished video; both nil shows them throughout.
        case captionWindow(from: Double?, to: Double?)

        // Text over the picture
        case addText(OverlayPatch)
        case updateOverlay(overlay: String, patch: OverlayPatch)
        case removeOverlay(overlay: String)

        // Sound
        case setMusicLevel(audio: String, gainDb: Double)
        case updateAudio(audio: String, patch: AudioPatch)
        case removeAudio(audio: String)
        case voiceCleanup(on: Bool)
        case voiceEffects(noiseReduction: Bool?, voiceEnhance: Bool?, deRumble: Bool?)

        // Project
        case setTitle(String)

        // Only the AI has these
        /// Names a clip (what the timeline and the inspector call it).
        case renameClip(clip: String, title: String)
        /// Assigns the clip's editorial role: hook, intro, point, example or cta.
        case setRole(clip: String, role: String)
        /// Rewrites what the prompter shows for a clip.
        case setScript(clip: String, text: String)
        /// Uses another recorded attempt for a clip.
        case selectTake(clip: String, take: String)
        /// Copies a text or picture to another moment.
        case duplicateOverlay(overlay: String, start: Double?)
        /// Moves every caption of one clip (or all clips) earlier or later, for captions out of sync.
        case shiftCaptions(clip: String?, by: Double)
        /// Replaces what is behind the person over a stretch of the video; no style takes it away.
        case setBackground(BackgroundRequest)
        /// Removes a tool laid over a stretch of the video.
        case removeEffect(effect: String)
        /// Lays or changes a colour look.
        case setFilter(FilterRequest)
        /// Lays or changes a sound effect on the voice.
        case setSound(SoundRequest)
        /// Moves or stretches any effect: new start and end on the finished video.
        case retimeEffect(effect: String, from: Double?, to: Double?)
        /// Cuts an effect in two at a moment of the finished video.
        case splitEffect(effect: String, at: Double)
        /// Changes an added video: when, which part, where, how loud.
        case updateVideo(video: String, patch: VideoPatch)
        /// Makes an added video move: its place at a moment of the finished video.
        case keyframeVideo(video: String, at: Double, patch: VideoPatch)
        /// Arranges the main video and the added ones: sideBySide, stacked, pictureInPicture, grid.
        case layoutVideos(layout: String)
        case removeVideo(video: String)
        case splitVideo(video: String, at: Double)
        /// Cuts a text or picture in two at a moment of the finished video.
        case splitOverlay(overlay: String, at: Double)
        /// The main video's own level, 0…1.
        case mainVolume(Double)
        /// Which listener's words a clip (or every clip) uses: device or cloud.
        case useTranscript(clip: String?, source: String)
        /// Lays a camera move over a stretch of the finished video, or changes one (`move`).
        case cameraMove(CameraMoveRequest)
        case removeCameraMove(move: String)
        /// Follows the speaker's face in a clip (every clip when nil); `closeness` is how much
        /// closer the framing gets, which is what gives the camera room to follow.
        case trackFace(clip: String?, closeness: Double?)
        /// Stops following in a clip (every clip when nil).
        case removeTrack(clip: String?)
        /// Makes a video with the user's video model and lays it in: over the video (B-roll) or
        /// as a clip, at a moment of the finished video.
        case generateVideo(GenerateClipRequest)
        /// A transition out of a clip (every cut when nil): crossfade, fadeBlack, slideLeft…
        case transition(clip: String?, kind: String, seconds: Double?)
        case removeTransition(clip: String?)

        case unknown(type: String)

        public var type: String {
            switch self {
            case .cut: "cut"
            case .removeWords: "removeWords"
            case .trimPauses: "trimPauses"
            case .trimClip: "trimClip"
            case .splitClip: "splitClip"
            case .duplicateClip: "duplicateClip"
            case .deleteClip: "deleteClip"
            case .reorder: "reorder"
            case .setSpeed: "setSpeed"
            case .reverse: "reverse"
            case .setCaptionText: "setCaptionText"
            case .captionTiming: "captionTiming"
            case .splitCaption: "splitCaption"
            case .mergeCaption: "mergeCaption"
            case .removeCaption: "removeCaption"
            case .captionStyle: "captionStyle"
            case .captionLook: "captionLook"
            case .captionWindow: "captionWindow"
            case .addText: "addText"
            case .updateOverlay: "updateOverlay"
            case .removeOverlay: "removeOverlay"
            case .setMusicLevel: "setMusicLevel"
            case .updateAudio: "updateAudio"
            case .removeAudio: "removeAudio"
            case .voiceCleanup: "voiceCleanup"
            case .voiceEffects: "voiceEffects"
            case .setTitle: "setTitle"
            case .renameClip: "renameClip"
            case .setRole: "setRole"
            case .setScript: "setScript"
            case .selectTake: "selectTake"
            case .duplicateOverlay: "duplicateOverlay"
            case .shiftCaptions: "shiftCaptions"
            case .setBackground: "setBackground"
            case .removeEffect: "removeEffect"
            case .setFilter: "setFilter"
            case .setSound: "setSound"
            case .retimeEffect: "retimeEffect"
            case .splitEffect: "splitEffect"
            case .updateVideo: "updateVideo"
            case .keyframeVideo: "keyframeVideo"
            case .layoutVideos: "layoutVideos"
            case .removeVideo: "removeVideo"
            case .splitVideo: "splitVideo"
            case .splitOverlay: "splitOverlay"
            case .mainVolume: "mainVolume"
            case .useTranscript: "useTranscript"
            case .cameraMove: "cameraMove"
            case .removeCameraMove: "removeCameraMove"
            case .trackFace: "trackFace"
            case .removeTrack: "removeTrack"
            case .generateVideo: "generateVideo"
            case .transition: "transition"
            case .removeTransition: "removeTransition"
            case .unknown(let type): type
            }
        }
    }

    /// Parts of the caption look to change. Nil leaves a part as it is. Colours are `#RRGGBB` or
    /// `#RRGGBBAA`; `"none"` removes a highlight or a plate.
    public struct CaptionLook: Sendable, Equatable {
        public var preset: String?
        public var size: Double?
        public var maxWords: Int?
        public var textCase: String?
        public var textColor: String?
        public var highlightColor: String?
        public var backgroundColor: String?
        public var font: String?
        /// 0 top … 1 bottom.
        public var position: Double?

        public init(
            preset: String? = nil, size: Double? = nil, maxWords: Int? = nil, textCase: String? = nil,
            textColor: String? = nil, highlightColor: String? = nil, backgroundColor: String? = nil,
            font: String? = nil, position: Double? = nil
        ) {
            self.preset = preset
            self.size = size
            self.maxWords = maxWords
            self.textCase = textCase
            self.textColor = textColor
            self.highlightColor = highlightColor
            self.backgroundColor = backgroundColor
            self.font = font
            self.position = position
        }
    }

    /// Parts of a text or picture overlay. Times are seconds of the finished video; geometry is a
    /// fraction of the frame, as in the document.
    public struct OverlayPatch: Sendable, Equatable {
        public var text: String?
        public var start: Double?
        public var duration: Double?
        public var end: Double?
        public var x: Double?
        public var y: Double?
        public var scale: Double?
        public var rotation: Double?
        public var opacity: Double?
        public var flipX: Bool?
        public var flipY: Bool?
        public var color: String?
        public var background: String?
        public var font: String?
        public var animation: String?
        /// Behind the people in the picture, or back in front of them.
        public var behind: Bool?

        public init(
            text: String? = nil, start: Double? = nil, duration: Double? = nil, end: Double? = nil,
            x: Double? = nil, y: Double? = nil, scale: Double? = nil, rotation: Double? = nil,
            opacity: Double? = nil, flipX: Bool? = nil, flipY: Bool? = nil, color: String? = nil,
            background: String? = nil, font: String? = nil, animation: String? = nil, behind: Bool? = nil
        ) {
            self.behind = behind
            self.text = text
            self.start = start
            self.duration = duration
            self.end = end
            self.x = x
            self.y = y
            self.scale = scale
            self.rotation = rotation
            self.opacity = opacity
            self.flipX = flipX
            self.flipY = flipY
            self.color = color
            self.background = background
            self.font = font
            self.animation = animation
        }
    }

    public struct AudioPatch: Sendable, Equatable {
        public var gainDb: Double?
        public var fadeIn: Double?
        public var fadeOut: Double?
        public var start: Double?
        public var muted: Bool?
        public var ducksUnderVoice: Bool?

        public init(
            gainDb: Double? = nil, fadeIn: Double? = nil, fadeOut: Double? = nil,
            start: Double? = nil, muted: Bool? = nil, ducksUnderVoice: Bool? = nil
        ) {
            self.gainDb = gainDb
            self.fadeIn = fadeIn
            self.fadeOut = fadeOut
            self.start = start
            self.muted = muted
            self.ducksUnderVoice = ducksUnderVoice
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
        operations = (try? container.decode([Lossy].self, forKey: .operations))?.map(\.value) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(summary, forKey: .summary)
        try container.encode(operations, forKey: .operations)
    }

    /// One operation that never fails to decode: something that is not even an object becomes
    /// `.unknown` instead of throwing the whole list away.
    private struct Lossy: Decodable {
        let value: Operation
        init(from decoder: any Decoder) throws {
            value = (try? Operation(from: decoder)) ?? .unknown(type: "unknown")
        }
    }
}

/// Any key, so an operation can carry whichever of its many fields it needs.
struct PlanKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Reads fields the way models write them: numbers as strings, flags as "true" or 1.
struct PlanFields {
    let container: KeyedDecodingContainer<PlanKey>

    func string(_ key: String) -> String? {
        let k = PlanKey(key)
        if let value = try? container.decode(String.self, forKey: k) { return value }
        if let value = try? container.decode(Int.self, forKey: k) { return String(value) }
        if let value = try? container.decode(Double.self, forKey: k) { return String(value) }
        return nil
    }

    func number(_ key: String) -> Double? {
        let k = PlanKey(key)
        if let value = try? container.decode(Double.self, forKey: k), value.isFinite { return value }
        return (try? container.decode(String.self, forKey: k)).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    func integer(_ key: String) -> Int? {
        number(key).map { Int($0.rounded()) }
    }

    func flag(_ key: String) -> Bool? {
        let k = PlanKey(key)
        if let value = try? container.decode(Bool.self, forKey: k) { return value }
        if let value = try? container.decode(Double.self, forKey: k) { return value != 0 }
        return (try? container.decode(String.self, forKey: k)).map { ["true", "yes", "on", "1"].contains($0.lowercased()) }
    }

    func strings(_ key: String) -> [String]? {
        try? container.decode([String].self, forKey: PlanKey(key))
    }

    func integers(_ key: String) -> [Int]? {
        if let values = try? container.decode([Int].self, forKey: PlanKey(key)) { return values }
        return (try? container.decode([String].self, forKey: PlanKey(key)))?.compactMap { Int($0) }
    }
}

extension EditPlan.Operation: Codable {
    public init(from decoder: any Decoder) throws {
        let f = PlanFields(container: try decoder.container(keyedBy: PlanKey.self))
        let op = f.string("op") ?? f.string("type") ?? "unknown"
        let unknown = EditPlan.Operation.unknown(type: op)

        switch op {
        case "cut":
            guard let clip = f.string("clip"), let from = f.number("from"), let to = f.number("to"), to > from else {
                self = unknown; return
            }
            self = .cut(clip: clip, from: from, to: to)
        case "removeWords":
            guard let clip = f.string("clip"), let words = f.integers("words") else { self = unknown; return }
            self = .removeWords(clip: clip, words: words)
        case "trimPauses":
            self = .trimPauses(clip: f.string("clip"), minPause: f.number("minPause") ?? 0.6)
        case "trimClip":
            guard let clip = f.string("clip") else { self = unknown; return }
            let start = f.number("start"), end = f.number("end")
            guard start != nil || end != nil else { self = unknown; return }
            self = .trimClip(clip: clip, start: start, end: end)
        case "splitClip":
            guard let clip = f.string("clip"), let at = f.number("at") else { self = unknown; return }
            self = .splitClip(clip: clip, at: at)
        case "duplicateClip":
            guard let clip = f.string("clip") else { self = unknown; return }
            self = .duplicateClip(clip: clip)
        case "deleteClip":
            guard let clip = f.string("clip") else { self = unknown; return }
            self = .deleteClip(clip: clip)
        case "reorder":
            guard let clips = f.strings("clips") else { self = unknown; return }
            self = .reorder(clips: clips)
        case "setSpeed":
            guard let clip = f.string("clip"), let speed = f.number("speed") else { self = unknown; return }
            self = .setSpeed(clip: clip, speed: speed)
        case "reverse":
            guard let clip = f.string("clip") else { self = unknown; return }
            self = .reverse(clip: clip, on: f.flag("on") ?? true)
        case "setCaptionText":
            guard let caption = f.string("caption"), let text = f.string("text") else { self = unknown; return }
            self = .setCaptionText(caption: caption, text: text)
        case "captionTiming":
            guard let caption = f.string("caption") else { self = unknown; return }
            let start = f.number("start"), end = f.number("end")
            guard start != nil || end != nil else { self = unknown; return }
            self = .captionTiming(caption: caption, start: start, end: end)
        case "splitCaption":
            guard let caption = f.string("caption") else { self = unknown; return }
            self = .splitCaption(caption: caption)
        case "mergeCaption":
            guard let caption = f.string("caption") else { self = unknown; return }
            self = .mergeCaption(caption: caption)
        case "removeCaption":
            guard let caption = f.string("caption") else { self = unknown; return }
            self = .removeCaption(caption: caption)
        case "captionStyle", "captionLook":
            let look = EditPlan.CaptionLook(
                preset: f.string("preset"),
                size: f.number("size"),
                maxWords: f.integer("maxWords"),
                textCase: f.string("textCase"),
                textColor: f.string("textColor"),
                highlightColor: f.string("highlightColor"),
                backgroundColor: f.string("backgroundColor"),
                font: f.string("font"),
                position: f.number("position")
            )
            let tuned = look.size != nil || look.maxWords != nil || look.textCase != nil || look.textColor != nil
                || look.highlightColor != nil || look.backgroundColor != nil || look.font != nil
            if let preset = look.preset, !tuned {
                self = .captionStyle(preset: preset, position: look.position)
            } else if tuned || look.position != nil {
                self = .captionLook(look)
            } else {
                self = unknown
            }
        case "captionWindow":
            self = .captionWindow(from: f.number("from"), to: f.number("to"))
        case "addText":
            guard let patch = Self.overlayPatch(f), let text = patch.text, !text.isEmpty else { self = unknown; return }
            self = .addText(patch)
        case "updateOverlay":
            guard let overlay = f.string("overlay"), let patch = Self.overlayPatch(f) else { self = unknown; return }
            self = .updateOverlay(overlay: overlay, patch: patch)
        case "removeOverlay":
            guard let overlay = f.string("overlay") else { self = unknown; return }
            self = .removeOverlay(overlay: overlay)
        case "setMusicLevel":
            guard let audio = f.string("audio"), let gain = f.number("gainDb") else { self = unknown; return }
            self = .setMusicLevel(audio: audio, gainDb: gain)
        case "updateAudio":
            guard let audio = f.string("audio") else { self = unknown; return }
            let patch = EditPlan.AudioPatch(
                gainDb: f.number("gainDb"),
                fadeIn: f.number("fadeIn"),
                fadeOut: f.number("fadeOut"),
                start: f.number("start"),
                muted: f.flag("muted"),
                ducksUnderVoice: f.flag("ducksUnderVoice")
            )
            self = .updateAudio(audio: audio, patch: patch)
        case "removeAudio":
            guard let audio = f.string("audio") else { self = unknown; return }
            self = .removeAudio(audio: audio)
        case "voiceCleanup":
            let noise = f.flag("noiseReduction"), enhance = f.flag("voiceEnhance"), rumble = f.flag("deRumble")
            if noise != nil || enhance != nil || rumble != nil {
                self = .voiceEffects(noiseReduction: noise, voiceEnhance: enhance, deRumble: rumble)
            } else {
                self = .voiceCleanup(on: f.flag("on") ?? true)
            }
        case "voiceEffects":
            self = .voiceEffects(noiseReduction: f.flag("noiseReduction"), voiceEnhance: f.flag("voiceEnhance"), deRumble: f.flag("deRumble"))
        case "setTitle":
            guard let title = f.string("title") ?? f.string("text"), !title.isEmpty else { self = unknown; return }
            self = .setTitle(title)
        case "renameClip":
            guard let clip = f.string("clip"), let title = f.string("title") ?? f.string("text") else { self = unknown; return }
            self = .renameClip(clip: clip, title: title)
        case "setRole":
            guard let clip = f.string("clip"),
                  let role = f.string("role")?.lowercased(),
                  ["hook", "intro", "point", "example", "cta"].contains(role)
            else { self = unknown; return }
            self = .setRole(clip: clip, role: role)
        case "setScript":
            guard let clip = f.string("clip"), let text = f.string("text") ?? f.string("script") else { self = unknown; return }
            self = .setScript(clip: clip, text: text)
        case "selectTake":
            guard let clip = f.string("clip"), let take = f.string("take") else { self = unknown; return }
            self = .selectTake(clip: clip, take: take)
        case "duplicateOverlay":
            guard let overlay = f.string("overlay") else { self = unknown; return }
            self = .duplicateOverlay(overlay: overlay, start: f.number("start"))
        case "setBackground":
            let style = f.string("style") ?? f.string("background")
            self = .setBackground(BackgroundRequest(
                clip: f.string("clip"),
                style: style == "none" ? nil : style,
                from: f.number("from") ?? f.number("start"),
                to: f.number("to") ?? f.number("end"),
                strength: f.number("strength") ?? f.number("amount"),
                feather: f.number("feather") ?? f.number("edge"),
                color: f.string("color"),
                keep: f.string("keep"),
                screen: f.string("screen")
            ))
        case "removeEffect":
            guard let effect = f.string("effect") ?? f.string("id") else { self = unknown; return }
            self = .removeEffect(effect: effect)
        case "setFilter", "filter":
            self = .setFilter(FilterRequest(
                effect: f.string("effect"), clip: f.string("clip"),
                from: f.number("from") ?? f.number("start"), to: f.number("to") ?? f.number("end"),
                look: f.string("look") ?? f.string("preset") ?? f.string("style"),
                intensity: f.number("intensity"), brightness: f.number("brightness"), contrast: f.number("contrast"),
                saturation: f.number("saturation"), warmth: f.number("warmth"), vignette: f.number("vignette"),
                sharpness: f.number("sharpness")
            ))
        case "setSound", "soundEffect":
            self = .setSound(SoundRequest(
                effect: f.string("effect"), clip: f.string("clip"),
                from: f.number("from") ?? f.number("start"), to: f.number("to") ?? f.number("end"),
                preset: f.string("preset") ?? f.string("style"),
                amount: f.number("amount") ?? f.number("strength"), pitch: f.number("pitch"),
                volume: f.number("volume") ?? f.number("gainDb")
            ))
        case "retimeEffect", "moveEffect":
            guard let effect = f.string("effect") else { self = unknown; return }
            let from = f.number("from") ?? f.number("start"), to = f.number("to") ?? f.number("end")
            guard from != nil || to != nil else { self = unknown; return }
            self = .retimeEffect(effect: effect, from: from, to: to)
        case "splitEffect":
            guard let effect = f.string("effect"), let at = f.number("at") else { self = unknown; return }
            self = .splitEffect(effect: effect, at: at)
        case "updateVideo":
            guard let video = f.string("video") else { self = unknown; return }
            let patch = Self.videoPatch(f)
            guard !patch.isEmpty else { self = unknown; return }
            self = .updateVideo(video: video, patch: patch)
        case "keyframeVideo":
            guard let video = f.string("video"), let at = f.number("at") else { self = unknown; return }
            self = .keyframeVideo(video: video, at: at, patch: Self.videoPatch(f))
        case "layoutVideos":
            guard let layout = f.string("layout") else { self = unknown; return }
            self = .layoutVideos(layout: layout)
        case "removeVideo":
            guard let video = f.string("video") else { self = unknown; return }
            self = .removeVideo(video: video)
        case "splitVideo":
            guard let video = f.string("video"), let at = f.number("at") else { self = unknown; return }
            self = .splitVideo(video: video, at: at)
        case "splitOverlay":
            guard let overlay = f.string("overlay"), let at = f.number("at") else { self = unknown; return }
            self = .splitOverlay(overlay: overlay, at: at)
        case "mainVolume":
            guard let volume = f.number("volume") else { self = unknown; return }
            self = .mainVolume(FilterRequest.unit(volume))
        case "cameraMove", "zoom", "camera":
            let at = f.number("at") ?? f.number("from") ?? f.number("start")
            let to = f.number("to") ?? f.number("end") ?? at.flatMap { a in f.number("duration").map { a + $0 } }
            let request = CameraMoveRequest(
                move: f.string("move"),
                at: at,
                to: to,
                kind: CameraMoveRequest.kind(f.string("kind") ?? f.string("style")),
                amount: CameraMoveRequest.amount(f.number("amount") ?? f.number("zoom")),
                feel: CameraMoveRequest.feel(f.string("feel"))
            )
            guard request.move != nil || request.at != nil else { self = unknown; return }
            self = .cameraMove(request)
        case "removeCameraMove", "removeZoom":
            guard let move = f.string("move") else { self = unknown; return }
            self = .removeCameraMove(move: move)
        case "trackFace", "track", "followFace":
            self = .trackFace(clip: f.string("clip"), closeness: f.number("closeness").map { CameraMoveRequest.amount($0) ?? 0.12 })
        case "generateVideo", "generateBroll", "broll":
            guard let prompt = f.string("prompt"), !prompt.trimmingCharacters(in: .whitespaces).isEmpty else {
                self = unknown; return
            }
            let place = (f.string("as") ?? f.string("placement"))?.lowercased()
            self = .generateVideo(GenerateClipRequest(
                prompt: prompt,
                at: f.number("at") ?? f.number("start"),
                seconds: f.number("seconds") ?? f.number("duration"),
                asClip: place == "clip",
                model: f.string("model")
            ))
        case "transition", "addTransition", "setTransition":
            guard let kind = f.string("kind") ?? f.string("style") ?? f.string("effect") else { self = unknown; return }
            self = .transition(
                clip: f.string("clip") ?? f.string("after"),
                kind: kind,
                seconds: f.number("seconds") ?? f.number("duration")
            )
        case "removeTransition", "removeTransitions":
            self = .removeTransition(clip: f.string("clip") ?? f.string("after"))
        case "removeTrack", "stopTracking":
            self = .removeTrack(clip: f.string("clip"))
        case "useTranscript":
            guard let source = f.string("source"), ["device", "cloud"].contains(source) else { self = unknown; return }
            self = .useTranscript(clip: f.string("clip"), source: source)
        case "shiftCaptions":
            guard let by = f.number("by") ?? f.number("seconds") else { self = unknown; return }
            self = .shiftCaptions(clip: f.string("clip"), by: by)
        default:
            self = unknown
        }
    }

    private static func videoPatch(_ f: PlanFields) -> VideoPatch {
        VideoPatch(
            start: f.number("start"), end: f.number("end"), sourceStart: f.number("sourceStart"),
            x: f.number("x"), y: f.number("y"), width: f.number("width") ?? f.number("w"),
            height: f.number("height") ?? f.number("h"), opacity: f.number("opacity"),
            volume: f.number("volume"), muted: f.flag("muted"), hidden: f.flag("hidden"), mirrored: f.flag("mirrored"),
            screen: f.string("screen")
        )
    }

    private static func overlayPatch(_ f: PlanFields) -> EditPlan.OverlayPatch? {
        let patch = EditPlan.OverlayPatch(
            text: f.string("text"),
            start: f.number("start"),
            duration: f.number("duration"),
            end: f.number("end"),
            x: f.number("x"),
            y: f.number("y"),
            scale: f.number("scale"),
            rotation: f.number("rotation"),
            opacity: f.number("opacity"),
            flipX: f.flag("flipX"),
            flipY: f.flag("flipY"),
            color: f.string("color"),
            background: f.string("background"),
            font: f.string("font"),
            animation: f.string("animation"),
            behind: f.flag("behind")
        )
        return patch == EditPlan.OverlayPatch() ? nil : patch
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: PlanKey.self)
        func put<T: Encodable>(_ key: String, _ value: T?) throws {
            if let value { try c.encode(value, forKey: PlanKey(key)) }
        }
        try put("op", type)
        func putOverlay(_ patch: EditPlan.OverlayPatch) throws {
            try put("start", patch.start); try put("duration", patch.duration); try put("end", patch.end)
            try put("x", patch.x); try put("y", patch.y); try put("scale", patch.scale)
            try put("rotation", patch.rotation); try put("opacity", patch.opacity); try put("flipX", patch.flipX)
            try put("flipY", patch.flipY); try put("color", patch.color); try put("background", patch.background)
            try put("font", patch.font); try put("animation", patch.animation); try put("behind", patch.behind)
        }
        switch self {
        case .cut(let clip, let from, let to):
            try put("clip", clip); try put("from", from); try put("to", to)
        case .removeWords(let clip, let words):
            try put("clip", clip); try put("words", words)
        case .trimPauses(let clip, let minPause):
            try put("clip", clip); try put("minPause", minPause)
        case .trimClip(let clip, let start, let end):
            try put("clip", clip); try put("start", start); try put("end", end)
        case .splitClip(let clip, let at):
            try put("clip", clip); try put("at", at)
        case .duplicateClip(let clip), .deleteClip(let clip):
            try put("clip", clip)
        case .reorder(let clips):
            try put("clips", clips)
        case .setSpeed(let clip, let speed):
            try put("clip", clip); try put("speed", speed)
        case .reverse(let clip, let on):
            try put("clip", clip); try put("on", on)
        case .setCaptionText(let caption, let text):
            try put("caption", caption); try put("text", text)
        case .captionTiming(let caption, let start, let end):
            try put("caption", caption); try put("start", start); try put("end", end)
        case .splitCaption(let caption), .mergeCaption(let caption), .removeCaption(let caption):
            try put("caption", caption)
        case .captionStyle(let preset, let position):
            try put("preset", preset); try put("position", position)
        case .captionLook(let look):
            try put("preset", look.preset); try put("size", look.size); try put("maxWords", look.maxWords)
            try put("textCase", look.textCase); try put("textColor", look.textColor)
            try put("highlightColor", look.highlightColor); try put("backgroundColor", look.backgroundColor)
            try put("font", look.font); try put("position", look.position)
        case .captionWindow(let from, let to):
            try put("from", from); try put("to", to)
        case .addText(let patch):
            try put("text", patch.text); try putOverlay(patch)
        case .updateOverlay(let overlay, let patch):
            try put("overlay", overlay); try put("text", patch.text); try putOverlay(patch)
        case .removeOverlay(let overlay):
            try put("overlay", overlay)
        case .setMusicLevel(let audio, let gain):
            try put("audio", audio); try put("gainDb", gain)
        case .updateAudio(let audio, let patch):
            try put("audio", audio); try put("gainDb", patch.gainDb); try put("fadeIn", patch.fadeIn)
            try put("fadeOut", patch.fadeOut); try put("start", patch.start); try put("muted", patch.muted)
            try put("ducksUnderVoice", patch.ducksUnderVoice)
        case .removeAudio(let audio):
            try put("audio", audio)
        case .voiceCleanup(let on):
            try put("on", on)
        case .voiceEffects(let noise, let enhance, let rumble):
            try put("noiseReduction", noise); try put("voiceEnhance", enhance); try put("deRumble", rumble)
        case .setTitle(let title):
            try put("title", title)
        case .renameClip(let clip, let title):
            try put("clip", clip); try put("title", title)
        case .setRole(let clip, let role):
            try put("clip", clip); try put("role", role)
        case .setScript(let clip, let text):
            try put("clip", clip); try put("text", text)
        case .selectTake(let clip, let take):
            try put("clip", clip); try put("take", take)
        case .duplicateOverlay(let overlay, let start):
            try put("overlay", overlay); try put("start", start)
        case .shiftCaptions(let clip, let by):
            try put("clip", clip); try put("by", by)
        case .setBackground(let request):
            try put("clip", request.clip); try put("style", request.style ?? "none")
            try put("from", request.from); try put("to", request.to)
            try put("strength", request.strength); try put("feather", request.feather); try put("color", request.color)
            try put("keep", request.keep); try put("screen", request.screen)
        case .removeEffect(let effect):
            try put("effect", effect)
        case .setFilter(let r):
            try put("effect", r.effect); try put("clip", r.clip); try put("from", r.from); try put("to", r.to)
            try put("look", r.look); try put("intensity", r.intensity); try put("brightness", r.brightness)
            try put("contrast", r.contrast); try put("saturation", r.saturation); try put("warmth", r.warmth)
            try put("vignette", r.vignette); try put("sharpness", r.sharpness)
        case .setSound(let r):
            try put("effect", r.effect); try put("clip", r.clip); try put("from", r.from); try put("to", r.to)
            try put("preset", r.preset); try put("amount", r.amount); try put("pitch", r.pitch); try put("volume", r.volume)
        case .retimeEffect(let effect, let from, let to):
            try put("effect", effect); try put("from", from); try put("to", to)
        case .splitEffect(let effect, let at):
            try put("effect", effect); try put("at", at)
        case .updateVideo(let video, let p), .keyframeVideo(let video, _, let p):
            try put("video", video)
            if case .keyframeVideo(_, let at, _) = self { try put("at", at) }
            try put("start", p.start); try put("end", p.end); try put("sourceStart", p.sourceStart)
            try put("x", p.x); try put("y", p.y); try put("width", p.width); try put("height", p.height)
            try put("opacity", p.opacity); try put("volume", p.volume); try put("muted", p.muted)
            try put("hidden", p.hidden); try put("mirrored", p.mirrored); try put("screen", p.screen)
        case .layoutVideos(let layout):
            try put("layout", layout)
        case .removeVideo(let video):
            try put("video", video)
        case .splitVideo(let video, let at):
            try put("video", video); try put("at", at)
        case .splitOverlay(let overlay, let at):
            try put("overlay", overlay); try put("at", at)
        case .mainVolume(let volume):
            try put("volume", volume)
        case .useTranscript(let clip, let source):
            try put("clip", clip); try put("source", source)
        case .cameraMove(let r):
            try put("move", r.move); try put("at", r.at); try put("to", r.to)
            try put("kind", r.kind.map(EditDocument.documentName)); try put("amount", r.amount)
            try put("feel", r.feel?.rawValue)
        case .removeCameraMove(let move):
            try put("move", move)
        case .trackFace(let clip, let closeness):
            try put("clip", clip); try put("closeness", closeness)
        case .removeTrack(let clip):
            try put("clip", clip)
        case .generateVideo(let r):
            try put("prompt", r.prompt); try put("at", r.at); try put("seconds", r.seconds)
            try put("as", r.asClip ? "clip" : "broll"); try put("model", r.model)
        case .transition(let clip, let kind, let seconds):
            try put("clip", clip); try put("kind", kind); try put("seconds", seconds)
        case .removeTransition(let clip):
            try put("clip", clip)
        case .unknown:
            break
        }
    }
}

extension EditPlan {
    /// The plan with every reference the model wrote — `c2`, `k14`, a bare clip number, an id prefix —
    /// turned into the real id in `project`. Anything that matches nothing is left as written, and the
    /// step that uses it is skipped rather than guessed.
    public func resolvingReferences(in project: Project) -> EditPlan {
        let refs = EditReferences(project: project)
        return EditPlan(summary: summary, operations: operations.map { op in
            switch op {
            case .cut(let clip, let from, let to): .cut(clip: refs.clip(clip), from: from, to: to)
            case .removeWords(let clip, let words): .removeWords(clip: refs.clip(clip), words: words)
            case .trimPauses(let clip, let minPause): .trimPauses(clip: clip.map(refs.clip), minPause: minPause)
            case .trimClip(let clip, let start, let end): .trimClip(clip: refs.clip(clip), start: start, end: end)
            case .splitClip(let clip, let at): .splitClip(clip: refs.clip(clip), at: at)
            case .duplicateClip(let clip): .duplicateClip(clip: refs.clip(clip))
            case .deleteClip(let clip): .deleteClip(clip: refs.clip(clip))
            case .reorder(let clips): .reorder(clips: clips.map(refs.clip))
            case .setSpeed(let clip, let speed): .setSpeed(clip: refs.clip(clip), speed: speed)
            case .reverse(let clip, let on): .reverse(clip: refs.clip(clip), on: on)
            case .setCaptionText(let caption, let text): .setCaptionText(caption: refs.caption(caption), text: text)
            case .captionTiming(let caption, let start, let end): .captionTiming(caption: refs.caption(caption), start: start, end: end)
            case .splitCaption(let caption): .splitCaption(caption: refs.caption(caption))
            case .mergeCaption(let caption): .mergeCaption(caption: refs.caption(caption))
            case .removeCaption(let caption): .removeCaption(caption: refs.caption(caption))
            case .updateOverlay(let overlay, let patch): .updateOverlay(overlay: refs.overlay(overlay), patch: patch)
            case .removeOverlay(let overlay): .removeOverlay(overlay: refs.overlay(overlay))
            case .duplicateOverlay(let overlay, let start): .duplicateOverlay(overlay: refs.overlay(overlay), start: start)
            case .setMusicLevel(let audio, let gain): .setMusicLevel(audio: refs.audioClip(audio), gainDb: gain)
            case .updateAudio(let audio, let patch): .updateAudio(audio: refs.audioClip(audio), patch: patch)
            case .removeAudio(let audio): .removeAudio(audio: refs.audioClip(audio))
            case .renameClip(let clip, let title): .renameClip(clip: refs.clip(clip), title: title)
            case .setRole(let clip, let role): .setRole(clip: refs.clip(clip), role: role)
            case .setScript(let clip, let text): .setScript(clip: refs.clip(clip), text: text)
            case .selectTake(let clip, let take): .selectTake(clip: refs.clip(clip), take: refs.take(take))
            case .shiftCaptions(let clip, let by): .shiftCaptions(clip: clip.map(refs.clip), by: by)
            case .setBackground(let request):
                .setBackground(BackgroundRequest(
                    clip: request.clip.map(refs.clip), style: request.style, from: request.from, to: request.to,
                    strength: request.strength, feather: request.feather, color: request.color,
                    keep: request.keep, screen: request.screen
                ))
            case .removeEffect(let effect): .removeEffect(effect: refs.effect(effect))
            case .setFilter(let r): .setFilter(r.resolving(effect: refs.effect, clip: refs.clip))
            case .setSound(let r): .setSound(r.resolving(effect: refs.effect, clip: refs.clip))
            case .retimeEffect(let effect, let from, let to): .retimeEffect(effect: refs.effect(effect), from: from, to: to)
            case .splitEffect(let effect, let at): .splitEffect(effect: refs.effect(effect), at: at)
            case .updateVideo(let video, let patch): .updateVideo(video: refs.video(video), patch: patch)
            case .keyframeVideo(let video, let at, let patch): .keyframeVideo(video: refs.video(video), at: at, patch: patch)
            case .removeVideo(let video): .removeVideo(video: refs.video(video))
            case .splitVideo(let video, let at): .splitVideo(video: refs.video(video), at: at)
            case .splitOverlay(let overlay, let at): .splitOverlay(overlay: refs.overlay(overlay), at: at)
            case .useTranscript(let clip, let source): .useTranscript(clip: clip.map(refs.clip), source: source)
            case .cameraMove(let r):
                .cameraMove(CameraMoveRequest(
                    move: r.move.map(refs.move), at: r.at, to: r.to, kind: r.kind, amount: r.amount, feel: r.feel
                ))
            case .removeCameraMove(let move): .removeCameraMove(move: refs.move(move))
            case .trackFace(let clip, let closeness): .trackFace(clip: clip.map(refs.clip), closeness: closeness)
            case .removeTrack(let clip): .removeTrack(clip: clip.map(refs.clip))
            case .generateVideo: op
            case .transition(let clip, let kind, let seconds): .transition(clip: clip.map(refs.clip), kind: kind, seconds: seconds)
            case .removeTransition(let clip): .removeTransition(clip: clip.map(refs.clip))
            case .layoutVideos, .mainVolume: op
            case .captionStyle, .captionLook, .captionWindow, .addText, .voiceCleanup, .voiceEffects, .setTitle, .unknown: op
            }
        })
    }
}

/// A background over a stretch of the video, as the model asked for it.
///
/// The stretch is `from`–`to` on the finished video when given, otherwise the clip, otherwise the
/// whole video.
public struct BackgroundRequest: Hashable, Sendable {
    public var clip: String?
    /// A `ClipBackground` name; nil removes backgrounds from the stretch.
    public var style: String?
    public var from: Double?
    public var to: Double?
    public var strength: Double?
    public var feather: Double?
    public var color: String?
    /// What stays in front: `person` (the default), `subject`, or `screen` for a keyed colour.
    public var keep: String?
    /// The screen colour taken out, `#RRGGBB`, when `keep` is `screen`. Green when not given.
    public var screen: String?

    public init(
        clip: String? = nil,
        style: String?,
        from: Double? = nil,
        to: Double? = nil,
        strength: Double? = nil,
        feather: Double? = nil,
        color: String? = nil,
        keep: String? = nil,
        screen: String? = nil
    ) {
        self.keep = keep
        self.screen = screen
        self.clip = clip
        self.style = style
        self.from = from
        self.to = to
        self.strength = strength
        self.feather = feather
        self.color = color
    }
}

extension RGBAColor {
    /// `#RRGGBB` or `#RRGGBBAA`, with or without the hash.
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        if digits.count == 6 {
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        } else {
            self.init(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                alpha: Double(value & 0xFF) / 255
            )
        }
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when not opaque.
    public var hex: String {
        func byte(_ value: Double) -> String {
            let b = Int((min(max(value, 0), 1) * 255).rounded())
            let s = String(b, radix: 16, uppercase: true)
            return s.count == 1 ? "0" + s : s
        }
        return "#" + byte(red) + byte(green) + byte(blue) + (alpha < 0.999 ? byte(alpha) : "")
    }
}
