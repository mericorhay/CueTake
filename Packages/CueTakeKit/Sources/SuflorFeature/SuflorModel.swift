import DesignSystem
import Domain
import Foundation
import Observation
import UIKit

/// An ad from the brief to the report.
///
/// Three steps — what kind of video, the brand's brief, the cards — then the studio: the cards
/// become the project's segments and are read on its teleprompter. After the take the report for
/// the brand is made from the recording itself: where the ad sits in the video and where each
/// thing the brand asked for was said, with a frame from that moment.
@MainActor
@Observable
public final class SuflorModel {
    public enum Step: Int, CaseIterable, Sendable {
        case kind, brief, flow
    }

    public enum Stage: Sendable {
        case setup, report
    }

    /// Why the server could not write the cards, in terms the screen can act on.
    public enum WriteError: Error, Sendable {
        /// Cloud AI is off in Settings; the screen offers to turn it on.
        case cloudOff
        case offline
        case server(Int)
        case empty
    }

    /// Writes cards from a brief on the server. Nil in a build without the assistant.
    public typealias Writer = (SuflorBrief, String, String?) async throws -> [SuflorCue]
    /// Reads the recorded take: the ad's place in the video and each item heard in it.
    public typealias Reporter = () async -> SuflorSession?

    public var step: Step = .kind
    public private(set) var stage: Stage = .setup
    public var brief: SuflorBrief { didSet { save() } }
    /// Two flows kept side by side: the one the server wrote and the creator's own. Switching
    /// pages never loses either.
    public enum CueSource: String, CaseIterable, Sendable {
        case ai, own
    }

    public var aiCues: [SuflorCue] { didSet { save() } }
    public var ownCues: [SuflorCue] { didSet { save() } }
    public var cueSource: CueSource { didSet { save() } }

    /// The page being edited and taken to the studio.
    public var cues: [SuflorCue] {
        get { cueSource == .ai ? aiCues : ownCues }
        set {
            if cueSource == .ai { aiCues = newValue } else { ownCues = newValue }
        }
    }

    public private(set) var isWriting = false
    public var writeError: String?
    /// True when the last failure was cloud AI being off, so the screen shows the switch.
    public private(set) var writeNeedsCloud = false
    /// Turns cloud AI on in Settings. Set by the app.
    public var allowCloud: (() -> Void)?
    public private(set) var session: SuflorSession?
    public private(set) var isVerifying = false
    public var verifyError: String?
    /// A new card written by the model, for the stagger as they land.
    public private(set) var freshCues: Set<UUID> = []

    public var writer: Writer?
    /// Gathers the creator's speech from their videos. Set by the app.
    public var voiceLoader: (() async -> String?)?
    /// Write the cards in the creator's own voice, from their videos.
    public var useMyVoice: Bool { didSet { defaults.set(useMyVoice, forKey: Keys.voice) } }
    /// Words of the creator's speech found; nil until looked for.
    public private(set) var voiceWords: Int?
    @ObservationIgnored private var voiceSample: String?
    public var localeIdentifier: String

    /// Takes the cards to the studio. Set by the app.
    public var onRecord: ((SuflorPlan) -> Void)?
    /// Makes the report from what was recorded. Set by the app.
    public var reporter: Reporter?
    /// The ad has been recorded, so a report can be made. Set by the app.
    public var hasRecording = false

    private let defaults: UserDefaults

    public init(localeIdentifier: String = Locale.current.identifier, defaults: UserDefaults = .standard) {
        self.localeIdentifier = localeIdentifier
        self.defaults = defaults
        let decoder = JSONDecoder()
        brief = defaults.data(forKey: Keys.brief).flatMap { try? decoder.decode(SuflorBrief.self, from: $0) } ?? SuflorBrief()
        aiCues = defaults.data(forKey: Keys.cues).flatMap { try? decoder.decode([SuflorCue].self, from: $0) } ?? []
        ownCues = defaults.data(forKey: Keys.ownCues).flatMap { try? decoder.decode([SuflorCue].self, from: $0) } ?? []
        cueSource = defaults.string(forKey: Keys.source).flatMap(CueSource.init(rawValue:)) ?? .ai
        useMyVoice = defaults.bool(forKey: Keys.voice)
    }

