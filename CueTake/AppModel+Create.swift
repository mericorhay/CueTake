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
        do {
            let draft = try await dependencies.assistantClient.writeScript(brief, localeIdentifier: localeIdentifier)
            promptModel.advance(to: 3)
            var fresh = Project(title: draft.title, format: promptModel.platform.defaultFormat, localeIdentifier: localeIdentifier)
            fresh.segments = draft.segments.map(Segment.init(draft:))
            settingsModel.settings.applyStyle(to: &fresh)

            promptModel.advance(to: 4)
            try? await dependencies.projectStore.save(fresh)
            adopt(fresh)
            await refreshLibrary()
            promptModel.finish()
            scriptReturn = .blueprint
            go(to: .blueprint)
        } catch {
            promptModel.fail(Self.assistantFailureMessage(error))
        }
    }

    /// The script screen's rewrite chips, on the server.
    func rewriteOnServer(text: String, direction: String, role: String, script: String, localeIdentifier: String) async throws -> String {
        guard settingsModel.settings.aiProcessing == .allowCloud else {
            throw DescribedError(message: Self.assistantFailureMessage(AssistantClient.AssistantError.declined))
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
            throw DescribedError(message: Self.assistantFailureMessage(error))
        }
    }
}
