import Foundation
import Testing
@testable import Domain

/// Translated captions: the video shows the chosen language on the original's timing, and a line
/// the creator fixed by hand survives a new translation.
struct CaptionTranslationTests {
    private func project() -> (Project, CaptionCue.ID, CaptionCue.ID) {
        let a = CaptionCue(text: "Merhaba millet", range: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 1.5)))
        let b = CaptionCue(text: "Bugün bir sır vereceğim", range: MediaTimeRange(start: MediaTime(seconds: 1.5), duration: MediaTime(seconds: 2)))
        var segment = Segment(role: .hook, script: "s", estimatedDuration: MediaTime(seconds: 4))
        segment.captions = [a, b]
        return (Project(title: "t", localeIdentifier: "tr-TR", segments: [segment]), a.id, b.id)
    }

    @Test func videoShowsTheChosenLanguageOnTheSameTiming() {
        var (project, a, b) = project()
        project.applyTranslations([a: "Hi everyone", b: "Today I'll tell you a secret"], language: "en")
        #expect(project.translationLanguages == ["en"])

        let spoken = project.captionCues
        project.captionLanguage = "en"
        let translated = project.captionCues
        #expect(translated.map(\.text) == ["Hi everyone", "Today I'll tell you a secret"])
        #expect(translated.map(\.range) == spoken.map(\.range))
        #expect(translated.allSatisfy { $0.localeIdentifier == "en" })
        // Its words fill the original line's time, in order.
        let words = translated[1].words
        #expect(words.count == 6)
        #expect(abs((words.last?.range.end.seconds ?? 0) - translated[1].range.end.seconds) < 0.001)
    }

    @Test func englishLinesAreUppercasedAsEnglish() {
        var (project, a, _) = project()
        project.applyTranslations([a: "this is it"], language: "en")
        project.captionLanguage = "en"
        var style = CaptionStyle.standard
        style.textCase = .uppercase
        let cue = project.captionCues[0]
        let words = CaptionWords(cue: cue, style: style, locale: Locale(identifier: "tr-TR")).words
        #expect(words == ["THIS", "IS", "IT"])
    }

    @Test func handFixesSurviveANewTranslation() {
        var (project, a, b) = project()
        project.applyTranslations([a: "Hello all", b: "Secret today"], language: "en")
        project.setTranslation("Hey everyone", cue: a, language: "en")
        project.applyTranslations([a: "Hello all again", b: "Today, a secret"], language: "en")
        let cues = project.segments[0].captions
        #expect(cues[0].translation("en") == "Hey everyone")
        #expect(cues[1].translation("en") == "Today, a secret")
        #expect(cues[0].isTranslationEdited("en"))
    }

    @Test func missingLinesFallBackAndRemovingALanguageResetsTheVideo() {
        var (project, a, _) = project()
        project.applyTranslations([a: "Hi everyone"], language: "es")
        project.captionLanguage = "es"
        #expect(project.captionCues.map(\.text) == ["Hi everyone", "Bugün bir sır vereceğim"])
        project.removeTranslation("es")
        #expect(project.captionLanguage == nil)
        #expect(project.translationLanguages.isEmpty)
    }

    @Test func oldProjectsStillOpen() throws {
        let (project, _, _) = project()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as! [String: Any]
        json.removeValue(forKey: "captionLanguage")
        let decoded = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.captionLanguage == nil)
        #expect(decoded.segments[0].captions.first?.translations == nil)
    }

    @Test func languageCodes() {
        #expect(CaptionTranslation.code(of: "tr-TR") == "tr")
        #expect(CaptionTranslation.code(of: "zh-Hans-CN") == "zh-Hans")
    }
}
