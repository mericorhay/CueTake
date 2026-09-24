import DesignSystem
import AIServices
import ScriptFeature
import SettingsFeature
import Domain
import Foundation
import Persistence

/// The ways into a new video from Create: an idea, a script, a recording.
extension AppModel {
    /// Whether the open project already holds something — footage or words — that a new start must
    /// not write into. "Start with a script" used to open the script of whatever project was open,
    /// and "Start recording" recorded into it.
    var projectHasContent: Bool {
        !project.recordings.isEmpty || !project.audio.isEmpty || project.segments.contains {
            !$0.takes.isEmpty || !$0.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// A clean project for the script screen, which opens on a place to paste or type.
    func startWithScript() {
        if projectHasContent || !project.segments.isEmpty { adopt(Self.blankProject()) }
        scriptReturn = .create
        go(to: .script)
    }

    /// From the home screen straight to reading: a clean project, the place to paste the words,
    /// and from there the camera. Back returns home rather than into the create flow.
    func startTeleprompter() {
        if projectHasContent || !project.segments.isEmpty { adopt(Self.blankProject()) }
        scriptReturn = .home
        go(to: .script)
    }

    /// A clean project for the studio, to record without a script.
    func startRecording() {
        if projectHasContent { adopt(Self.blankProject()) }
        studioReturn = .create
        openStudio()
    }

    /// From the blueprint, both lead back to it.
    func openScriptFromBlueprint() {
        scriptReturn = .blueprint
        go(to: .script)
    }

    /// From the studio, for a project with nothing to read. Back goes to the studio.
    func openScriptFromStudio() {
        scriptReturn = .studio
        studioReturn = .create
        go(to: .script)
    }

    /// Leaving the script screen: back where it was opened from.
    func leaveScript() {
        switch scriptReturn {
        case .studio: openStudio()
        case .blueprint where !project.segments.isEmpty: go(to: .blueprint)
        case .home: go(to: .home)
        default: go(to: .create)
        }
    }

    func openStudioFromPlan() {
        studioReturn = project.segments.isEmpty ? .create : .blueprint
        openStudio()
    }

    /// Writes the script on the server, for phones that cannot run the on-device model.
    func generateScriptOnServer(_ brief: ScriptBrief, localeIdentifier: String) async {
        promptModel.advance(to: 2)
        guard settingsModel.settings.aiProcessing == .allowCloud else {
            promptModel.fail(Self.assistantFailureMessage(AssistantClient.AssistantError.declined))
            return
        }
        guard access.use(.scriptWriting) else {
            promptModel.fail(AccessModel.message(for: access.decision(.scriptWriting)))
            return
        }
        do {
            let written = try await dependencies.assistantClient.writeScript(brief, localeIdentifier: localeIdentifier)
            let draft = ScriptBudget.fit(written, seconds: brief.targetDuration.seconds, localeIdentifier: localeIdentifier)
            promptModel.advance(to: 3)
            var fresh = Project(title: draft.title, format: promptModel.platform.defaultFormat, localeIdentifier: localeIdentifier)
            fresh.segments = draft.segments.map(Segment.init(draft:))
            settingsModel.settings.applyNewProjectDefaults(to: &fresh)

            promptModel.advance(to: 4)
            try? await dependencies.projectStore.save(fresh)
            adopt(fresh)
            await refreshLibrary()
            promptModel.finish()
            scriptReturn = .blueprint
            go(to: .blueprint)
        } catch {
            access.refund(.scriptWriting)
            promptModel.fail(Self.assistantFailureMessage(error))
        }
    }

    /// A short script for the script screen: the phone's own model when it has one, the server
    /// otherwise, cut to the length asked for.
    func writeScriptDraft(_ brief: ScriptBrief) async throws -> ScriptDraft {
        let locale = brief.localeIdentifier ?? project.localeIdentifier
        if let writer = await dependencies.ai.provider(
            .scriptWriting,
            as: (any ScriptWriting).self,
            localeIdentifier: locale
        ) {
            var draft: ScriptDraft?
            do {
                for try await partial in writer.writeScript(brief, localeIdentifier: locale) {
                    draft = partial
                }
            } catch {
                throw DescribedError(message: AppLocalization.string("prompt.failed.generic"))
            }
            guard let draft, !draft.segments.isEmpty else {
                throw DescribedError(message: AppLocalization.string("prompt.failed.empty"))
            }
            return ScriptBudget.fit(draft, seconds: brief.targetDuration.seconds, localeIdentifier: locale)
        }
        guard dependencies.assistantClient.isConfigured else {
            throw DescribedError(message: AppLocalization.string("prompt.failed.unavailable"))
        }
        guard settingsModel.settings.aiProcessing == .allowCloud else {
            throw DescribedError(message: Self.assistantFailureMessage(AssistantClient.AssistantError.declined))
        }
        do {
            let written = try await dependencies.assistantClient.writeScript(brief, localeIdentifier: locale)
            return ScriptBudget.fit(written, seconds: brief.targetDuration.seconds, localeIdentifier: locale)
        } catch {
            throw DescribedError(message: Self.assistantFailureMessage(error))
        }
    }

    /// The script screen's rewrite chips, on the server.
    func rewriteOnServer(text: String, direction: String, role: String, script: String, localeIdentifier: String) async throws -> String {
        guard settingsModel.settings.aiProcessing == .allowCloud else {
            throw DescribedError(message: Self.assistantFailureMessage(AssistantClient.AssistantError.declined))
        }
        guard access.use(.scriptWriting) else {
            throw DescribedError(message: AccessModel.message(for: access.decision(.scriptWriting)))
        }
        do {
            return try await dependencies.assistantClient.rewrite(
                text,
                direction: direction,
                role: role,
                script: script,
                localeIdentifier: localeIdentifier
            )
        } catch {
            access.refund(.scriptWriting)
            throw DescribedError(message: Self.assistantFailureMessage(error))
        }
    }
}
