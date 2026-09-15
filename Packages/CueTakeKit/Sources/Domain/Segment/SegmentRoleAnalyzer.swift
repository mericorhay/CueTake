import Foundation

/// A local, deliberately conservative reading of a video's structure.
///
/// A segment's place in the timeline is useful context, but it is never enough on its own: the
/// last line is not automatically a CTA and the first line is not automatically a hook. The
/// analyser asks for language signals as well, then only returns changes it can support strongly.
public enum SegmentRoleAnalyzer {
    public struct Suggestion: Identifiable, Hashable, Sendable {
        public let segmentID: Segment.ID
        public let role: SegmentRole
        /// 0...1. Kept with the result so a caller can choose how cautious its UI should be.
        public let confidence: Double

        public var id: Segment.ID { segmentID }

        public init(segmentID: Segment.ID, role: SegmentRole, confidence: Double) {
            self.segmentID = segmentID
            self.role = role
            self.confidence = confidence
        }
    }

    /// Returns only high-confidence changes. A selected take's transcript wins when it has real
    /// words, because the editor should describe what was said rather than a script that changed
    /// before recording.
    public static func suggestions(
        for segments: [Segment],
        localeIdentifier: String
    ) -> [Suggestion] {
        guard !segments.isEmpty else { return [] }

        let readings = segments.enumerated().map { index, segment in
            Reading(
                index: index,
                segment: segment,
                text: spokenText(for: segment),
                localeIdentifier: localeIdentifier,
                total: segments.count
            )
        }

        var result: [Suggestion] = []

        // A hook and a CTA frame the whole video. Pick one strongest candidate for each rather
        // than labelling every enthusiastic opening or closing sentence the same way.
        if let hook = readings
            .filter({ $0.hook.score >= 0.62 && $0.segment.role != .hook })
            .max(by: { $0.hook.score < $1.hook.score }) {
            result.append(Suggestion(segmentID: hook.segment.id, role: .hook, confidence: hook.hook.score))
        }

        if let cta = readings
            .filter({ $0.cta.hasExplicitAction && $0.cta.score >= 0.68 && $0.segment.role != .callToAction })
            .max(by: { $0.cta.score < $1.cta.score }) {
            result.append(Suggestion(segmentID: cta.segment.id, role: .callToAction, confidence: cta.cta.score))
        }

        let alreadySuggested = Set(result.map(\.segmentID))
        for reading in readings where !alreadySuggested.contains(reading.segment.id) {
            if reading.example >= 0.66, reading.segment.role != .example {
                result.append(Suggestion(segmentID: reading.segment.id, role: .example, confidence: reading.example))
            } else if reading.intro >= 0.66, reading.segment.role != .intro {
                result.append(Suggestion(segmentID: reading.segment.id, role: .intro, confidence: reading.intro))
            } else if reading.mainPoint >= 0.72, reading.segment.role != .mainPoint {
                result.append(Suggestion(segmentID: reading.segment.id, role: .mainPoint, confidence: reading.mainPoint))
            }
        }

        return result.sorted { $0.confidence > $1.confidence }
    }
}

private extension SegmentRoleAnalyzer {
    struct Score {
        var score: Double
        var hasExplicitAction = false
    }

    struct Reading {
        let index: Int
        let segment: Segment
        let normalized: String
        let words: [String]
        let position: Double

        init(index: Int, segment: Segment, text: String, localeIdentifier: String, total: Int) {
            self.index = index
            self.segment = segment
            normalized = Self.normalized(text, localeIdentifier: localeIdentifier)
            words = normalized.split(separator: " ").map(String.init)
            position = total > 1 ? Double(index) / Double(total - 1) : 0
        }

        var hook: Score {
            let hooks = ["dur", "bunu", "neden", "nasil", "kimse", "sirr", "yanlis", "simdi", "stop", "wait", "why", "how", "secret", "mistake"]
            let ctas = Self.ctaTerms
            let hookHits = hits(in: hooks)
            let hasQuestion = normalized.contains("?")
            let hasExcitement = normalized.contains("!")
            var score = position <= 0.30 ? 0.24 : 0
            score += min(Double(hookHits) * 0.16, 0.40)
            if hasQuestion || hasExcitement { score += 0.16 }
            if (3...24).contains(words.count) { score += 0.08 }
            if hits(in: ctas) > 0 { score -= 0.32 }
            return Score(score: min(max(score, 0), 1))
        }

        var cta: Score {
            let actionHits = hits(in: Self.ctaTerms)
            let directed = containsAny(["sen", "siz", "you", "yorum", "comment", "profil", "bio", "link"])
            var score = min(Double(actionHits) * 0.26, 0.62)
            if position >= 0.60 { score += 0.20 }
            if directed { score += 0.10 }
            // "Follow for more" and "takip et" are complete closing requests even without a
            // second action word. Treat the phrase as evidence, not the clip's final position.
            if containsAny(["takip et", "abone ol", "follow for", "follow me", "subscribe for", "comment below"]) {
                score += 0.16
            }
            if normalized.contains("!") { score += 0.05 }
            return Score(score: min(max(score, 0), 1), hasExplicitAction: actionHits > 0)
        }

        var intro: Double {
            let signals = ["bugun", "bu videoda", "anlatacagim", "gosterecegim", "inceleyecegiz", "today", "in this video", "i will show", "lets"]
            guard position <= 0.45 else { return 0 }
            let matches = hits(in: signals)
            return min(0.22 + Double(matches) * 0.28, 1)
        }

        var example: Double {
            let signals = ["ornek", "mesela", "ornegin", "diyelim", "varsayalim", "example", "for instance", "imagine", "say"]
            let matches = hits(in: signals)
            return matches == 0 ? 0 : min(0.45 + Double(matches) * 0.28, 1)
        }

        var mainPoint: Double {
            let signals = ["adim", "once", "sonra", "ilk", "ikinci", "ucuncu", "because", "therefore", "step", "first", "second", "then"]
            let matches = hits(in: signals)
            guard matches > 0, position > 0.10, position < 0.90 else { return 0 }
            return min(0.48 + Double(matches) * 0.16, 0.92)
        }

        func hits(in phrases: [String]) -> Int {
            phrases.reduce(into: 0) { count, phrase in
                if normalized.contains(phrase) { count += 1 }
            }
        }

        func containsAny(_ phrases: [String]) -> Bool {
            phrases.contains { normalized.contains($0) }
        }

        static let ctaTerms = ["takip", "abone", "yorum", "begen", "kaydet", "paylas", "link", "profil", "haber ver", "follow", "subscribe", "comment", "like", "save", "share", "bio"]

        static func normalized(_ text: String, localeIdentifier: String) -> String {
            let locale = Locale(identifier: localeIdentifier)
            let lowered = text.lowercased(with: locale)
            let folded = lowered.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: locale)
            return folded.unicodeScalars.map { scalar in
                CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespaces.contains(scalar) || scalar == "?" || scalar == "!"
                    ? String(scalar)
                    : " "
            }.joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }

    static func spokenText(for segment: Segment) -> String {
        let transcript = segment.selectedTake?.transcript?.text ?? ""
        return ScriptText.words(in: transcript).count >= 3 ? transcript : segment.script
    }
}
