import Foundation
import NaturalLanguage

/// The language someone typed in, for the AI to answer in.
///
/// The app's language and the project's are not the creator's language for this one request: a
/// creator with a Turkish phone who writes "a 30 second reel about my coffee shop" wants English
/// back, and every AI feature used to answer in Turkish because it only knew the phone's locale.
public enum WrittenLanguage {
    /// A locale identifier for `text`'s language, or `fallback` when the text is too short to
    /// tell or the recognizer is unsure. The fallback's region is kept when the language matches.
    public static func locale(of text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return fallback }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= 0.6, language != .undetermined
        else { return fallback }
        let code = language.rawValue
        let fallbackCode = Locale(identifier: fallback).language.languageCode?.identifier
        return code == fallbackCode ? fallback : code
    }
}
