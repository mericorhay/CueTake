import Foundation

// MARK: - Studio tools as workflow steps
//
// Every tool of the editor's studio, as a step a workflow can run without anyone in the editor:
// titles, brand templates, filters, backgrounds, camera moves, face tracking, transitions, voice
// effects, the layout of added videos, the brand kit, cleanup, best takes and a free AI edit.
//
// A step only says what the creator wants ("a cinematic look on the hook", "a punch-in every few
// sentences"); `WorkflowStudioPlanner` turns it into the same edit operations the studio's AI
// sends, against the video as it is when the step runs. The editor applies them exactly as it
// applies the AI's, so a workflow and a hand edit can never drift apart.

/// Decodes a field or falls back, whatever went wrong: a missing key, a string where a number
/// belongs. A workflow an AI wrote must cost a parameter, not the step.
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

/// Which clips a studio step works on: the whole video, or the clips of one section role.
public enum WorkflowTarget {
    public static let all = "all"
    public static let options = ["all", "hook", "intro", "point", "example", "cta"]
}

public struct CleanupStepOptions: Hashable, Sendable, Codable {
    public var pauses: Bool
    public var fillers: Bool
    public var repeats: Bool
    public var restarts: Bool

    public init(pauses: Bool = true, fillers: Bool = true, repeats: Bool = true, restarts: Bool = true) {
        self.pauses = pauses
        self.fillers = fillers
        self.repeats = repeats
        self.restarts = restarts
    }

    private enum CodingKeys: String, CodingKey { case pauses, fillers, repeats, restarts }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pauses = c.value(.pauses, or: true)
        fillers = c.value(.fillers, or: true)
        repeats = c.value(.repeats, or: true)
        restarts = c.value(.restarts, or: true)
    }

    public var kinds: Set<CleanupItem.Kind> {
        var kinds: Set<CleanupItem.Kind> = []
        if pauses { kinds.insert(.pause) }
        if fillers { kinds.insert(.filler) }
        if repeats { kinds.insert(.repeated) }
        if restarts { kinds.insert(.restart) }
        return kinds
    }
}

public struct BrandStepOptions: Hashable, Sendable, Codable {
    /// Paints captions and titles in the brand's colours and face.
    public var colors: Bool
    /// Puts the brand's logo in its corner.
    public var logo: Bool

    public init(colors: Bool = true, logo: Bool = true) {
        self.colors = colors
        self.logo = logo
    }

    private enum CodingKeys: String, CodingKey { case colors, logo }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colors = c.value(.colors, or: true)
        logo = c.value(.logo, or: true)
    }
}

/// Where a title or a template goes in time.
public enum WorkflowMoment: String, Hashable, Sendable, Codable, CaseIterable {
    /// Right at the opening.
    case start
    /// When the call to action starts, or the last few seconds without one.
    case cta
    /// Over the closing seconds.
    case end
    /// At `seconds` from the start.
    case at
}

public struct TitleStepOptions: Hashable, Sendable, Codable {
    /// Empty: the project's title, else the opening words.
    public var text: String
    public var moment: WorkflowMoment
    public var seconds: Double
    public var duration: Double
    /// 0 top … 1 bottom, the centre of the text.
    public var y: Double
    public var scale: Double
    public var animation: String
    /// The person stands in front of the text: the magazine-cover look.
    public var behind: Bool

    public init(
        text: String = "", moment: WorkflowMoment = .start, seconds: Double = 0, duration: Double = 2.5,
        y: Double = 0.22, scale: Double = 1.7, animation: String = "pop", behind: Bool = false
    ) {
        self.text = text
        self.moment = moment
        self.seconds = seconds
        self.duration = duration
        self.y = y
        self.scale = scale
        self.animation = animation
        self.behind = behind
    }

    private enum CodingKeys: String, CodingKey { case text, moment, seconds, duration, y, scale, animation, behind }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = c.value(.text, or: "")
        moment = c.value(.moment, or: .start)
        seconds = c.value(.seconds, or: 0)
        duration = c.value(.duration, or: 2.5)
        y = c.value(.y, or: 0.22)
        scale = c.value(.scale, or: 1.7)
        animation = c.value(.animation, or: "pop")
        behind = c.value(.behind, or: false)
    }
}

public struct TemplateStepOptions: Hashable, Sendable, Codable {
    /// A template style: `codeCard`, `coupon`, `priceTag`… (`WorkflowTemplateStyle`).
    public var style: String
    /// Each line by its slot's name. Empty lines are left out of the picture.
    public var lines: [String: String]
    /// `#RRGGBB`; empty for the brand's own colour.
    public var color: String
    public var moment: WorkflowMoment
    public var seconds: Double
    public var duration: Double

