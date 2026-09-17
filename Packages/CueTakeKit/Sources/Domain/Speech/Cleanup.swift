import Foundation

/// The words people say while thinking, by language.
///
/// Two kinds. *Sounds* ("ııı", "um") are never meant and are always offered for the cut. *Words*
/// ("yani", "like") are sometimes meant, so they are offered only when the script says they were
/// not — or, without a script to ask, offered switched off.
public enum Disfluency {
    static let sounds: [String: Set<String>] = [
        "tr": ["ı", "ıh", "ıhı", "e", "eh", "ehm", "em", "hm", "hım", "ım", "m", "mhm", "öh", "ah"],
        "en": ["um", "uh", "uhm", "er", "erm", "ah", "hm", "m", "mhm", "eh", "uhh", "mm"],
    ]

    static let words: [String: Set<String>] = [
        "tr": ["yani", "şey", "işte", "hani", "falan", "filan", "aslında", "açıkçası"],
        "en": ["like", "so", "basically", "actually", "literally", "well", "right", "okay", "ok"],
    ]

    /// Two-word fillers, checked before single words.
    static let pairs: [String: Set<String>] = [
        "tr": ["şey yani", "ne diyordum", "nasıl desem"],
        "en": ["you know", "i mean", "kind of", "sort of", "you see"],
    ]

    static func language(_ locale: Locale) -> String {
        locale.language.languageCode?.identifier == "tr" ? "tr" : "en"
    }

    /// "ummm" → "um", "ıııı" → "ı": held sounds are the same sound.
    static func collapsed(_ key: String) -> String {
        var result = ""
        for character in key where character != result.last {
            result.append(character)
        }
        return result
    }

    public static func isSound(_ key: String, locale: Locale) -> Bool {
        guard !key.isEmpty, key.count <= 8 else { return false }
        let language = language(locale)
        let short = collapsed(key)
        return sounds[language]?.contains(short) == true || sounds[language]?.contains(key) == true
    }

    public static func isFillerWord(_ key: String, locale: Locale) -> Bool {
        words[language(locale)]?.contains(key) == true
    }

    public static func isFillerPair(_ first: String, _ second: String, locale: Locale) -> Bool {
        pairs[language(locale)]?.contains(first + " " + second) == true
    }
}

/// One thing the cleanup offers to cut from a take.
public struct CleanupItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable, CaseIterable, Codable {
        /// A long silence between words.
        case pause
        /// "ııı", "um", or a filler word the script does not have.
        case filler
        /// The same word said twice in a row.
        case repeated
        /// A sentence begun, dropped and begun again.
        case restart
        /// Words the script does not have, that are not filler. Often the best bit; off by default.
        case offScript
    }

    public var kind: Kind
    /// Take-relative seconds to remove.
    public var start: Double
    public var end: Double
    /// Spoken word indices the cut removes; nil for a pause.
    public var words: ClosedRange<Int>?
    public var text: String
    /// Whether the plan cuts it unless told otherwise.
    public var isOn: Bool

    public var id: String { "\(kind.rawValue)-\(Int((start * 1000).rounded()))-\(words.map { "\($0.lowerBound)" } ?? "p")" }
    public var duration: Double { max(0, end - start) }

    public init(kind: Kind, start: Double, end: Double, words: ClosedRange<Int>?, text: String, isOn: Bool) {
        self.kind = kind
        self.start = start
        self.end = end
        self.words = words
        self.text = text
        self.isOn = isOn
    }
}

public struct CleanupOptions: Hashable, Sendable {
    /// Silences longer than this are offered.
    public var pause: Double
    /// Air left each side of a cut, so it sounds like a breath rather than a splice.
    public var pad: Double

    public init(pause: Double = 0.6, pad: Double = 0.12) {
        self.pause = pause
        self.pad = pad
    }
}

