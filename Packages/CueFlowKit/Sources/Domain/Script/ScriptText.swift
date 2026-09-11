import Foundation

/// Script text helpers shared by teleprompter, speech tracking and captions.
/// Every comparison is locale-aware: Turkish dotted/dotless i breaks naive lowercasing.
public enum ScriptText {
    public static func words(in text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace)
    }

    /// Comparison key for matching spoken words against script words.
    /// "İSTANBUL'DA," with a Turkish locale becomes "istanbul'da".
    public static func matchKey(for word: some StringProtocol, locale: Locale) -> String {
        word.lowercased(with: locale).trimmingCharacters(in: .punctuationCharacters)
    }
}

/// Rough speaking rates used to estimate segment length before anything is recorded.
/// Turkish words are longer on average, so fewer words per minute. Tune with real data.
public enum SpeakingRate {
    public static func wordsPerMinute(forLocaleIdentifier identifier: String) -> Double {
        switch Locale(identifier: identifier).language.languageCode?.identifier {
        case "tr": 115
        default: 150
        }
    }
}
