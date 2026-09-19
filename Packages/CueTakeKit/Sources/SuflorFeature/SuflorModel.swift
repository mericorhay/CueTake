import CoreText
import DesignSystem
import Domain
import Foundation
import Observation
import UIKit

/// The suflör from the brief to the report.
///
/// Three steps before the stage — what kind of shoot, the brand's brief, the cards — then the
/// stage itself, which floats into Picture in Picture when the speaker leaves for TikTok, then the
/// report for the brand.
@MainActor
@Observable
public final class SuflorModel {
    public enum Step: Int, CaseIterable, Sendable {
        case kind, brief, flow
    }

    public enum Stage: Sendable {
        case setup, live, report
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
    /// Listens to a saved recording of the stream and finds where each item was said.
    public typealias Verifier = (URL, [String]) async throws -> [SuflorProof]

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

    /// The page being edited and read on stage.
    public var cues: [SuflorCue] {
        get { cueSource == .ai ? aiCues : ownCues }
        set {
            if cueSource == .ai { aiCues = newValue } else { ownCues = newValue }
        }
    }
    public var wordsPerMinute: Double { didSet { save(); engine?.setWordsPerMinute(wordsPerMinute) } }
    public var textSize: Double { didSet { save(); relayout() } }

    public private(set) var isWriting = false
    public var writeError: String?
    /// True when the last failure was cloud AI being off, so the screen shows the switch.
    public private(set) var writeNeedsCloud = false
    /// Turns cloud AI on in Settings. Set by the app.
    public var allowCloud: (() -> Void)?
    public private(set) var session: SuflorSession?
    public private(set) var isFloating = false
    public private(set) var canFloat = false
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
    public var verifier: Verifier?
    public var localeIdentifier: String

    /// Takes the cards to the studio, to be read on our own teleprompter. Set by the app.
    public var onRecord: ((SuflorPlan) -> Void)?
    /// Makes the report from a take recorded in the studio. Set by the app.
    public var reporter: (() async -> SuflorSession?)?
    /// The cards have been recorded in the studio, so a report can be made from the take.
    public var hasRecording = false

    /// Where the report's proof comes from.
    public enum ReportSource: Sendable {
        /// A stream or video made in another app, saved and added from Photos.
        case stream
        /// A take recorded in our studio, already heard.
        case take
    }

    public private(set) var reportSource: ReportSource = .stream

    private(set) var engine: SuflorEngine?
    private var pip: SuflorPiP?
    private let defaults: UserDefaults

    public static let paceRange: ClosedRange<Double> = 80...220
    public static let sizeRange: ClosedRange<Double> = 20...44

    public init(localeIdentifier: String = Locale.current.identifier, defaults: UserDefaults = .standard) {
        self.localeIdentifier = localeIdentifier
        self.defaults = defaults
        let decoder = JSONDecoder()
        brief = defaults.data(forKey: Keys.brief).flatMap { try? decoder.decode(SuflorBrief.self, from: $0) } ?? SuflorBrief()
        aiCues = defaults.data(forKey: Keys.cues).flatMap { try? decoder.decode([SuflorCue].self, from: $0) } ?? []
        ownCues = defaults.data(forKey: Keys.ownCues).flatMap { try? decoder.decode([SuflorCue].self, from: $0) } ?? []
        cueSource = defaults.string(forKey: Keys.source).flatMap(CueSource.init(rawValue:)) ?? .ai
        let pace = defaults.double(forKey: Keys.pace)
        wordsPerMinute = pace > 0 ? pace : 130
        let size = defaults.double(forKey: Keys.size)
        textSize = size > 0 ? size : 32
        useMyVoice = defaults.bool(forKey: Keys.voice)
    }

    private enum Keys {
        static let brief = "suflor.brief"
        static let cues = "suflor.cues"
        static let ownCues = "suflor.cues.own"
        static let source = "suflor.cues.source"
        static let pace = "suflor.pace"
        // "suflor.size" held 30, written back on every save; 32 reads better from arm's length.
        static let size = "suflor.textSize"
        static let creator = "suflor.creator"
        static let voice = "suflor.voice"
    }

    private func save() {
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(brief), forKey: Keys.brief)
        defaults.set(try? encoder.encode(aiCues), forKey: Keys.cues)
        defaults.set(try? encoder.encode(ownCues), forKey: Keys.ownCues)
        defaults.set(cueSource.rawValue, forKey: Keys.source)
        defaults.set(wordsPerMinute, forKey: Keys.pace)
        defaults.set(textSize, forKey: Keys.size)
    }

    // MARK: - Setup

    public var plan: SuflorPlan { SuflorPlan(brief: brief, cues: cues) }
    public var canWrite: Bool { writer != nil && brief.isUsable }

    /// Minutes the cards take at the chosen pace.
    public var flowSeconds: Double { Double(plan.wordCount) / max(1, wordsPerMinute) * 60 }

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