/// Everything a cleanup of one take could cut, and what it would keep.
public struct CleanupPlan: Hashable, Sendable {
    public var segmentID: Segment.ID
    public var items: [CleanupItem]
    /// Nil when the take has no usable script to compare with.
    public var alignment: ScriptAlignment?
    /// Length of the take, in seconds.
    public var total: Double

    public init(segmentID: Segment.ID, items: [CleanupItem], alignment: ScriptAlignment?, total: Double) {
        self.segmentID = segmentID
        self.items = items
        self.alignment = alignment
        self.total = total
    }

    public var defaultSelection: Set<CleanupItem.ID> {
        Set(items.filter(\.isOn).map(\.id))
    }

    /// The stretches removed by the chosen items, merged.
    public func cuts(_ chosen: Set<CleanupItem.ID>) -> [ClosedRange<Double>] {
        let ranges = items
            .filter { chosen.contains($0.id) && $0.duration > 0.01 }
            .map { max(0, $0.start)...min(total, $0.end) }
            .sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Double>] = []
        for range in ranges {
            // Kept slivers shorter than this are not worth a clip of their own.
            if let last = merged.last, range.lowerBound <= last.upperBound + 0.14 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// What stays, in take-relative seconds.
    public func kept(_ chosen: Set<CleanupItem.ID>) -> [ClosedRange<Double>] {
        var spans: [ClosedRange<Double>] = []
        var cursor = 0.0
        for cut in cuts(chosen) {
            if cut.lowerBound - cursor > 0.13 { spans.append(cursor...cut.lowerBound) }
            cursor = max(cursor, cut.upperBound)
        }
        if total - cursor > 0.13 { spans.append(cursor...total) }
        return spans
    }

    public func saved(_ chosen: Set<CleanupItem.ID>) -> Double {
        total - kept(chosen).reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
    }

    public func count(_ kind: CleanupItem.Kind) -> Int {
        items.filter { $0.kind == kind }.count
    }
}

public enum CleanupPlanner {
    public static func plan(for segment: Segment, localeIdentifier: String, options: CleanupOptions = CleanupOptions()) -> CleanupPlan? {
        guard let take = segment.selectedTake,
              let words = take.transcript?.words, !words.isEmpty
        else { return nil }
        return plan(
            words: words,
            script: segment.script,
            total: take.sourceRange.duration.seconds,
            segmentID: segment.id,
            locale: Locale(identifier: localeIdentifier),
            options: options
        )
    }

