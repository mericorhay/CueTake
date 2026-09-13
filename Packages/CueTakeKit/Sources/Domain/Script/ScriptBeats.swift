import Foundation

extension ScriptText {
    /// A pasted or typed script cut into beats, without a model.
    ///
    /// Paragraphs are beats when the writer made paragraphs — that is the writer saying where the
    /// breaks are. A single block is cut at sentences: the first sentence is the hook, the last is
    /// the call to action when there are enough to spare one, and the rest are grouped two or three
    /// at a time so no beat is a paragraph to read off a prompter. Never more than eight beats.
    public static func beats(from text: String, localeIdentifier: String) -> [SegmentDraft] {
        let clean = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }

        var pieces = clean
            .components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if pieces.count < 2 {
            var sentences: [String] = []
            let flat = clean.replacingOccurrences(of: "\n", with: " ")
            flat.enumerateSubstrings(in: flat.startIndex..., options: .bySentences) { sentence, _, _, _ in
                if let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                    sentences.append(sentence)
                }
            }
            if sentences.isEmpty { sentences = [flat] }
            pieces = group(sentences)
        }

        if pieces.count > 8 {
            let head = Array(pieces.prefix(7))
            pieces = head + [pieces.dropFirst(7).joined(separator: " ")]
        }

        let perMinute = SpeakingRate.wordsPerMinute(forLocaleIdentifier: localeIdentifier)
        return pieces.enumerated().map { index, piece in
            let role: SegmentRole
            if index == 0, pieces.count > 1 {
                role = .hook
            } else if index == pieces.count - 1, pieces.count >= 3 {
                role = .callToAction
            } else {
                role = .mainPoint
            }
            let spoken = Double(Self.words(in: piece).count)
            return SegmentDraft(
                role: role,
                title: "",
                script: piece,
                estimatedDuration: MediaTime(seconds: max(1, spoken / perMinute * 60))
            )
        }
    }

    /// Sentences into beats: the first alone, the last alone when there are four or more, the
    /// middle two or three at a time.
    private static func group(_ sentences: [String]) -> [String] {
        guard sentences.count > 2 else { return sentences }
        var beats = [sentences[0]]
        let hasEnd = sentences.count >= 4
        let middle = Array(sentences[1..<(hasEnd ? sentences.count - 1 : sentences.count)])
        let size = middle.count > 6 ? 3 : 2
        var start = 0
        while start < middle.count {
            let end = min(start + size, middle.count)
            beats.append(middle[start..<end].joined(separator: " "))
            start = end
        }
        if hasEnd, let last = sentences.last { beats.append(last) }
        return beats
    }
}
