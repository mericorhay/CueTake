import Foundation

/// Captions in other languages: the lines a translation writes, and how a translated line is
/// timed when it is shown on the video.
///
/// A translation belongs to the cue it translates, so cutting, moving or retiming a line carries
/// its translations with it. The spoken language stays the source of truth; a translation is
/// shown on the video only when the creator picks it (`Project.captionLanguage`).
public enum CaptionTranslation {
    /// The languages offered, by code. Right-to-left scripts are left out until the caption
    /// renderer lays words out right to left.
    public static let languages = [
        "en", "tr", "es", "de", "fr", "it", "pt", "nl", "pl", "ru", "uk", "id", "hi", "ja", "ko", "zh-Hans",
    ]

    /// A language's name in the viewer's own language: "İngilizce", "English", "Inglés".
    public static func name(of code: String, in locale: Locale) -> String {
        locale.localizedString(forIdentifier: code)?.capitalized(with: locale) ?? code
    }

    /// The code of the language a project is spoken in, in the same form as `languages`.
    public static func code(of localeIdentifier: String) -> String {
        let locale = Locale(identifier: localeIdentifier)
        let language = locale.language.languageCode?.identifier ?? String(localeIdentifier.prefix(2))
        if language == "zh" { return "zh-Hans" }
        return language
    }

    /// The translated line's words over the time the original was said, each word given a share
    /// of the time as long as it is. Not what was said word by word, but it keeps a karaoke look
    /// moving with the voice instead of lighting everything at once.
    public static func spread(_ text: String, over range: MediaTimeRange) -> [PlacedWord] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, range.duration.seconds > 0 else { return [] }
        let weights = words.map { Double(max($0.count, 2)) }
        let total = weights.reduce(0, +)
        var cursor = range.start.seconds
        return zip(words, weights).map { word, weight in
            let length = range.duration.seconds * weight / total
            defer { cursor += length }
            return PlacedWord(text: word, range: MediaTimeRange(start: MediaTime(seconds: cursor), duration: MediaTime(seconds: length)))
        }
    }
}

extension Project {
    /// The languages some caption has a translation in, in the offered order.
    public var translationLanguages: [String] {
        var found = Set<String>()
        for segment in segments {
            for cue in segment.captions {
                for (code, text) in cue.translations ?? [:] where !text.isEmpty { found.insert(code) }
            }
        }
        let known = CaptionTranslation.languages.filter(found.contains)
        return known + found.subtracting(known).sorted()
    }

    /// Every caption line in video order, with the text to translate.
    public var captionLines: [(id: CaptionCue.ID, text: String)] {
        segments.flatMap { $0.captions.map { ($0.id, $0.text) } }
    }

    /// Lays in a translation. Lines the creator corrected by hand in that language are kept.
    public mutating func applyTranslations(_ lines: [CaptionCue.ID: String], language: String) {
        for s in segments.indices {
            for c in segments[s].captions.indices {
                let cue = segments[s].captions[c]
                guard let text = lines[cue.id], !cue.isTranslationEdited(language) else { continue }
                var translations = cue.translations ?? [:]
                translations[language] = text.trimmingCharacters(in: .whitespacesAndNewlines)
                segments[s].captions[c].translations = translations
            }
        }
    }

    /// A hand correction of one translated line.
    public mutating func setTranslation(_ text: String, cue id: CaptionCue.ID, language: String) {
        for s in segments.indices {
            guard let c = segments[s].captions.firstIndex(where: { $0.id == id }) else { continue }
            var translations = segments[s].captions[c].translations ?? [:]
            translations[language] = text
            segments[s].captions[c].translations = translations
            var edited = Set(segments[s].captions[c].editedTranslations ?? [])
            edited.insert(language)
            segments[s].captions[c].editedTranslations = edited.sorted()
            return
        }
    }

    /// Forgets a language everywhere; the video goes back to the spoken one if it showed it.
    public mutating func removeTranslation(_ language: String) {
        for s in segments.indices {
            for c in segments[s].captions.indices {
                segments[s].captions[c].translations?[language] = nil
                segments[s].captions[c].editedTranslations?.removeAll { $0 == language }
            }
        }
        if captionLanguage == language { captionLanguage = nil }
    }
}