    public static func plan(
        words: [TimedWord],
        script: String,
        total: Double,
        segmentID: Segment.ID,
        locale: Locale,
        options: CleanupOptions = CleanupOptions()
    ) -> CleanupPlan {
        let keys = words.map { ScriptAlignment.key($0.text, locale: locale) }
        let aligned = ScriptAlignment.align(words, script: script, locale: locale)
        let alignment: ScriptAlignment? = aligned.isUsable ? aligned : nil
        func isExtra(_ i: Int) -> Bool { alignment?.isExtra(i) ?? true }

        // What each spoken word is, decided once.
        enum Mark { case keep, sound, fillerWord(on: Bool), repeated(on: Bool), restart, offScript }
        var marks = [Mark](repeating: .keep, count: words.count)

        var i = 0
        while i < words.count {
            if isExtra(i), i + 1 < words.count, isExtra(i + 1), Disfluency.isFillerPair(keys[i], keys[i + 1], locale: locale) {
                marks[i] = .fillerWord(on: alignment != nil)
                marks[i + 1] = .fillerWord(on: alignment != nil)
                i += 2
                continue
            }
            if Disfluency.isSound(keys[i], locale: locale), isExtra(i) {
                marks[i] = .sound
            } else if isExtra(i), Disfluency.isFillerWord(keys[i], locale: locale) {
                marks[i] = .fillerWord(on: alignment != nil)
            }
            i += 1
        }

        func isFiller(_ i: Int) -> Bool {
            switch marks[i] {
            case .sound, .fillerWord: true
            default: false
            }
        }

        // The same word twice: the first goes. Without a script this is a guess — Turkish doubles
        // words on purpose ("yavaş yavaş", "çok çok") — so there it is only offered.
        let repeatsOn = alignment != nil || Disfluency.language(locale) != "tr"
        for i in words.indices.dropLast() where !keys[i].isEmpty && !isFiller(i) {
            guard let next = ((i + 1)..<words.count).first(where: { !isFiller($0) }) else { continue }
            let same = ScriptAlignment.similarity(keys[i], keys[next]) >= 0.9
            if let alignment {
                // With a script, only a copy the script does not want, and a word cut short counts.
                guard alignment.isExtra(i) else { continue }
                let cutShort = keys[i].count >= 2 && keys[next].hasPrefix(keys[i])
                guard same || cutShort || ScriptAlignment.similarity(keys[i], keys[next]) >= 0.75 else { continue }
            } else {
                guard same else { continue }
            }
            marks[i] = .repeated(on: repeatsOn)
        }

        // Runs of extra words: a restart when the next words say the same thing again, otherwise
        // an ad-lib.
        if let alignment {
            var start: Int?
            for i in words.indices.map({ $0 }) + [words.count] {
                let extra = i < words.count && alignment.isExtra(i)
                if extra {
                    if start == nil { start = i }
                    continue
                }
                guard let first = start else { continue }
                start = nil
                // Words already taken as repeats are settled; a run of only those is not a restart.
                let run = (first..<i).filter { index in
                    if isFiller(index) { return false }
                    if case .repeated = marks[index] { return false }
                    return true
                }
                guard !run.isEmpty else { continue }
                let isRestart: Bool = {
                    guard run.count <= 10, i < words.count else { return false }
                    let following = (i..<min(words.count, i + run.count + 1)).filter { !isFiller($0) }
                    guard let opener = following.first else { return false }
                    return ScriptAlignment.similarity(keys[run[0]], keys[opener]) > 0
                        || keys[opener].hasPrefix(keys[run[0]]) && keys[run[0]].count >= 2
                }()
                for index in run {
                    marks[index] = isRestart ? .restart : .offScript
                }
                // Filler inside a restart goes with it.
                if isRestart {
                    for index in first..<i where isFiller(index) { marks[index] = .restart }
                }
            }
        }

        // Runs of the same mark become one item each.
        var items: [CleanupItem] = []
        var runStart = 0
        func kind(_ mark: Mark) -> (kind: CleanupItem.Kind, on: Bool)? {
            switch mark {
            case .keep: return nil
            case .sound: return (.filler, true)
            case .fillerWord(let on): return (.filler, on)
            case .repeated(let on): return (.repeated, on)
            case .restart: return (.restart, true)
            case .offScript: return (.offScript, false)
            }
        }
        while runStart < words.count {
            guard let found = kind(marks[runStart]) else {
                runStart += 1
                continue
            }
            let itemKind = found.kind
            let on = found.on
            var runEnd = runStart
            while runEnd + 1 < words.count, let next = kind(marks[runEnd + 1]), next.kind == itemKind, next.on == on {
                runEnd += 1
            }
            let before = runStart > 0 ? words[runStart - 1].range.end.seconds : 0
            let after = runEnd + 1 < words.count ? words[runEnd + 1].range.start.seconds : total
            let first = words[runStart].range.start.seconds
            let last = words[runEnd].range.end.seconds
            // Keep a little air after the word before and before the word after, never more than
            // half of the silence there was.
            let lower = min(first, before + min(options.pad, max(0, first - before) / 2))
            let upper = max(last, after - min(options.pad, max(0, after - last) / 2))
            items.append(CleanupItem(
                kind: itemKind,
                start: max(0, lower),
                end: min(total, upper),
                words: runStart...runEnd,
                text: words[runStart...runEnd].map(\.text).joined(separator: " "),
                isOn: on
            ))
            runStart = runEnd + 1
        }

        // Long silences between words, and before the first and after the last.
        var edges: [(Double, Double)] = zip(words, words.dropFirst()).map { ($0.range.end.seconds, $1.range.start.seconds) }
        edges.insert((0, words[0].range.start.seconds), at: 0)
        edges.append((words[words.count - 1].range.end.seconds, total))
        for (index, edge) in edges.enumerated() {
            let (from, to) = edge
            guard to - from > options.pause else { continue }
            let lower = index == 0 ? from : from + options.pad
            let upper = index == edges.count - 1 ? to : to - options.pad
            guard upper - lower > 0.05 else { continue }
            items.append(CleanupItem(kind: .pause, start: lower, end: upper, words: nil, text: "", isOn: true))
        }

        items.sort { $0.start < $1.start }
        return CleanupPlan(segmentID: segmentID, items: items, alignment: alignment, total: total)
    }
}

/// Where a cleaned clip came from, so the cut can be undone at any time rather than only by undo.
public struct CleanupOrigin: Hashable, Sendable, Codable {
    /// Shared by every piece one cleanup made.
    public var group: UUID
    /// The script the clip had before it was cut.
    public var script: String
    /// The takes and choice before the cut. Only the first piece carries them.
    public var takes: [Take]?
    public var selectedTakeID: Take.ID?

