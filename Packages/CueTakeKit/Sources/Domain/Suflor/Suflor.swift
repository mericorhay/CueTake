import Foundation

// Ads: a brand's brief turned into the lines a creator reads on the studio's teleprompter, in
// their own voice, and after the take a report for the brand of what was said and when.
//
// Named after the suflör it grew out of — a prompter that floated over another app's camera. iOS
// darkens every floating window while a camera is open, so it could never work during a stream
// from the phone; the brief, the cards and the report moved into our own studio instead.

/// What the brand wants said.
public struct SuflorBrief: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// A video of its own about something else, with the ad woven in: the topic, a bridge,
        /// the ad, back out.
        case integrated
        /// A video that is the ad: short, straight to the product.
        case video

        /// Briefs from the live-stream prompter said "live": that is the woven-in kind.
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .integrated
        }
    }

    public enum Platform: String, Codable, CaseIterable, Sendable {
        case tiktok, instagram, youtube, other
    }

    public var kind: Kind
    public var platform: Platform
    public var brand: String
    public var product: String
    /// Words that must be said: a discount code, a link, a claim the brand insists on.
    public var mustSay: [String]
    public var tone: String
    /// What the video is about, so the bridge into the ad sounds like part of it.
    public var topic: String
    /// What the product is and what the brand wants said about it, usually pasted from the
    /// brand's own brief. The only source of facts about the product: without it, nothing is
    /// claimed about what the product is or does.
    public var details: String

    public init(
        kind: Kind = .integrated,
        platform: Platform = .tiktok,
        brand: String = "",
        product: String = "",
        mustSay: [String] = [],
        tone: String = "",
        topic: String = "",
        details: String = ""
    ) {
        self.kind = kind
        self.platform = platform
        self.brand = brand
        self.product = product
        self.mustSay = mustSay
        self.tone = tone
        self.topic = topic
        self.details = details
    }

    private enum CodingKeys: String, CodingKey {
        case kind, platform, brand, product, mustSay, tone, topic, details
    }

    /// Briefs saved before `details` existed, and with the live stream's ad timing, still open.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        platform = try container.decode(Platform.self, forKey: .platform)
        brand = try container.decode(String.self, forKey: .brand)
        product = try container.decode(String.self, forKey: .product)
        mustSay = try container.decode([String].self, forKey: .mustSay)
        tone = try container.decode(String.self, forKey: .tone)
        topic = try container.decode(String.self, forKey: .topic)
        details = try container.decodeIfPresent(String.self, forKey: .details) ?? ""
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

    /// Cards in the order a video uses them: the talk before the ad, then the ad as one block,
    /// then the close. Whatever order they were written in, the ad stays together, so the report
    /// can say where it began and ended.
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

    static func fold(_ text: String, locale: Locale) -> String {
        text.lowercased(with: locale)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: locale)
            .filter { $0.isLetter || $0.isNumber }
    }
}

/// What the take holds, for the report to the brand.
public struct SuflorSession: Codable, Hashable, Sendable {
    public var plan: SuflorPlan
    public var startedAt: Date
    public var endedAt: Date?
    /// Seconds into the video where the ad section begins and ends.
    public var adStartedAt: Double?
    public var adEndedAt: Double?
    /// Items the speaker ticked by hand, with the second they did.
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
