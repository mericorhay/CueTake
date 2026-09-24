import DesignSystem
import Domain
import Foundation

/// Lines in, the same lines in `target` out, by cue; the progress callback runs as pieces finish.
public typealias CaptionTranslator = (
    _ lines: [(id: CaptionCue.ID, text: String)],
    _ target: String,
    _ progress: @escaping @Sendable (Double) async -> Void
) async throws -> [CaptionCue.ID: String]

/// Captions in other languages, from the editor: translate, choose what the video shows, correct a
/// line by hand. Each is one undo step.
extension EditorModel {
    public var canTranslateCaptions: Bool {
        captionTranslator != nil && project.segments.contains { !$0.captions.isEmpty }
    }

    /// The spoken language, as a translation code.
    public var spokenLanguage: String { CaptionTranslation.code(of: project.localeIdentifier) }

    /// Translates every caption. Lines already corrected by hand in that language are kept.
    @discardableResult
    public func translateCaptions(to language: String) async -> Bool {
        guard let captionTranslator, translationProgress == nil else { return false }
        let lines = project.captionLines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return false }
        guard allows(.captionTranslation) else { return false }
        translationFailure = nil
        translationProgress = 0
        defer { translationProgress = nil }
        do {
            let result = try await captionTranslator(lines, language) { [weak self] value in
                await MainActor.run { self?.translationProgress = value }
            }
            record("editor.change.translate", symbol: "globe")
            project.applyTranslations(result, language: language)
            project.updatedAt = .now
            return true
        } catch {
            accessRefund?(.captionTranslation)
            translationFailure = (error as? LocalizedError)?.errorDescription
                ?? AppLocalization.string("lyrics.translate.failed", bundle: .module)
            return false
        }
    }

    /// Which language the captions on the video are in: a translation, or nil for the spoken one.
    public func showCaptions(in language: String?) {
        let wanted = language == spokenLanguage ? nil : language
        guard project.captionLanguage != wanted else { return }
        record("editor.change.captionLanguage", symbol: "globe")
        project.captionLanguage = wanted
        project.updatedAt = .now
    }

    /// A hand correction of a line, in the spoken language or in a translation.
    public func correctCaption(_ id: CaptionCue.ID, text: String, language: String?) {
        let clean = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        record("editor.change.caption", symbol: "text.bubble", coalescing: "caption-\(id)")
        if let language, language != spokenLanguage {
            project.setTranslation(clean, cue: id, language: language)
        } else if let index = project.segments.firstIndex(where: { $0.captions.contains { $0.id == id } }) {
            project.segments[index].setCaptionText(id, to: clean)
        }
        project.updatedAt = .now
    }

    public func removeCaptionTranslation(_ language: String) {
        record("editor.change.translate", symbol: "globe")
        project.removeTranslation(language)
        project.updatedAt = .now
    }
}