    /// Cards from the brief without the server: a skeleton to write over.
    /// The creator's own page: five empty cards, one of each part a sponsored stream needs, the
    /// first time; whatever they wrote, every time after.
    public func writeMyself() {
        cueSource = .own
        if ownCues.allSatisfy({ $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            ownCues = [.opening, .topic, .bridge, .ad, .cta].map { SuflorCue(role: $0, text: "") }
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

    public func nudgePace(_ delta: Double) {
        wordsPerMinute = min(Self.paceRange.upperBound, max(Self.paceRange.lowerBound, wordsPerMinute + delta))
    }

    public func nudgeSize(_ delta: Double) {
        textSize = min(Self.sizeRange.upperBound, max(Self.sizeRange.lowerBound, textSize + delta))
    }

    // MARK: - Stage

    public var isReady: Bool { !plan.ordered.isEmpty }

    /// On stage: the clock starts, the floating window is ready to go.
    public func goOnStage() {
        let ordered = plan.ordered
        guard !ordered.isEmpty else { return }
        let layout = makeLayout(ordered)
        let adAt: Double? = switch brief.timing {
        case .minute(let minutes) where brief.kind == .live: SuflorClock.countdown + Double(minutes) * 60
        default: nil
        }
        let holds = brief.kind == .live && brief.timing != .none
        let engine = SuflorEngine(
            layout: layout,
            adAt: adAt,
            holds: holds,
            wordsPerMinute: wordsPerMinute,
            kind: brief.kind,
            text: Self.chromeText,
            fonts: Self.fonts(size: CGFloat(textSize))
        )
        engine.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        var session = SuflorSession(plan: SuflorPlan(brief: brief, cues: ordered))
        session.creator = defaults.string(forKey: Keys.creator) ?? ""
        self.session = session
        self.engine = engine
        let pip = SuflorPiP(engine: engine)
        pip.onActiveChange = { [weak self] active in
            self?.isFloating = active
            // The window has no play button: floating it is the start.
            if active, let engine = self?.engine, !engine.frame().clock.started {
                engine.setPlaying(true)
            }
        }
        pip.onPossibleChange = { [weak self] possible in self?.canFloat = possible }
        self.pip = pip
        engine.start()
        stage = .live
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// What the stage shows of the floating window.
    var windowView: SuflorFrameView? { pip?.sourceView }

    /// The preview is on screen: the window can now be made.
    func attachWindow() {
        pip?.attach()
    }

    private func handle(_ event: SuflorEngine.Event) {
        switch event {
        case .started:
            // The report's clock is the stream's, not the stage's.
            session?.startedAt = .now
        case .adStarted(let at): session?.adStartedAt = at
        case .adEnded(let at): session?.adEndedAt = at
        case .finished: break
        }
    }

    /// Floats the window, then opens the app the stream is on when it can be opened directly.
    /// Never a website: if the app will not open, the window floats and the speaker switches.
    public func floatAway() {
        pip?.start()
        let platform = brief.platform
        Task {
            // Long enough for the window to leave the preview before the other app covers it.
            try? await Task.sleep(for: .milliseconds(650))
            await Self.open(platform)
        }
    }

    public func bringBack() {
        pip?.stop()
    }

    public var isPlaying: Bool { engine?.isPlaying ?? false }

    public func togglePlaying() {
        guard let engine else { return }
        engine.setPlaying(!engine.isPlaying)
        pip?.invalidate()
    }

    public func skip(forward: Bool) {
        engine?.skip(forward: forward)
        pip?.invalidate()
    }

    public func startAd() {
        engine?.startAd()
        pip?.invalidate()
    }

    func drag(by delta: Double) {
        engine?.move(by: delta)
    }

    func setDragging(_ dragging: Bool) {
        engine?.setDragging(dragging)
    }

    /// Ticks an item the brand asked for, at the second it was said.
    public func tick(_ item: String) {
        guard var session, let engine else { return }
        if session.ticked[item] != nil {
            session.ticked[item] = nil
        } else {
            session.ticked[item] = max(0, engine.frame().clock.elapsed - SuflorClock.countdown)
        }
        self.session = session
    }

    /// Off the stage and on to the report.
    public func endStage() {
        reportSource = .stream
        session?.endedAt = .now
        if let engine, var session, session.adStartedAt != nil, session.adEndedAt == nil {
            session.adEndedAt = max(0, engine.frame().clock.elapsed - SuflorClock.countdown)
            self.session = session
        }
        pip?.detach()
        pip = nil
        engine?.stop()
        engine = nil
        isFloating = false
        UIApplication.shared.isIdleTimerDisabled = false
        stage = .report
    }

    /// Back to the cards, keeping them, for the next stream.
    public func leaveReport() {
        session = nil
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

    // MARK: - Studio

    /// Off to our studio with the cards as the script.
    public func record() {
        guard isReady else { return }
        onRecord?(plan)
    }

    /// Marks a segment as a card, so it can be found again in the project.
    public static let roleKey = "ad.role"
    /// The brief a project was made from, as JSON, in the project's metadata.
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

    /// The report for a take recorded in the studio: opened at once, filled in as the take is read.
    public func openTakeReport() async {
        reportSource = .take
        session = nil
        stage = .report
        await readTake()
    }

    /// Reads the studio take again: where the ad sits and where each item was said.
    public func readTake() async {
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

    // MARK: - Report

    /// Listens to the saved stream and finds each item the brand asked for in it.
    public func verify(recording url: URL) async {
        guard let verifier, var session, !isVerifying else { return }
        isVerifying = true
        verifyError = nil
        defer { isVerifying = false }
        let items = session.plan.brief.mustSay + [session.plan.brief.brand, session.plan.brief.product].filter { !$0.isEmpty }
        do {
            session.proofs = try await verifier(url, items)
            self.session = session
            if session.proofs.isEmpty {
                verifyError = String(localized: "suflor.verify.none", bundle: .module)
            }
        } catch {
            verifyError = String(localized: "suflor.verify.failed", bundle: .module)
        }
    }

    // MARK: - Drawing

    @ObservationIgnored private var previewCache: (key: Int, layout: SuflorLayout, fonts: SuflorFonts)?

    /// The cards laid out for the preview, remade only when the words or the size change.
    func previewLayout() -> (SuflorLayout, SuflorFonts) {
        var hasher = Hasher()
        hasher.combine(plan.ordered)
        hasher.combine(textSize)
        hasher.combine(brief.mustSay)
        let key = hasher.finalize()
        if let previewCache, previewCache.key == key { return (previewCache.layout, previewCache.fonts) }
        let fonts = Self.fonts(size: CGFloat(textSize))
        var ordered = plan.ordered
        if ordered.isEmpty { ordered = [SuflorCue(role: .opening, text: String(localized: "suflor.flow.empty", bundle: .module))] }
        let layout = SuflorLayout(cues: ordered, fontSize: CGFloat(textSize), fonts: fonts, labels: Self.roleLabels, highlights: brief.mustSay)
        previewCache = (key, layout, fonts)
        return (layout, fonts)
    }

    private func relayout() {
        guard let engine else { return }
        let ordered = plan.ordered
        engine.setLayout(makeLayout(ordered), holds: brief.kind == .live && brief.timing != .none)
    }

    private func makeLayout(_ cues: [SuflorCue]) -> SuflorLayout {
        SuflorLayout(
            cues: cues,
            fontSize: CGFloat(textSize),
            fonts: Self.fonts(size: CGFloat(textSize)),
            labels: Self.roleLabels,
            highlights: brief.mustSay
        )
    }

    static func fonts(size: CGFloat) -> SuflorFonts {
        // Registers the design system's faces before Core Text looks them up by name.
        _ = DS.custom(.sans, .semibold, 12)
        func font(_ family: DS.FontFamily, _ weight: DS.FontWeight, _ size: CGFloat) -> CTFont {
            CTFontCreateWithName(DS.fontName(family, weight) as CFString, size, nil)
        }
        return SuflorFonts(
            body: font(.sans, .semibold, size),
            label: font(.mono, .medium, max(10, size * 0.36)),
            chrome: font(.sans, .medium, 13),
            chromeBold: font(.mono, .medium, 12),
            display: font(.archivo, .extrabold, 64)
        )
    }

    static var roleLabels: [SuflorCue.Role: String] {
        Dictionary(uniqueKeysWithValues: SuflorCue.Role.allCases.map { ($0, $0.title) })
    }

    static var chromeText: SuflorChromeText {
        SuflorChromeText(
            live: String(localized: "suflor.chrome.live", bundle: .module),
            video: String(localized: "suflor.chrome.video", bundle: .module),
            toAd: String(localized: "suflor.chrome.toAd", bundle: .module),
            ad: String(localized: "suflor.chrome.ad", bundle: .module),
            paused: String(localized: "suflor.chrome.paused", bundle: .module),
            hold: String(localized: "suflor.chrome.hold", bundle: .module),
            holdManual: String(localized: "suflor.chrome.holdManual", bundle: .module),
            done: String(localized: "suflor.chrome.done", bundle: .module),
            ready: String(localized: "suflor.chrome.ready", bundle: .module)
        )
    }

    // MARK: - Leaving for the other app

    /// The app's own scheme only; each is tried until one opens. A web address is never used:
    /// it opens Safari when the app does not claim it, which is worse than staying put.
    private static func open(_ platform: SuflorBrief.Platform) async {
        let schemes: [String] = switch platform {
        case .tiktok: ["snssdk1233://", "tiktok://"]
        case .instagram: ["instagram://camera", "instagram://app"]
        case .youtube: ["youtube://"]
        case .other: []
        }
        for scheme in schemes {
            if let url = URL(string: scheme), await UIApplication.shared.open(url) { return }
        }
    }
}

extension SuflorCue.Role {
    /// How the card reads on the studio's teleprompter and in the editor.
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