    public init(
        style: String = "codeCard", lines: [String: String] = [:], color: String = "",
        moment: WorkflowMoment = .cta, seconds: Double = 0, duration: Double = 4
    ) {
        self.style = style
        self.lines = lines
        self.color = color
        self.moment = moment
        self.seconds = seconds
        self.duration = duration
    }

    private enum CodingKeys: String, CodingKey { case style, lines, color, moment, seconds, duration }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = c.value(.style, or: "codeCard")
        lines = c.value(.lines, or: [:])
        color = c.value(.color, or: "")
        moment = c.value(.moment, or: .cta)
        seconds = c.value(.seconds, or: 0)
        duration = c.value(.duration, or: 4)
    }
}

/// The template styles and the lines each one has, in reading order. The same as the studio's.
public enum WorkflowTemplateStyle {
    public static let styles: [(name: String, slots: [String])] = [
        ("codeCard", ["label", "code", "note", "brand"]),
        ("coupon", ["number", "label", "code", "date", "brand"]),
        ("priceTag", ["title", "price", "oldPrice", "brand"]),
        ("spotlight", ["label", "title", "price", "brand"]),
        ("badge", ["number", "label", "brand"]),
        ("stat", ["number", "title", "detail", "brand"]),
        ("bigTitle", ["brand", "title", "detail"]),
        ("lowerThird", ["brand", "title", "detail"]),
        ("newDrop", ["label", "title", "detail", "brand"]),
        ("countdown", ["title", "detail", "brand"]),
        ("promoStrip", ["title", "detail"]),
        ("review", ["title", "detail", "brand"]),
        ("quote", ["title", "detail"]),
        ("checklist", ["title", "item1", "item2", "item3", "brand"]),
        ("beforeAfter", ["optionA", "title", "optionB", "detail"]),
        ("poll", ["title", "optionA", "optionB"]),
        ("giveaway", ["title", "item1", "item2", "item3", "brand"]),
        ("ticket", ["brand", "title", "detail", "date"]),
        ("location", ["place", "detail", "cta"]),
        ("linkPill", ["title", "brand"]),
        ("ctaButton", ["detail", "cta", "brand"]),
        ("collab", ["brand", "title"]),
    ]

    public static var names: [String] { styles.map(\.name) }

    public static func slots(of style: String) -> [String] {
        styles.first { $0.name == style }?.slots ?? []
    }
}

public struct FilterStepOptions: Hashable, Sendable, Codable {
    /// A `FilterSettings.Look` name.
    public var look: String
    public var intensity: Double
    /// `all`, or a section role.
    public var target: String

    public init(look: String = "cinematic", intensity: Double = 0.7, target: String = "all") {
        self.look = look
        self.intensity = intensity
        self.target = target
    }

    private enum CodingKeys: String, CodingKey { case look, intensity, target }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        look = c.value(.look, or: "cinematic")
        intensity = c.value(.intensity, or: 0.7)
        target = c.value(.target, or: "all")
    }
}

public struct TransitionStepOptions: Hashable, Sendable, Codable {
    public enum Placement: String, Hashable, Sendable, Codable, CaseIterable {
        /// Only where one section hands over to the next: the story changes, not the sentence.
        case sections
        case everyCut
    }

    /// A `ClipTransition.Kind` name.
    public var kind: String
    public var seconds: Double
    public var placement: Placement

    public init(kind: String = "crossfade", seconds: Double = 0.5, placement: Placement = .sections) {
        self.kind = kind
        self.seconds = seconds
        self.placement = placement
    }

    private enum CodingKeys: String, CodingKey { case kind, seconds, placement }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.value(.kind, or: "crossfade")
        seconds = c.value(.seconds, or: 0.5)
        placement = c.value(.placement, or: .sections)
    }
}

public struct ZoomStepOptions: Hashable, Sendable, Codable {
    public enum Style: String, Hashable, Sendable, Codable, CaseIterable {
        /// A quick punch-in on a sentence's first word.
        case punch
        /// A slow push into the sentence.
        case push
        /// Push and punch taking turns: what a professional edit usually does.
        case mixed
    }

    public var style: Style
    /// Added magnification at the peak, 0.04…0.35.
    public var amount: Double
    /// The least time between two moves, in seconds.
    public var spacing: Double

    public init(style: Style = .mixed, amount: Double = 0.14, spacing: Double = 5) {
        self.style = style
        self.amount = amount
        self.spacing = spacing
    }

    private enum CodingKeys: String, CodingKey { case style, amount, spacing }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = c.value(.style, or: .mixed)
        amount = c.value(.amount, or: 0.14)
        spacing = c.value(.spacing, or: 5)
    }
}

