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

    /// Writes cards from a brief on the server. Nil in a build without the assistant.
    public typealias Writer = (SuflorBrief, String) async throws -> [SuflorCue]
    /// Listens to a saved recording of the stream and finds where each item was said.
    public typealias Verifier = (URL, [String]) async throws -> [SuflorProof]

    public var step: Step = .kind
    public private(set) var stage: Stage = .setup
    public var brief: SuflorBrief { didSet { save() } }
    public var cues: [SuflorCue] { didSet { save() } }
    public var wordsPerMinute: Double { didSet { save(); engine?.setWordsPerMinute(wordsPerMinute) } }
    public var textSize: Double { didSet { save(); relayout() } }

    public private(set) var isWriting = false
    public var writeError: String?
    public private(set) var session: SuflorSession?
    public private(set) var isFloating = false
    public private(set) var canFloat = false
    public private(set) var isVerifying = false
    public var verifyError: String?
    /// A new card written by the model, for the stagger as they land.
    public private(set) var freshCues: Set<UUID> = []

    public var writer: Writer?
    public var verifier: Verifier?
    public var localeIdentifier: String

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
        cues = defaults.data(forKey: Keys.cues).flatMap { try? decoder.decode([SuflorCue].self, from: $0) } ?? []
        let pace = defaults.double(forKey: Keys.pace)
        wordsPerMinute = pace > 0 ? pace : 130
        let size = defaults.double(forKey: Keys.size)
        textSize = size > 0 ? size : 30
    }

    private enum Keys {
        static let brief = "suflor.brief"
        static let cues = "suflor.cues"
        static let pace = "suflor.pace"
        static let size = "suflor.size"
        static let creator = "suflor.creator"
    }

    private func save() {
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(brief), forKey: Keys.brief)
        defaults.set(try? encoder.encode(cues), forKey: Keys.cues)
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
        defer { isWriting = false }
        do {
            let written = try await writer(brief, localeIdentifier)
            guard !written.isEmpty else {
                writeError = String(localized: "suflor.write.empty", bundle: .module)
                return
            }
            cues = []
            step = .flow
            for cue in SuflorPlan(brief: brief, cues: written).ordered {
                try? await Task.sleep(for: .milliseconds(110))
                freshCues.insert(cue.id)
                cues.append(cue)
            }
            try? await Task.sleep(for: .seconds(1.2))
            freshCues = []
        } catch {
            writeError = String(localized: "suflor.write.failed", bundle: .module)
        }
    }

    /// Cards from the brief without the server: a skeleton to write over.
    public func useTemplate() {
        cues = SuflorTemplate.cues(for: brief)
        step = .flow
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
        pip.onActiveChange = { [weak self] active in self?.isFloating = active }
        pip.onPossibleChange = { [weak self] possible in self?.canFloat = possible }
        self.pip = pip
        engine.start()
        stage = .live
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// The preview is on screen: the window can now be made.
    func attachWindow() {
        pip?.attach()
    }

    private func handle(_ event: SuflorEngine.Event) {
        switch event {
        case .adStarted(let at): session?.adStartedAt = at
        case .adEnded(let at): session?.adEndedAt = at
        case .finished: break
        }
    }

    /// Floats the window and opens the app the stream is on.
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
            done: String(localized: "suflor.chrome.done", bundle: .module)
        )
    }

    // MARK: - Leaving for the other app

    /// The app's own link first — it opens the app when installed — then its scheme.
    private static func open(_ platform: SuflorBrief.Platform) async {
        let links: [(String, String)] = switch platform {
        case .tiktok: [("https://www.tiktok.com/", "tiktok://")]
        case .instagram: [("https://www.instagram.com/", "instagram://camera")]
        case .youtube: [("https://www.youtube.com/", "youtube://")]
        case .other: []
        }
        for (web, scheme) in links {
            if let url = URL(string: web), await UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { return }
            if let url = URL(string: scheme), await UIApplication.shared.open(url) { return }
        }
    }
}

extension SuflorCue.Role {
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

/// Cards to write over when there is no server to write them.
enum SuflorTemplate {
    static func cues(for brief: SuflorBrief) -> [SuflorCue] {
        let product = brief.product.isEmpty ? brief.brand : brief.product
        let brand = brief.brand.isEmpty ? brief.product : brief.brand
        let topic = brief.topic.isEmpty ? String(localized: "suflor.template.topicFallback", bundle: .module) : brief.topic
        let must = brief.mustSay.joined(separator: " · ")
        func text(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }
        var cues: [SuflorCue] = []
        if brief.kind == .live {
            cues.append(SuflorCue(role: .opening, text: String(format: text("suflor.template.opening"), topic)))
            cues.append(SuflorCue(role: .topic, text: text("suflor.template.topic1")))
            cues.append(SuflorCue(role: .topic, text: text("suflor.template.topic2")))
        } else {
            cues.append(SuflorCue(role: .opening, text: String(format: text("suflor.template.hook"), product)))
        }
        cues.append(SuflorCue(role: .bridge, text: String(format: text("suflor.template.bridge"), product)))
        cues.append(SuflorCue(role: .ad, text: String(format: text("suflor.template.ad1"), brand, product)))
        cues.append(SuflorCue(role: .ad, text: text("suflor.template.ad2")))
        if !must.isEmpty {
            cues.append(SuflorCue(role: .cta, text: String(format: text("suflor.template.cta"), must)))
        }
        if brief.kind == .live {
            cues.append(SuflorCue(role: .rescue, text: text("suflor.template.rescue1")))
            cues.append(SuflorCue(role: .rescue, text: text("suflor.template.rescue2")))
        }
        cues.append(SuflorCue(role: .closing, text: text("suflor.template.closing")))
        return cues
    }
}
