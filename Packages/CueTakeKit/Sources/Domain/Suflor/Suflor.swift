import Foundation

// Suflör: the prompter that sits beside another app's camera.
//
// Someone going live on TikTok or Instagram cannot use our camera, and the microphone belongs to
// whichever app is live: iOS gives it to one app at a time. So the suflör does not listen. It is
// prepared beforehand — the brand's brief turned into cards — and during the stream it floats in
// Picture in Picture and scrolls at the speed the speaker chose, holding before the ad until the
// minute comes.

/// What the brand wants said, and when.
public struct SuflorBrief: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// A live stream: talk freely, the ad comes at a minute or on a tap.
        case live
        /// A video recorded with another app's camera: the cards are the script.
        case video
    }

    public enum Platform: String, Codable, CaseIterable, Sendable {
        case tiktok, instagram, youtube, other
    }

    public enum AdTiming: Codable, Hashable, Sendable {
        /// The ad starts this many minutes after the prompter is started.
        case minute(Int)
        /// The prompter waits before the ad until the speaker moves it on.
        case manual
        /// No waiting: the cards run straight through.
        case none
    }

    public var kind: Kind
    public var platform: Platform
    public var brand: String
    public var product: String
    /// Words that must be said: a discount code, a link, a claim the brand insists on.
    public var mustSay: [String]
    public var timing: AdTiming
    public var tone: String
    /// What the stream or video is about, so the bridge into the ad sounds like part of it.
    public var topic: String

    public init(
        kind: Kind = .live,
        platform: Platform = .tiktok,
        brand: String = "",
        product: String = "",
        mustSay: [String] = [],
        timing: AdTiming = .minute(5),
        tone: String = "",
        topic: String = ""
    ) {
        self.kind = kind
        self.platform = platform
        self.brand = brand
        self.product = product
        self.mustSay = mustSay
        self.timing = timing
        self.tone = tone
        self.topic = topic
    }

    /// Enough to prepare anything from.
    public var isUsable: Bool {
        !brand.trimmingCharacters(in: .whitespaces).isEmpty || !product.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// One card of the flow.
public struct SuflorCue: Codable, Hashable, Identifiable, Sendable {
    public enum Role: String, Codable, CaseIterable, Sendable {
        case opening, topic, bridge, ad, cta, rescue, closing

        /// The ad section: from the bridge into it to the lines kept for when the words run out.
        public var isAd: Bool {
            switch self {
            case .bridge, .ad, .cta, .rescue: true
            default: false
            }
        }
    }

    public var id: UUID
    public var role: Role
    public var text: String

    public init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

public struct SuflorPlan: Codable, Hashable, Sendable {
    public var brief: SuflorBrief
    public var cues: [SuflorCue]

    public init(brief: SuflorBrief, cues: [SuflorCue]) {
        self.brief = brief
        self.cues = cues
    }

    /// Cards in the order a stream uses them: the talk before the ad, then the ad as one block,
    /// then the close. Whatever order they were written in, the ad stays together, which is what
    /// the hold before it relies on.
    public var ordered: [SuflorCue] {
        let usable = cues.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let before = usable.filter { $0.role == .opening || $0.role == .topic }
        let ad = SuflorCue.Role.allCases.filter(\.isAd).flatMap { role in usable.filter { $0.role == role } }
        let after = usable.filter { $0.role == .closing }
        return before + ad + after
    }

    /// Index of the first ad card in `ordered`, or nil when there is none.
    public var adStart: Int? { ordered.firstIndex { $0.role.isAd } }

    /// Words across every card, for the time the whole flow takes.
    public var wordCount: Int {
        ordered.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    /// Reads a plan out of what the model wrote, tolerating text around the JSON and unknown roles.
    public static func cues(fromModelText text: String) -> [SuflorCue] {
        struct Written: Decodable {
            struct Card: Decodable {
                var role: String?
                var text: String?
            }
            var cues: [Card]?
        }
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let written = try? JSONDecoder().decode(Written.self, from: Data(text[open...close].utf8))
        else { return [] }
        return (written.cues ?? []).compactMap { card in
            let words = (card.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else { return nil }
            let role = SuflorCue.Role(rawValue: (card.role ?? "").lowercased()) ?? .topic
            return SuflorCue(role: role, text: words)
        }
    }
}

/// Where the prompter is and what it is doing, advanced by one clock.
///
/// Positions are in the layout's points: 0 is the first line on the reading line. The ad hold is
/// a position too — the top of the ad section — where the flow waits for the minute or the tap.
public struct SuflorClock: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        /// On stage but not started: waiting for the first play, which is when the stream starts.
        case ready
        /// The three-second count before anything moves.
        case countdown
        case rolling
        /// Waiting at the top of the ad section.
        case holding
        /// The last line has reached the reading line.
        case finished
    }

    public var offset: Double = 0
    public var isPlaying = true
    /// False until the first play. Going on stage and going live are minutes apart — opening the
    /// other app, starting the stream — and the words must not roll away in between.
    public var started = true
    /// Seconds since the first play: the stream's own clock.
    public var elapsed: Double = 0
    /// The ad section's top, or nil when there is nothing to wait for.
    public var holdAt: Double?
    /// Seconds after going on stage when the ad may start; nil waits for the speaker.
    public var adAt: Double?
    /// Set once the speaker or the minute has let the ad go.
    public var released = false
    public var end: Double
    public static let countdown: Double = 3

    public init(end: Double, holdAt: Double? = nil, adAt: Double? = nil, started: Bool = true) {
        self.end = end
        self.holdAt = holdAt
        self.adAt = adAt
        self.started = started
        if !started { isPlaying = false }
    }

    public var phase: Phase {
        if !started { return .ready }
        if elapsed < Self.countdown { return .countdown }
        if offset >= end { return .finished }
        if isHolding { return .holding }
        return .rolling
    }

    private var isHolding: Bool {
        guard let holdAt, !released, offset >= holdAt - 0.5 else { return false }
        return true
    }

    /// Seconds until the ad, while there is a minute to wait for.
    public var secondsToAd: Double? {
        guard let adAt, !released else { return nil }
        return max(0, adAt - elapsed)
    }

    /// Moves time on. Scrolls at `speed` points a second unless paused, counting down, held or done.
    public mutating func tick(_ seconds: Double, speed: Double) {
        guard seconds > 0, started else { return }
        elapsed += seconds
        if let adAt, !released, elapsed >= adAt { released = true }
        guard isPlaying, elapsed >= Self.countdown else { return }
        var next = offset + speed * seconds
        if let holdAt, !released, offset <= holdAt, next > holdAt { next = holdAt }
        offset = min(max(0, next), end)
    }

    /// Play and pause. The first play starts the stream's clock.
    public mutating func setPlaying(_ playing: Bool) {
        if playing { started = true }
        isPlaying = playing
    }

    /// The speaker's hand: dragging up or down. Moving past the hold lets the ad go.
    public mutating func move(by delta: Double) {
        offset = min(max(0, offset + delta), end)
        if let holdAt, offset > holdAt + 1 { released = true }
    }

    /// Straight to a position, as the skip buttons do. Jumping into the ad lets it go.
    public mutating func jump(to position: Double) {
        offset = min(max(0, position), end)
        if let holdAt, offset >= holdAt - 0.5 { released = true }
    }
}

/// Where in a recording something the brand asked for was said.
public struct SuflorProof: Codable, Hashable, Sendable, Identifiable {
    public var id: String { item + "@\(Int(seconds))" }
    public var item: String
    public var seconds: Double
    /// The sentence around it, as heard.
    public var quote: String
    public var frame: Data?

    public init(item: String, seconds: Double, quote: String, frame: Data? = nil) {
        self.item = item
        self.seconds = seconds
        self.quote = quote
        self.frame = frame
    }

    /// The first time each item was said in the transcript.
    ///
    /// Spoken words come back spaced and cased however the recogniser likes — "kod 20", "KOD20",
    /// "Kod-20" — so both sides are folded to letters and digits and the item is looked for in
    /// runs of up to five consecutive words.
    public static func find(_ items: [String], in words: [TimedWord], localeIdentifier: String) -> [SuflorProof] {
        let locale = Locale(identifier: localeIdentifier)
        let folded = words.map { fold($0.text, locale: locale) }
        var proofs: [SuflorProof] = []
        for item in items {
            let target = fold(item, locale: locale)
            guard !target.isEmpty else { continue }
            search: for start in folded.indices {
                var joined = ""
                for end in start..<min(folded.count, start + 5) {
                    joined += folded[end]
                    if joined.contains(target) {
                        // The run may have started a word early ("kodum kod 20"): tighten it
                        // to the latest first word that still holds the item.
                        var first = start
                        while first < end, folded[(first + 1)...end].joined().contains(target) { first += 1 }
                        let from = max(0, first - 6)
                        let to = min(words.count - 1, end + 6)
                        let quote = words[from...to].map(\.text).joined(separator: " ")
                        proofs.append(SuflorProof(item: item, seconds: words[first].range.start.seconds, quote: quote))
                        break search
                    }
                    if joined.count > target.count + 24 { break }
                }
            }
        }
        return proofs
    }

    static func fold(_ text: String, locale: Locale) -> String {
        text.lowercased(with: locale)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: locale)
            .filter { $0.isLetter || $0.isNumber }
    }
}

/// What happened on stage, for the report to the brand.
public struct SuflorSession: Codable, Hashable, Sendable {
    public var plan: SuflorPlan
    public var startedAt: Date
    public var endedAt: Date?
    /// Seconds after going on stage when the ad section reached the reading line.
    public var adStartedAt: Double?
    public var adEndedAt: Double?
    /// Items the speaker ticked on stage, with the second they did.
    public var ticked: [String: Double]
    public var proofs: [SuflorProof]
    public var creator: String

    public init(plan: SuflorPlan, startedAt: Date = .now) {
        self.plan = plan
        self.startedAt = startedAt
        ticked = [:]
        proofs = []
        creator = ""
    }

    public var duration: Double { (endedAt ?? .now).timeIntervalSince(startedAt) }
    public var adDuration: Double? {
        guard let adStartedAt else { return nil }
        return max(0, (adEndedAt ?? duration) - adStartedAt)
    }

    /// Each item the brand asked for and how we know it was said, strongest first: heard in the
    /// recording, then ticked by the speaker.
    public enum Evidence: Hashable, Sendable {
        case heard(SuflorProof)
        case ticked(Double)
        case missing
    }

    public func evidence(for item: String) -> Evidence {
        if let proof = proofs.first(where: { $0.item == item }) { return .heard(proof) }
        if let second = ticked[item] { return .ticked(second) }
        return .missing
    }

    /// Short and unguessable enough to quote back: "SF-7K2M-Q9XD".
    public var reportID: String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var seed = UInt64(bitPattern: Int64(startedAt.timeIntervalSince1970 * 1000)) ^ 0x9E37_79B9_7F4A_7C15
        var characters: [Character] = []
        for _ in 0..<8 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            characters.append(alphabet[Int((seed >> 33) % UInt64(alphabet.count))])
        }
        return "SF-" + String(characters[0..<4]) + "-" + String(characters[4..<8])
    }

    /// "12:04" for a second count, hours when there are any.
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}