    public init(group: UUID, script: String, takes: [Take]? = nil, selectedTakeID: Take.ID? = nil) {
        self.group = group
        self.script = script
        self.takes = takes
        self.selectedTakeID = selectedTakeID
    }

    public var originalTake: Take? {
        takes?.first { $0.id == selectedTakeID }
    }
}

/// How good one take is, from what was said.
public struct TakeScore: Hashable, Sendable {
    /// Share of the script said as written.
    public var accuracy: Double
    /// Few fillers, restarts and repeats.
    public var fluency: Double
    /// Near a natural speaking rate.
    public var pace: Double
    /// How sure the recogniser was, as a proxy for clear speech.
    public var clarity: Double
    /// False when the take has no script to compare with; accuracy is then left out.
    public var hasScript: Bool

    public var total: Double {
        hasScript
            ? 0.45 * accuracy + 0.3 * fluency + 0.15 * pace + 0.1 * clarity
            : 0.6 * fluency + 0.25 * pace + 0.15 * clarity
    }

    public static func score(_ take: Take, script: String, localeIdentifier: String) -> TakeScore? {
        guard let words = take.transcript?.words, words.count >= 2 else { return nil }
        let plan = CleanupPlanner.plan(
            words: words,
            script: script,
            total: take.sourceRange.duration.seconds,
            segmentID: UUID(),
            locale: Locale(identifier: localeIdentifier)
        )
        var slips = 0
        for item in plan.items where item.isOn && item.kind != .pause && item.kind != .offScript {
            slips += item.words?.count ?? 0
        }
        let fluency = max(0, 1 - Double(slips) / Double(words.count) * 4)

        let speaking = max(0.5, (words.last?.range.end.seconds ?? 0) - (words.first?.range.start.seconds ?? 0))
        let rate = Double(words.count) / speaking * 60
        let target = SpeakingRate.wordsPerMinute(forLocaleIdentifier: localeIdentifier)
        let pace = max(0, 1 - abs(rate - target) / target)

        let sure = words.compactMap(\.confidence)
        let clarity = sure.isEmpty ? 0.8 : sure.reduce(0, +) / Double(sure.count)

        return TakeScore(
            accuracy: plan.alignment?.accuracy ?? 0,
            fluency: fluency,
            pace: pace,
            clarity: clarity,
            hasScript: plan.alignment != nil
        )
    }
}

extension Segment {
    /// The take that reads best, when there is more than one with words to judge.
    public func bestTake(localeIdentifier: String) -> (id: Take.ID, score: TakeScore)? {
        let scored = takes.compactMap { take in
            TakeScore.score(take, script: script, localeIdentifier: localeIdentifier).map { (take.id, $0) }
        }
        guard scored.count >= 2, let best = scored.max(by: { $0.1.total < $1.1.total }) else { return nil }
        return (id: best.0, score: best.1)
    }
}