public struct TrackFaceOptions: Hashable, Sendable, Codable {
    /// How much closer the framing gets, 0.08…0.2: the room the camera has to follow.
    public var closeness: Double

    public init(closeness: Double = 0.12) {
        self.closeness = closeness
    }

    private enum CodingKeys: String, CodingKey { case closeness }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        closeness = c.value(.closeness, or: 0.12)
    }
}

public struct BackgroundStepOptions: Hashable, Sendable, Codable {
    /// A `ClipBackground` name.
    public var style: String
    public var strength: Double
    /// `#RRGGBB`, for the `color` style.
    public var color: String
    public var target: String

    public init(style: String = "blur", strength: Double = 0.7, color: String = "#1E1E24", target: String = "all") {
        self.style = style
        self.strength = strength
        self.color = color
        self.target = target
    }

    private enum CodingKeys: String, CodingKey { case style, strength, color, target }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = c.value(.style, or: "blur")
        strength = c.value(.strength, or: 0.7)
        color = c.value(.color, or: "#1E1E24")
        target = c.value(.target, or: "all")
    }
}

public struct VoiceEffectOptions: Hashable, Sendable, Codable {
    /// A `SoundSettings.Preset` name.
    public var preset: String
    public var amount: Double
    public var target: String

    public init(preset: String = "room", amount: Double = 0.4, target: String = "all") {
        self.preset = preset
        self.amount = amount
        self.target = target
    }

    private enum CodingKeys: String, CodingKey { case preset, amount, target }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = c.value(.preset, or: "room")
        amount = c.value(.amount, or: 0.4)
        target = c.value(.target, or: "all")
    }
}

public struct VideoLayoutOptions: Hashable, Sendable, Codable {
    public static let layouts = ["pictureInPicture", "sideBySide", "stacked", "grid"]

    public var layout: String

    public init(layout: String = "pictureInPicture") {
        self.layout = layout
    }

    private enum CodingKeys: String, CodingKey { case layout }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = c.value(.layout, or: "pictureInPicture")
    }
}

public struct AIEditOptions: Hashable, Sendable, Codable {
    /// What the studio's AI should do, in the creator's words.
    public var instruction: String

    public init(instruction: String = "") {
        self.instruction = instruction
    }

    private enum CodingKeys: String, CodingKey { case instruction }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instruction = c.value(.instruction, or: "")
    }
}

// MARK: - Planning

/// Turns a studio step into the studio's own edit operations, for the video as it is now.
public enum WorkflowStudioPlanner {
    /// The clips a target names, by their document ids. Nil means the whole video.
    static func clips(_ target: String, in document: EditDocument) -> [String]? {
        let wanted = target.lowercased()
        guard wanted != WorkflowTarget.all, !wanted.isEmpty else { return nil }
        return document.clips.filter { $0.role.lowercased() == wanted }.map(\.id)
    }

    /// Where a moment falls on the finished video, for something `duration` long.
    static func start(of moment: WorkflowMoment, seconds: Double, duration: Double, in document: EditDocument) -> Double {
        let total = document.duration
        let latest = max(0, total - duration)
        switch moment {
        case .start:
            return min(0.2, latest)
        case .end:
            return max(0, total - duration - 0.2)
        case .at:
            return min(max(0, seconds), latest)
        case .cta:
            if let cta = document.clips.first(where: { $0.role.lowercased() == "cta" }) {
                return min(cta.at + 0.2, latest)
            }
            return max(0, total - duration - 0.2)
        }
    }

