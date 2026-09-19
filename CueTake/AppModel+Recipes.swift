import Domain
import Foundation

/// Ready-made recipes: a workflow packaged as a result — "a UGC ad", "my reel", "clean this up" —
/// run on the open project with one tap. Built fresh each time, in the viewer's language, and
/// never stored: copying one into the library is how it becomes the creator's to change.
extension AppModel {
    enum Recipe: String, CaseIterable {
        case quickFinish, ugcAd, myReel, talkingHead, podcast
    }

    var recipes: [WorkflowDefinition] { Recipe.allCases.map { recipe($0) } }

    func recipe(_ kind: Recipe) -> WorkflowDefinition {
        let preference = settingsModel.settings.captionPreset
        // The creator's own caption look, or pop when they turned captions off by default.
        let captions = preference == .off ? "pop" : preference.rawValue
        // Recipes that do not rebuild the video keep its shape.
        let format = project.format
        switch kind {
        case .quickFinish:
            return WorkflowDefinition(
                id: Self.recipeID(0),
                name: String(localized: "recipe.quick.name"),
                summary: String(localized: "recipe.quick.summary"),
                origin: .builtIn,
                style: WorkflowStyle(captionPreset: captions, aspect: format.aspectRatio, resolution: format.resolution, frameRate: format.frameRate),
                steps: [
                    WorkflowStep(kind: .analyzeSpeech),
                    WorkflowStep(kind: .trimSilences(TrimSilencesOptions())),
                    WorkflowStep(kind: .cutWords(CutWordsOptions())),
                    WorkflowStep(kind: .generateCaptions),
                    WorkflowStep(kind: .applyCaptionStyle(presetID: captions)),
                    WorkflowStep(kind: .export(.shortFormVertical)),
                ]
            )
        case .ugcAd:
            return WorkflowDefinition(
                id: Self.recipeID(1),
                name: String(localized: "recipe.ugc.name"),
                summary: String(localized: "recipe.ugc.summary"),
                origin: .builtIn,
                sections: [
                    WorkflowSection(role: "hook", title: String(localized: "recipe.section.hook"), seconds: 3),
                    WorkflowSection(role: "problem", title: String(localized: "recipe.section.problem"), seconds: 5),
                    WorkflowSection(role: "point", title: String(localized: "recipe.section.product"), seconds: 10),
                    WorkflowSection(role: "example", title: String(localized: "recipe.section.proof"), seconds: 6),
                    WorkflowSection(role: "cta", title: String(localized: "recipe.section.cta"), seconds: 4),
                ],
                style: WorkflowStyle(captionPreset: "bold"),
                steps: [
                    WorkflowStep(kind: .assembleSections),
                    WorkflowStep(kind: .analyzeSpeech),
                    WorkflowStep(kind: .trimSilences(TrimSilencesOptions(minPause: 0.4, padding: 0.08))),
                    WorkflowStep(kind: .cutWords(CutWordsOptions())),
                    WorkflowStep(kind: .setSpeed(SpeedOptions(target: "hook", speed: 1.1))),
                    WorkflowStep(kind: .cleanAudio(CleanAudioOptions())),
                    WorkflowStep(kind: .musicBed(MusicBedOptions(levelDB: -16))),
                    WorkflowStep(kind: .generateCaptions),
                    WorkflowStep(kind: .applyCaptionStyle(presetID: "bold")),
                    WorkflowStep(kind: .export(.shortFormVertical)),
                ]
            )
        case .myReel:
            return WorkflowDefinition(
                id: Self.recipeID(2),
                name: String(localized: "recipe.reel.name"),
                summary: String(localized: "recipe.reel.summary"),
                origin: .builtIn,
                sections: [
                    WorkflowSection(role: "hook", title: String(localized: "recipe.section.hook"), seconds: 3),
                    WorkflowSection(role: "point", title: String(localized: "recipe.section.point \(1)"), seconds: 7),
                    WorkflowSection(role: "point", title: String(localized: "recipe.section.point \(2)"), seconds: 7),
                    WorkflowSection(role: "point", title: String(localized: "recipe.section.point \(3)"), seconds: 7),
                    WorkflowSection(role: "cta", title: String(localized: "recipe.section.cta"), seconds: 3),
                ],
                style: WorkflowStyle(captionPreset: "karaoke", captionPosition: "middle", frameRate: 60),
                steps: [
                    WorkflowStep(kind: .assembleSections),
                    WorkflowStep(kind: .analyzeSpeech),
                    WorkflowStep(kind: .trimSilences(TrimSilencesOptions(minPause: 0.45, padding: 0.08))),
                    WorkflowStep(kind: .cutWords(CutWordsOptions())),
                    WorkflowStep(kind: .setSpeed(SpeedOptions(target: "hook", speed: 1.15))),
                    WorkflowStep(kind: .musicBed(MusicBedOptions())),
                    WorkflowStep(kind: .generateCaptions),
                    WorkflowStep(kind: .applyCaptionStyle(presetID: "karaoke")),
                    WorkflowStep(kind: .export(.shortFormVertical)),
                ]
            )
        case .talkingHead:
            return WorkflowDefinition(
                id: Self.recipeID(3),
                name: String(localized: "recipe.talking.name"),
                summary: String(localized: "recipe.talking.summary"),
                origin: .builtIn,
                style: WorkflowStyle(captionPreset: "clean", aspect: format.aspectRatio, resolution: format.resolution, frameRate: format.frameRate),
                steps: [
                    WorkflowStep(kind: .analyzeSpeech),
                    WorkflowStep(kind: .trimSilences(TrimSilencesOptions())),
                    WorkflowStep(kind: .cutWords(CutWordsOptions())),
                    WorkflowStep(kind: .cleanAudio(CleanAudioOptions())),
                    WorkflowStep(kind: .generateCaptions),
                    WorkflowStep(kind: .applyCaptionStyle(presetID: "clean")),
                ]
            )
        case .podcast:
            return WorkflowDefinition(
                id: Self.recipeID(4),
                name: String(localized: "recipe.podcast.name"),
                summary: String(localized: "recipe.podcast.summary"),
                origin: .builtIn,
                style: WorkflowStyle(captionPreset: "podcast", aspect: format.aspectRatio, resolution: format.resolution, frameRate: format.frameRate),
                steps: [
                    WorkflowStep(kind: .analyzeSpeech),
                    WorkflowStep(kind: .trimSilences(TrimSilencesOptions(minPause: 0.8, padding: 0.15))),
                    WorkflowStep(kind: .cleanAudio(CleanAudioOptions())),
                    WorkflowStep(kind: .generateCaptions),
                    WorkflowStep(kind: .applyCaptionStyle(presetID: "podcast")),
                    WorkflowStep(kind: .export(.shortFormVertical)),
                ]
            )
        }
    }

    private static func recipeID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "6B1B3C0E-0F4E-4C59-9E3A-11A0C0DE01%02d", index)) ?? UUID()
    }

    /// Runs a recipe on the open project: its steps shown ticking off, the result at the end.
    /// With nothing recorded yet, it opens with the clip picker instead.
    func runRecipe(_ workflow: WorkflowDefinition) {
        openWorkflow(workflow)
        guard !project.recordings.isEmpty else {
            pickClipsForWorkflow()
            return
        }
        Task { await runWorkflow() }
    }

    /// Clean → captions → export, in one tap, for the take just recorded.
    func quickFinish() {
        runRecipe(recipe(.quickFinish))
    }
}