    private enum Keys {
        static let brief = "suflor.brief"
        static let cues = "suflor.cues"
        static let ownCues = "suflor.cues.own"
        static let source = "suflor.cues.source"
        static let creator = "suflor.creator"
        static let voice = "suflor.voice"
    }

    private func save() {
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(brief), forKey: Keys.brief)
        defaults.set(try? encoder.encode(aiCues), forKey: Keys.cues)
        defaults.set(try? encoder.encode(ownCues), forKey: Keys.ownCues)
        defaults.set(cueSource.rawValue, forKey: Keys.source)
    }

    // MARK: - Setup

    public var plan: SuflorPlan { SuflorPlan(brief: brief, cues: cues) }
    public var canWrite: Bool { writer != nil && brief.isUsable }

    /// Seconds the cards take read at an ordinary pace for the language.
    public var flowSeconds: Double {
        Double(plan.wordCount) / SpeakingRate.wordsPerMinute(forLocaleIdentifier: localeIdentifier) * 60
    }

    public func next() {
        guard let following = Step(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    public func back() -> Bool {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return false }
        step = previous
        return true
    }

    /// Has the server write the cards, landing them one after another.
    public func write() async {
        guard let writer, !isWriting else { return }
        isWriting = true
        writeError = nil
        writeNeedsCloud = false
        defer { isWriting = false }
        do {
            let voice = useMyVoice ? voiceSample : nil
            let written = try await writer(brief, localeIdentifier, voice)
            guard !written.isEmpty else {
                writeError = String(localized: "suflor.write.empty", bundle: .module)
                return
            }
            cueSource = .ai
            aiCues = []
            step = .flow
            for cue in SuflorPlan(brief: brief, cues: written).ordered {
                try? await Task.sleep(for: .milliseconds(110))
                freshCues.insert(cue.id)
                aiCues.append(cue)
            }
            try? await Task.sleep(for: .seconds(1.2))
            freshCues = []
        } catch WriteError.cloudOff {
            writeNeedsCloud = true
            writeError = String(localized: "suflor.write.cloudOff", bundle: .module)
        } catch WriteError.offline {
            writeError = String(localized: "suflor.write.offline", bundle: .module)
        } catch WriteError.server(let status) {
            writeError = String(localized: "suflor.write.server \(status)", bundle: .module)
        } catch {
            writeError = String(localized: "suflor.write.empty", bundle: .module)
        }
    }

    /// Looks through the creator's videos for their speech. Cheap to repeat: the brief step asks
    /// each time it opens, so a video transcribed a minute ago counts.
    public func refreshVoice() async {
        guard let voiceLoader else {
            voiceWords = 0
            return
        }
        voiceSample = await voiceLoader()
        voiceWords = SuflorVoice.wordCount(voiceSample)
        if voiceWords == 0 { useMyVoice = false }
    }

    /// Turns cloud AI on and tries again.
    public func allowCloudAndWrite() async {
        allowCloud?()
        writeNeedsCloud = false
        await write()
    }

    /// The creator's own page: an empty card for each part the kind of video needs, the first
    /// time; whatever they wrote, every time after.
    public func writeMyself() {
        cueSource = .own
        if ownCues.allSatisfy({ $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let roles: [SuflorCue.Role] = brief.kind == .video
                ? [.opening, .ad, .cta, .closing]
                : [.opening, .topic, .bridge, .ad, .cta]
            ownCues = roles.map { SuflorCue(role: $0, text: "") }
        }
        step = .flow
    }

    public func show(_ source: CueSource) {
        cueSource = source
    }

    public func add(_ role: SuflorCue.Role) {
        cues.append(SuflorCue(role: role, text: ""))
    }

    public func remove(_ cue: SuflorCue) {
        cues.removeAll { $0.id == cue.id }
    }

    public func move(_ cue: SuflorCue, by delta: Int) {
        guard let index = cues.firstIndex(where: { $0.id == cue.id }) else { return }
        let target = index + delta
        guard cues.indices.contains(target) else { return }
        cues.swapAt(index, target)
    }

    // MARK: - Studio

    public var isReady: Bool { !plan.ordered.isEmpty }

    /// Off to the studio with the cards as the script.
    public func record() {
        guard isReady else { return }
        onRecord?(plan)
    }

    /// Marks a segment as a card of an ad, so it can be found again in the project.
    public static let roleKey = "ad.role"
    /// The brief an ad project was made from, as JSON, in the project's metadata.
    public static let briefKey = "ad.brief"

    /// The cards as the project's segments, each keeping its card's identity. A card that is
    /// already a segment keeps its takes: its words are updated, nothing that was shot is lost.
    /// A segment whose card is gone goes with it, unless something was shot for it.
    public static func segments(for plan: SuflorPlan, merging existing: [Segment], localeIdentifier: String) -> [Segment] {
        let perMinute = SpeakingRate.wordsPerMinute(forLocaleIdentifier: localeIdentifier)
        var result: [Segment] = plan.ordered.map { cue in
            let words = ScriptText.words(in: cue.text).count
            let estimate = MediaTime(seconds: max(1, Double(words) / perMinute * 60))
            if var segment = existing.first(where: { $0.id == cue.id }) {
                segment.role = cue.role.segmentRole
                segment.title = cue.role.title
                segment.script = cue.text
                if segment.takes.isEmpty { segment.estimatedDuration = estimate }
                segment.metadata[roleKey] = cue.role.rawValue
                return segment
            }
            return Segment(
                id: cue.id,
                role: cue.role.segmentRole,
                title: cue.role.title,
                script: cue.text,
                estimatedDuration: estimate,
                metadata: [roleKey: cue.role.rawValue]
            )
        }
        let kept = Set(result.map(\.id))
        result += existing.filter { !kept.contains($0.id) && !$0.takes.isEmpty }
        return result
    }

    // MARK: - Report

    /// Opens the report and reads the take for it.
    public func openReport() async {
        session = nil
        stage = .report
        await verify()
    }

    /// Reads the recording again: where the ad sits and where each item was said.
    public func verify() async {
        guard let reporter, !isVerifying else { return }
        isVerifying = true
        verifyError = nil
        defer { isVerifying = false }
        guard var made = await reporter() else {
            verifyError = String(localized: "suflor.verify.failed", bundle: .module)
            return
        }
        made.creator = defaults.string(forKey: Keys.creator) ?? ""
        session = made
        if !made.plan.brief.mustSay.isEmpty, made.proofs.isEmpty {
            verifyError = String(localized: "suflor.verify.none", bundle: .module)
        }
    }

    /// Back to the cards, keeping them.
    public func leaveReport() {
        stage = .setup
        step = .flow
    }

    public var creator: String {
        get { session?.creator ?? "" }
        set {
            session?.creator = newValue
            defaults.set(newValue, forKey: Keys.creator)
        }
    }
}

extension SuflorCue.Role {
    /// How the card reads on the teleprompter and in the editor.
    public var segmentRole: SegmentRole {
        switch self {
        case .opening: .hook
        case .topic: .mainPoint
        case .cta: .callToAction
        default: .custom(title)
        }
    }

    public var title: String {
        switch self {
        case .opening: String(localized: "suflor.role.opening", bundle: .module)
        case .topic: String(localized: "suflor.role.topic", bundle: .module)
        case .bridge: String(localized: "suflor.role.bridge", bundle: .module)
        case .ad: String(localized: "suflor.role.ad", bundle: .module)
        case .cta: String(localized: "suflor.role.cta", bundle: .module)
        case .rescue: String(localized: "suflor.role.rescue", bundle: .module)
        case .closing: String(localized: "suflor.role.closing", bundle: .module)
        }
    }
}