    public static func title(_ options: TitleStepOptions, in document: EditDocument) -> [EditPlan.Operation] {
        var text = options.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = openingWords(in: document) }
        guard !text.isEmpty, document.duration > 0.5 else { return [] }
        let duration = min(max(options.duration, 0.5), document.duration)
        return [.addText(EditPlan.OverlayPatch(
            text: text,
            start: start(of: options.moment, seconds: options.seconds, duration: duration, in: document),
            duration: duration,
            x: 0.5,
            y: min(max(options.y, 0.06), 0.94),
            scale: min(max(options.scale, 0.5), 2.5),
            animation: options.animation,
            behind: options.behind
        ))]
    }

    /// A title for a video no one named: its first few words, the hook.
    static func openingWords(in document: EditDocument) -> String {
        let titled = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = document.clips.first?.words.prefix(12).map(\.text) ?? []
        if !words.isEmpty {
            // Up to the end of the first sentence, at most six words.
            var picked: [String] = []
            for word in words {
                picked.append(word)
                if picked.count >= 6 || word.last.map({ ".!?".contains($0) }) == true { break }
            }
            return picked.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".,;: "))
        }
        return titled
    }

    public static func template(_ options: TemplateStepOptions, in document: EditDocument) -> [EditPlan.Operation] {
        guard document.duration > 0.5 else { return [] }
        let slots = Set(WorkflowTemplateStyle.slots(of: options.style))
        let lines = options.lines.filter { slots.contains($0.key) && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        let duration = min(max(options.duration, 1), document.duration)
        let color = options.color.trimmingCharacters(in: .whitespaces)
        return [.addTemplate(TemplateRequest(
            style: options.style,
            texts: lines,
            color: color.isEmpty ? nil : color,
            start: start(of: options.moment, seconds: options.seconds, duration: duration, in: document),
            duration: duration
        ))]
    }

    public static func filter(_ options: FilterStepOptions, in document: EditDocument) -> [EditPlan.Operation] {
        let intensity = min(max(options.intensity, 0), 1)
        guard let clips = clips(options.target, in: document) else {
            return [.setFilter(FilterRequest(from: 0, to: document.duration, look: options.look, intensity: intensity))]
        }
        return clips.map { .setFilter(FilterRequest(clip: $0, look: options.look, intensity: intensity)) }
    }

    public static func background(_ options: BackgroundStepOptions, in document: EditDocument) -> [EditPlan.Operation] {
        let strength = min(max(options.strength, 0), 1)
        let color = options.style == "color" ? options.color : nil
        guard let clips = clips(options.target, in: document) else {
            return [.setBackground(BackgroundRequest(style: options.style, from: 0, to: document.duration, strength: strength, color: color))]
        }
        return clips.map { .setBackground(BackgroundRequest(clip: $0, style: options.style, strength: strength, color: color)) }
    }

    public static func voiceEffect(_ options: VoiceEffectOptions, in document: EditDocument) -> [EditPlan.Operation] {
        let amount = min(max(options.amount, 0), 1)
        guard let clips = clips(options.target, in: document) else {
            return [.setSound(SoundRequest(from: 0, to: document.duration, preset: options.preset, amount: amount))]
        }
        return clips.map { .setSound(SoundRequest(clip: $0, preset: options.preset, amount: amount)) }
    }

    public static func transitions(_ options: TransitionStepOptions, in document: EditDocument) -> [EditPlan.Operation] {
        guard document.clips.count > 1 else { return [] }
        let seconds = min(max(options.seconds, 0.2), 2)
        switch options.placement {
        case .everyCut:
            return [.transition(clip: nil, kind: options.kind, seconds: seconds)]
        case .sections:
            let clips = document.clips
            return clips.indices.dropLast().compactMap { index in
                clips[index].role.lowercased() == clips[index + 1].role.lowercased()
                    ? nil
                    : .transition(clip: clips[index].id, kind: options.kind, seconds: seconds)
            }
        }
    }

    /// Camera moves on the starts of sentences, never closer together than `spacing`, each inside
    /// one clip. Without speech, one every `spacing` seconds instead.
    public static func zoom(_ options: ZoomStepOptions, in document: EditDocument) -> [EditPlan.Operation] {
        let spacing = max(options.spacing, 2)
        let amount = min(max(options.amount, 0.04), 0.35)
        var moves: [EditPlan.Operation] = []
        var last = -Double.infinity
        var turn = 0

        for clip in document.clips {
            let speed = max(clip.speed ?? 1, 0.05)
            let end = clip.at + clip.length - 0.05
            var moments: [Double] = []
            var previousEnd: Double?
            var previousText = ""
            for word in clip.words {
                let startsSentence = previousEnd == nil
                    || word.start - (previousEnd ?? 0) >= 0.3
                    || previousText.last.map { ".!?".contains($0) } == true
                if startsSentence { moments.append(clip.at + word.start / speed) }
                previousEnd = word.end
                previousText = word.text
            }
            if clip.words.isEmpty {
                moments = Array(stride(from: clip.at + 0.5, to: end, by: spacing))
            }

            for moment in moments where moment - last >= spacing {
                let punch = options.style == .punch || (options.style == .mixed && turn % 2 == 1)
                let length = punch ? 1.0 : 2.2
                let to = min(moment + length, end)
                guard to - moment >= 0.6 else { continue }
                moves.append(.cameraMove(CameraMoveRequest(
                    at: moment,
                    to: to,
                    kind: punch ? .punch : .pushIn,
                    amount: punch ? amount * 1.4 : amount,
                    feel: punch ? .energetic : .natural
                )))
                last = moment
                turn += 1
            }
        }
        return moves
    }
}
