import Foundation

/// What was said, laid against what was meant to be said, word by word.
///
/// Every other editor guesses which words are "ums" and false starts from the speech alone. Here
/// the script is known, so a word that the script does not account for is a candidate for the cut,
/// and a word the script does account for is kept even when it looks like filler ("yani" in a
/// sentence that really says "yani").
///
/// Global alignment (Needleman–Wunsch) with fuzzy matching: recognisers bend spellings and
/// Turkish suffixes, so "anlatacağım" heard as "anlatacam" still lines up. Ties are resolved toward
/// the *later* spoken word, which is what makes a restart come out right: in "bugün size, bugün size
/// anlatacağım" the second attempt is the one matched, and the first is left over as extra.
public struct ScriptAlignment: Hashable, Sendable {
    public enum Match: Hashable, Sendable {
        /// The spoken word is this script word.
        case exact(Int)
        /// The spoken word is this script word, heard or said a little differently.
        case close(Int)
        /// Not in the script: filler, a restart, an ad-lib.
        case extra
    }

    /// One entry per spoken word.
    public var spoken: [Match]
    /// Script words that were never said.
    public var missed: [Int]
    public var scriptCount: Int

    public init(spoken: [Match], missed: [Int], scriptCount: Int) {
        self.spoken = spoken
        self.missed = missed
        self.scriptCount = scriptCount
    }

    public func scriptIndex(ofSpoken index: Int) -> Int? {
        guard spoken.indices.contains(index) else { return nil }
        switch spoken[index] {
        case .exact(let i), .close(let i): return i
        case .extra: return nil
        }
    }

    public func isExtra(_ index: Int) -> Bool {
        spoken.indices.contains(index) && spoken[index] == .extra
    }

    /// Share of the script that was said.
    public var coverage: Double {
        scriptCount == 0 ? 0 : Double(scriptCount - missed.count) / Double(scriptCount)
    }

    /// Share of the script said as written; a near miss counts half.
    public var accuracy: Double {
        guard scriptCount > 0 else { return 0 }
        let score = spoken.reduce(0.0) { total, match in
            switch match {
            case .exact: total + 1
            case .close: total + 0.5
            case .extra: total
            }
        }
        return min(1, score / Double(scriptCount))
    }

    /// Whether the take is really a reading of this script. An ad-lib recorded against a draft
    /// script lines up with almost nothing, and treating everything in it as "extra" would cut it
    /// to pieces.
    public var isUsable: Bool { scriptCount > 0 && coverage >= 0.4 }

    // MARK: - Aligning

    /// Past this many cells the full table is not worth the memory; a greedy walk is used.
    static let tableLimit = 2_500_000

    public static func align(spoken: [String], script: [String], locale: Locale) -> ScriptAlignment {
        let a = spoken.map { key($0, locale: locale) }
        let b = script.map { key($0, locale: locale) }
        guard !a.isEmpty, !b.isEmpty else {
            return ScriptAlignment(spoken: a.map { _ in .extra }, missed: Array(b.indices), scriptCount: b.count)
        }
        if a.count * b.count > tableLimit {
            return greedy(a, b)
        }
        return table(a, b)
    }

    public static func align(_ words: [TimedWord], script: String, locale: Locale) -> ScriptAlignment {
        align(spoken: words.map(\.text), script: ScriptText.words(in: script).map(String.init), locale: locale)
    }

    private static let matchScore = 2
    private static let closeScore = 1
    private static let gap = -1

    private static func table(_ a: [String], _ b: [String]) -> ScriptAlignment {
        let n = a.count, m = b.count
        let width = m + 1
        // 0 diagonal, 1 spoken extra (up), 2 script missed (left).
        var moves = [UInt8](repeating: 0, count: (n + 1) * width)
        var previous = [Int](repeating: 0, count: width)
        var current = [Int](repeating: 0, count: width)
        for j in 0...m {
            previous[j] = j * gap
            moves[j] = 2
        }
        for i in 1...n {
            current[0] = i * gap
            moves[i * width] = 1
            for j in 1...m {
                let s = similarity(a[i - 1], b[j - 1])
                var best = Int.min
                var move: UInt8 = 0
                if s > 0 {
                    best = previous[j - 1] + (s >= 1 ? matchScore : closeScore)
                }
                let up = previous[j] + gap
                if up > best {
                    best = up
                    move = 1
                }
                let left = current[j - 1] + gap
                if left > best {
                    best = left
                    move = 2
                }
                current[j] = best
                moves[i * width + j] = move
            }
            swap(&previous, &current)
        }

        var spoken = [Match](repeating: .extra, count: n)
        var said = [Bool](repeating: false, count: m)
        var i = n, j = m
        while i > 0 || j > 0 {
            let move = i == 0 ? 2 : (j == 0 ? 1 : moves[i * width + j])
            switch move {
            case 0:
                let s = similarity(a[i - 1], b[j - 1])
                spoken[i - 1] = s >= 1 ? .exact(j - 1) : .close(j - 1)
                said[j - 1] = true
                i -= 1
                j -= 1
            case 1:
                i -= 1
            default:
                j -= 1
            }
        }
        return ScriptAlignment(spoken: spoken, missed: said.indices.filter { !said[$0] }, scriptCount: m)
    }

    /// Walks forward matching each spoken word to the nearest script word just ahead.
    private static func greedy(_ a: [String], _ b: [String]) -> ScriptAlignment {
        var spoken = [Match](repeating: .extra, count: a.count)
        var said = [Bool](repeating: false, count: b.count)
        var cursor = 0
        for (i, word) in a.enumerated() where cursor < b.count {
            let end = min(b.count, cursor + 12)
            if let j = (cursor..<end).first(where: { similarity(word, b[$0]) > 0 }) {
                spoken[i] = similarity(word, b[j]) >= 1 ? .exact(j) : .close(j)
                said[j] = true
                cursor = j + 1
            }
        }
        return ScriptAlignment(spoken: spoken, missed: said.indices.filter { !said[$0] }, scriptCount: b.count)
    }

    // MARK: - Comparing words

    /// The form words are compared in: lower-cased for the locale, punctuation and apostrophes
    /// gone ("İstanbul'da," → "istanbulda").
    public static func key(_ word: some StringProtocol, locale: Locale) -> String {
        String(word.lowercased(with: locale).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// 1 for the same word, a fraction for a near miss, 0 for a different word.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return a.isEmpty ? 0 : 1 }
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let foldedA = fold(a), foldedB = fold(b)
        if foldedA == foldedB { return 0.9 }
        let shorter = min(foldedA.count, foldedB.count)
        // A suffix said differently, or a word the recogniser cut short.
        if shorter >= 4, foldedA.hasPrefix(foldedB) || foldedB.hasPrefix(foldedA) { return 0.8 }
        let longest = max(foldedA.count, foldedB.count)
        guard longest >= 4 else { return 0 }
        let ratio = 1 - Double(distance(foldedA, foldedB)) / Double(longest)
        return ratio >= 0.75 ? ratio : 0
    }

    /// Diacritics off, dotless i folded into i: the spellings a recogniser most often bends.
    static func fold(_ word: String) -> String {
        word.replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(1, a.count) where !a.isEmpty {
            var diagonal = row[0]
            row[0] = i
            for j in 1...max(1, b.count) where !b.isEmpty {
                let above = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, diagonal + (a[i - 1] == b[j - 1] ? 0 : 1))
                diagonal = above
            }
        }
        return a.isEmpty ? b.count : row[b.count]
    }
}
