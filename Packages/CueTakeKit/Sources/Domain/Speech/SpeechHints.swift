import Foundation

/// What the listeners are told before they hear anything.
///
/// The reader wrote the script, so the words most likely to be misheard — names, brands, products,
/// numbers, jargon — are known in advance. Recognisers take a short list of such terms, and Whisper
/// takes a prompt it treats as the text that came before.
public enum SpeechHints {
    /// Most recognisers weigh a short list; a long one dilutes every entry.
    public static let limit = 100

    /// The terms in the scripts worth telling a recogniser about, with the brand's own first.
    public static func terms(scripts: [String], brand: BrandVoice? = nil, localeIdentifier: String) -> [String] {
        let locale = Locale(identifier: localeIdentifier)
        var result: [String] = []
        var seen = Set<String>()
        func add(_ term: String) {
            let clean = term.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
            guard clean.count >= 2, result.count < limit else { return }
            let key = clean.lowercased(with: locale)
            guard seen.insert(key).inserted else { return }
            result.append(clean)
        }

        if let brand, !brand.isEmpty {
            add(brand.name)
            for phrase in brand.mustSay.components(separatedBy: CharacterSet(charactersIn: ",;\n")) {
                let words = ScriptText.words(in: phrase)
                // A short phrase as a whole; a sentence is too long to be a term.
                if (1...4).contains(words.count) { add(phrase) }
            }
        }

        for script in scripts {
            let raw = ScriptText.words(in: script)
            let words = raw.map { ScriptText.emphasis($0).text }
            for (index, word) in words.enumerated() {
                let bare = word.trimmingCharacters(in: .punctuationCharacters)
                guard bare.count >= 2 else { continue }
                let startsSentence = index == 0 || ScriptText.endsSentence(words[index - 1])
                let hasDigit = bare.contains { $0.isNumber }
                let letters = bare.filter(\.isLetter)
                let capitalised = letters.first?.isUppercase == true && !startsSentence
                let mixedCase = letters.dropFirst().contains { $0.isUppercase }
                let emphasised = ScriptText.emphasis(raw[index]).isEmphasized
                if hasDigit || capitalised || mixedCase || emphasised || bare.count >= 11 {
                    add(bare)
                }
            }
        }
        return result
    }

    /// Whisper's prompt: the terms, the opening of the script, and a line of hesitation.
    ///
    /// Whisper writes what it hears in the style of its prompt. Given clean text it cleans up the
    /// speech too and drops the "um"s; a prompt that has a few of them keeps them, and those are
    /// exactly the words the cleanup needs to see.
    public static func whisperPrompt(script: String, terms: [String], localeIdentifier: String, limit: Int = 400) -> String {
        let hesitation = Locale(identifier: localeIdentifier).language.languageCode?.identifier == "tr"
            ? "Iıı, şey… yani, hmm, ee, bu önemli."
            : "Umm, so, uh… like, I mean, hmm."
        let glossary = terms.prefix(20).joined(separator: ", ")
        let room = max(0, limit - hesitation.count - glossary.count - 4)
        let opening = String(script.trimmingCharacters(in: .whitespacesAndNewlines).prefix(room))
        let parts = [glossary.isEmpty ? nil : glossary + ".", opening.isEmpty ? nil : opening, hesitation]
        return String(parts.compactMap { $0 }.joined(separator: " ").prefix(limit))
    }
}

/// Numbers said as words, read back as digits, so "iki bin yirmi altı" meets "2026" in the script.
public enum SpokenNumbers {
    private static let turkish: [String: Int] = [
        "sıfır": 0, "bir": 1, "iki": 2, "üç": 3, "dört": 4, "beş": 5, "altı": 6, "yedi": 7, "sekiz": 8, "dokuz": 9,
        "on": 10, "yirmi": 20, "otuz": 30, "kırk": 40, "elli": 50, "altmış": 60, "yetmiş": 70, "seksen": 80, "doksan": 90,
    ]
    private static let english: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    private struct Words {
        var small: [String: Int]
        var hundred: String
        var thousand: String
        var million: String
        var percentBefore: String?
        var percentAfter: String?
        var joiner: String?
    }

    private static func words(for locale: Locale) -> Words {
        if locale.language.languageCode?.identifier == "tr" {
            return Words(small: turkish, hundred: "yüz", thousand: "bin", million: "milyon", percentBefore: "yüzde", percentAfter: nil, joiner: nil)
        }
        return Words(small: english, hundred: "hundred", thousand: "thousand", million: "million", percentBefore: nil, percentAfter: "percent", joiner: "and")
    }

    /// Match keys with every run of number words replaced by its value. A lone "one" or "bir" is
    /// left alone: it is far more often "a" than a number.
    public static func collapse(_ keys: [String], locale: Locale) -> [String] {
        let vocabulary = words(for: locale)
        func isNumberWord(_ key: String) -> Bool {
            vocabulary.small[key] != nil || key == vocabulary.hundred || key == vocabulary.thousand || key == vocabulary.million
        }

        var result: [String] = []
        var index = 0
        while index < keys.count {
            let key = keys[index]
            if key == vocabulary.percentBefore, index + 1 < keys.count, isNumberWord(keys[index + 1]) || Int(keys[index + 1]) != nil {
                // "yüzde elli" is "%50", whose key is "50".
                index += 1
                continue
            }
            guard isNumberWord(key) else {
                if key != vocabulary.percentAfter || !(result.last.map { Int($0) != nil } ?? false) {
                    result.append(key)
                }
                index += 1
                continue
            }

            var run: [String] = []
            var cursor = index
            while cursor < keys.count {
                if isNumberWord(keys[cursor]) {
                    run.append(keys[cursor])
                    cursor += 1
                } else if keys[cursor] == vocabulary.joiner, !run.isEmpty, cursor + 1 < keys.count, isNumberWord(keys[cursor + 1]) {
                    cursor += 1
                } else {
                    break
                }
            }
            let value = Self.value(of: run, vocabulary)
            if run.count == 1, let value, value < 2 {
                result.append(key)
            } else if let value {
                result.append(String(value))
            } else {
                result.append(contentsOf: run)
            }
            index = cursor
        }
        return result
    }

    private static func value(of run: [String], _ vocabulary: Words) -> Int? {
        var total = 0
        var current = 0
        for word in run {
            if let small = vocabulary.small[word] {
                current += small
            } else if word == vocabulary.hundred {
                current = max(current, 1) * 100
            } else if word == vocabulary.thousand {
                total += max(current, 1) * 1000
                current = 0
            } else if word == vocabulary.million {
                total += max(current, 1) * 1_000_000
                current = 0
            } else {
                return nil
            }
        }
        return total + current
    }
}
