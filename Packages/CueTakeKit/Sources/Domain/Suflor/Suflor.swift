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
    /// What the product is and what the brand wants said about it, usually pasted from the
    /// brand's own brief. The only source of facts about the product: without it, nothing is
    /// claimed about what the product is or does.
    public var details: String
    /// Where the link sends people: an address, or "the link in my bio". Checked in the take.
    public var link: String
    /// The brand's own words — product models, campaign codes — told to the recogniser before it
    /// listens, so it writes them the brand's way.
    public var vocabulary: [String]
    /// Words that must not be said: a competitor, a claim the brand cannot make.
    public var avoid: [String]
    /// How long the ad section should last, in seconds; 0 when the brand did not say.
    public var adSeconds: Int

    public init(
        kind: Kind = .live,
        platform: Platform = .tiktok,
        brand: String = "",
        product: String = "",
        mustSay: [String] = [],
        timing: AdTiming = .minute(5),
        tone: String = "",
        topic: String = "",
        details: String = "",
        link: String = "",
        vocabulary: [String] = [],
        avoid: [String] = [],
        adSeconds: Int = 0
    ) {
        self.kind = kind
        self.platform = platform
        self.brand = brand
        self.product = product
        self.mustSay = mustSay
        self.timing = timing
        self.tone = tone
        self.topic = topic
        self.details = details
        self.link = link
        self.vocabulary = vocabulary
        self.avoid = avoid
        self.adSeconds = adSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case kind, platform, brand, product, mustSay, timing, tone, topic, details, link, vocabulary, avoid, adSeconds
    }

    /// Every term the recogniser should expect: the names, the items, the brand's vocabulary and
    /// the words to catch if they slip out.
    public var recognitionTerms: [String] {
        var seen = Set<String>()
        return ([brand, product] + mustSay + vocabulary + avoid + [link])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Briefs saved before `details` existed, or the checks after it, still open.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        platform = try container.decode(Platform.self, forKey: .platform)
        brand = try container.decode(String.self, forKey: .brand)
        product = try container.decode(String.self, forKey: .product)
        mustSay = try container.decode([String].self, forKey: .mustSay)
        timing = try container.decode(AdTiming.self, forKey: .timing)
        tone = try container.decode(String.self, forKey: .tone)
        topic = try container.decode(String.self, forKey: .topic)
        details = try container.decodeIfPresent(String.self, forKey: .details) ?? ""
        link = try container.decodeIfPresent(String.self, forKey: .link) ?? ""
        vocabulary = try container.decodeIfPresent([String].self, forKey: .vocabulary) ?? []
        avoid = try container.decodeIfPresent([String].self, forKey: .avoid) ?? []
        adSeconds = try container.decodeIfPresent(Int.self, forKey: .adSeconds) ?? 0
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
        /// The count before anything moves.
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
    /// Time to put the phone down and look at the camera after pressing play.
    public static let countdown: Double = 10

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

/// The creator's own way of talking, taken from what they said in their videos, so the cards can
/// be written in their voice instead of a generic one.
public enum SuflorVoice {
    /// Enough speech to hear a way of talking in; less is just noise.
    public static let minimumWords = 60

    /// Up to `maxWords` of the creator's speech, newest first, one recording per paragraph. Nil
    /// when there is too little to go on.
    public static func sample(from transcripts: [Transcript], maxWords: Int = 450) -> String? {
        var paragraphs: [String] = []
        var count = 0
        for transcript in transcripts {
            let words = transcript.words.map(\.text).filter { !$0.isEmpty }
            guard words.count >= 8, count < maxWords else { continue }
            let taken = Array(words.prefix(maxWords - count))
            paragraphs.append(taken.joined(separator: " "))
            count += taken.count
        }
        return count >= minimumWords ? paragraphs.joined(separator: "\n\n") : nil
    }

    public static func wordCount(_ sample: String?) -> Int {
        sample?.split(whereSeparator: \.isWhitespace).count ?? 0
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

    /// Ways of saying "this is an ad", in the languages the app speaks. A spoken word matches a
    /// phrase word when it starts with it, so "iş birliğiyle" counts as "iş birliği".
    public static let disclosurePhrases = [
        "iş birliği", "işbirliği", "reklam", "reklamdır", "sponsor", "sponsorlu", "ücretli ortaklık",
        "paid partnership", "sponsored", "advertisement", "partnered with", "in partnership with",
        "publicidad", "patrocinado", "colaboración pagada", "en colaboración con",
    ]

    /// Ways of sending people to a link.
    public static let linkPhrases = [
        "link", "linki", "linke", "bağlantı", "açıklamada", "açıklama", "bio", "biyografi", "profilde",
        "description", "in bio", "enlace", "en la descripción",
    ]

    /// The name inside an address — "cuetake" in "https://cuetake.app/kod" — which is how it is said.
    public static func names(inLink link: String) -> [String] {
        let cleaned = link.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
        guard let host = cleaned.split(separator: "/").first, host.contains(".") else { return [] }
        let name = host.split(separator: ".").first.map(String.init) ?? ""
        return name.count >= 3 ? [name] : []
    }

    /// The first time any of the phrases was said, word for word from the start of each.
    public static func firstPhrase(_ phrases: [String], in words: [TimedWord], label: String, localeIdentifier: String) -> SuflorProof? {
        let locale = Locale(identifier: localeIdentifier)
        let folded = words.map { fold($0.text, locale: locale) }
        let targets = phrases.map { $0.split(separator: " ").map { fold(String($0), locale: locale) }.filter { !$0.isEmpty } }
            .filter { !$0.isEmpty && ($0.count > 1 || $0[0].count >= 3) }
        for start in folded.indices {
            for target in targets where start + target.count <= folded.count {
                let matches = target.indices.allSatisfy { folded[start + $0].hasPrefix(target[$0]) }
                guard matches else { continue }
                let end = start + target.count - 1
                let quote = words[max(0, start - 6)...min(words.count - 1, end + 6)].map(\.text).joined(separator: " ")
                return SuflorProof(item: label, seconds: words[start].range.start.seconds, quote: quote)
            }
        }
        return nil
    }

    /// Every time each item was said, at most five times each.
    public static func every(_ items: [String], in words: [TimedWord], localeIdentifier: String) -> [SuflorProof] {
        var found: [SuflorProof] = []
        for item in items where !item.trimmingCharacters(in: .whitespaces).isEmpty {
            var rest = words
            var offset = 0
            for _ in 0..<5 {
                guard let hit = find([item], in: rest, localeIdentifier: localeIdentifier).first,
                      let index = rest.firstIndex(where: { $0.range.start.seconds >= hit.seconds })
                else { break }
                found.append(hit)
                offset += index + 1
                rest = Array(words.dropFirst(offset))
            }
        }
        return found.sorted { $0.seconds < $1.seconds }
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
    /// Where it was said that this is an ad — "iş birliği", "sponsored" — or nil when it was not.
    public var disclosure: SuflorProof?
    /// Where people were sent to the link, or nil.
    public var linkProof: SuflorProof?
    /// Every time a word that must not be said was said.
    public var avoidHits: [SuflorProof]
    /// The recording was listened to: a check that found nothing means it was not said, rather
    /// than not looked for.
    public var listened: Bool

    public init(plan: SuflorPlan, startedAt: Date = .now) {
        self.plan = plan
        self.startedAt = startedAt
        ticked = [:]
        proofs = []
        creator = ""
        disclosure = nil
        linkProof = nil
        avoidHits = []
        listened = false
    }

    /// Reads the whole video's words for the report: each item the brand asked for, the ad
    /// disclosure, the link, and any word that must not be said. Times are the words' own.
    public mutating func check(_ words: [TimedWord], localeIdentifier: String) {
        let brief = plan.brief
        let items = brief.mustSay + [brief.brand, brief.product].filter { !$0.isEmpty }
        proofs = SuflorProof.find(items, in: words, localeIdentifier: localeIdentifier)
        disclosure = SuflorProof.firstPhrase(SuflorProof.disclosurePhrases, in: words, label: "disclosure", localeIdentifier: localeIdentifier)
        // The address's own name counts as sending people there — unless it is just the brand's
        // name, which is said anyway.
        let linkNames = SuflorProof.names(inLink: brief.link).filter { $0 != brief.brand.lowercased() }
        linkProof = brief.link.isEmpty ? nil : SuflorProof.firstPhrase(
            SuflorProof.linkPhrases + linkNames,
            in: words,
            label: "link",
            localeIdentifier: localeIdentifier
        )
        avoidHits = SuflorProof.every(brief.avoid, in: words, localeIdentifier: localeIdentifier)
        listened = true
    }

    /// Every proof, for putting a frame on each.
    public var allProofs: [SuflorProof] {
        proofs + [disclosure, linkProof].compactMap { $0 } + avoidHits
    }

    /// Every second a frame is wanted for.
    public var proofSeconds: Set<Double> { Set(allProofs.map(\.seconds)) }

    /// Puts a frame on every proof, by the second it was said.
    public mutating func attachFrames(_ frames: [Double: Data]) {
        for index in proofs.indices { proofs[index].frame = frames[proofs[index].seconds] }
        if let found = disclosure { disclosure?.frame = frames[found.seconds] }
        if let found = linkProof { linkProof?.frame = frames[found.seconds] }
        for index in avoidHits.indices { avoidHits[index].frame = frames[avoidHits[index].seconds] }
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
