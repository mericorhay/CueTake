import AIServices
import AssistantFeature
import DesignSystem
import Domain
import EditorFeature
import Foundation
import Persistence
import SettingsFeature
import WorkflowsFeature

/// The assistant's connections to the rest of the app, and the journey that keeps the user
/// oriented from the first import to the finished video.
extension AppModel {
    // MARK: - Assistant

    /// Hands the assistant its capabilities. Done once, lazily, because the closures capture the
    /// app model and cannot be built while it is still being initialised.
    func wireAssistant() {
        guard !isAssistantWired else { return }
        isAssistantWired = true

        let client = dependencies.assistantClient
        let store = dependencies.assistantStore

        assistant.isConnected = client.isConfigured && settingsModel.settings.aiProcessing == .allowCloud
        assistant.send = { [weak self] session in
            guard let self,
                  self.settingsModel.settings.aiProcessing == .allowCloud
            else { throw AssistantClient.AssistantError.declined }
            let locale = self.project.localeIdentifier
            return try await client.reply(to: session, localeIdentifier: locale)
        }
        assistant.save = { session in
            Task { try? await store?.save(session) }
        }
        assistant.delete = { id in
            Task { await store?.delete(id: id) }
        }
        assistant.deleteAll = {
            Task { await store?.deleteAll() }
        }
        assistant.context = { [weak self] in
            self?.assistantContext() ?? ""
        }
        assistant.onDestination = { [weak self] destination in
            self?.go(toAssistantDestination: destination)
        }
        assistant.onWorkflow = { [weak self] workflow, run in
            self?.adoptAssistantWorkflow(workflow, run: run)
        }
        assistant.describeFailure = { error in Self.assistantFailureMessage(error) }

        Task { [weak self] in
            guard let store else { return }
            let stored = await store.all()
            self?.assistant.load(stored)
        }
    }

    /// Opens the assistant, optionally with a question already asked.
    func openAssistant(asking question: String? = nil) {
        wireAssistant()
        assistant.isConnected = dependencies.assistantClient.isConfigured
            && settingsModel.settings.aiProcessing == .allowCloud
        if let question, !question.trimmingCharacters(in: .whitespaces).isEmpty {
            assistant.ask(question)
        }

        // One sheet at a time. Presenting the assistant while the journey map is still on its way
        // down is silently ignored by SwiftUI, so the second one waits for the first to leave.
        guard isJourneyOpen else {
            isAssistantOpen = true
            return
        }
        isJourneyOpen = false
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.isAssistantOpen = true
        }
    }

    /// Where the user is, in a few plain lines, sent with each message.
    ///
    /// Written by the app rather than asked of the user, because the moment someone opens the
    /// assistant to say "I'm lost" is exactly the moment they cannot describe where they are.
    func assistantContext() -> String {
        let takes = project.segments.filter { $0.selectedTake != nil }.count
        let seconds = Int(project.segments.reduce(0) { $0 + $1.barWeight }.rounded())
        let transcribed = project.segments.contains { $0.selectedTake?.transcript != nil }
        let captioned = project.segments.contains { !$0.captions.isEmpty }

        var lines = [
            "screen: \(Self.screenName(screen))",
            "project: \"\(project.title)\", \(project.segments.count) clips (\(takes) with footage), \(seconds)s",
            "transcribed: \(transcribed ? "yes" : "no"), captions: \(captioned ? "yes" : "no"), music/audio clips: \(project.audio.count)",
            "format: \(project.format.label)",
        ]
        if let stage = journeyStage {
            lines.append("journey stage: \(stage + 1) of 4 (\(Self.stageNames[stage]))")
        }
        if exportModel.outputURL != nil {
            lines.append("this project has been exported")
        }
        if let workflow = workflowStudio?.definition {
            lines.append("open workflow: \"\(workflow.name)\" with \(workflow.steps.count) steps")
        }
        return lines.joined(separator: "\n")
    }

    func go(toAssistantDestination destination: AssistantDestination) {
        isAssistantOpen = false
        isJourneyOpen = false
        switch destination {
        case .create: go(to: .create)
        case .import:
            // The picker is a presentation, and the assistant's sheet is still leaving.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                self?.isPickingFootage = true
            }
        case .editor: openEditor()
        case .captions: go(to: .captions)
        case .export: go(to: .export)
        case .projects: go(to: .projects)
        case .workflows: go(to: .workflows)
        case .settings: go(to: .settings)
        case .studio: openStudio()
        }
    }

    /// Takes a workflow the assistant wrote: stored like any other, opened in the studio, and run on
    /// the open project when that is what the user tapped.
    func adoptAssistantWorkflow(_ proposed: WorkflowDefinition, run: Bool) {
        var workflow = proposed
        workflow.origin = .ai
        isAssistantOpen = false

        workflowStudio = WorkflowStudioModel(definition: workflow, clips: currentClips())
        workflows.removeAll { $0.id == workflow.id }
        workflows.insert(workflow, at: 0)
        let store = dependencies.workflowStore
        Task { try? await store?.save(workflow) }

        go(to: .workflowDetail)
        guard run else { return }
        Task { [weak self] in
            // After the sheet has left, so the user watches the rail fill rather than missing it.
            try? await Task.sleep(for: .milliseconds(500))
            await self?.runWorkflow()
        }
    }

    // MARK: - Journey

    /// English names for the assistant's context. The visible names are localised separately.
    static let stageNames = ["Start", "Edit", "Captions", "Share"]

    static func screenName(_ screen: Screen) -> String {
        switch screen {
        case .onboarding: "Onboarding"
        case .home: "Home"
        case .create: "Create"
        case .prompt: "Write a script with AI"
        case .blueprint: "Blueprint"
        case .script: "Script"
        case .studio: "Studio (camera)"
        case .complete: "Recording complete"
        case .editor: "Editor"
        case .retake: "Retake"
        case .captions: "Captions"
        case .export: "Export"
        case .projects: "Projects"
        case .workflows: "Workflows"
        case .workflowDetail: "Workflow studio"
        case .settings: "Settings"
        case .suflor: "Suflör (live-stream prompter)"
        }
    }

    /// Which of the four stages the current screen belongs to.
    var journeyStage: Int? {
        switch screen {
        case .create, .prompt, .blueprint, .script, .studio, .complete, .retake: 0
        case .editor: 1
        case .captions: 2
        case .export: 3
        default: nil
        }
    }

    /// Stages that are actually done, judged from the project rather than from where the user has
    /// been: visiting the captions screen does not make a video captioned.
    var journeyCompleted: Set<Int> {
        var done = Set<Int>()
        let hasFootage = project.segments.contains { $0.selectedTake != nil }
        let captioned = project.segments.contains { !$0.captions.isEmpty }
        let exported = exportModel.outputURL != nil
        if hasFootage { done.insert(0) }
        if hasFootage && (captioned || exported || editorModel.canUndo) { done.insert(1) }
        if captioned { done.insert(2) }
        if exported { done.insert(3) }
        return done
    }

    var journeyContext: DSJourneyContext {
        DSJourneyContext(
            stages: [
                AppLocalization.string("journey.stage.start"),
                AppLocalization.string("journey.stage.edit"),
                AppLocalization.string("journey.stage.captions"),
                AppLocalization.string("journey.stage.share"),
            ],
            current: journeyStage,
            completed: journeyCompleted,
            onOpenMap: { [weak self] in self?.isJourneyOpen = true }
        )
    }

    /// The stage the user should do next: the first one that is not done.
    var journeyNext: Int? {
        (0..<4).first { !journeyCompleted.contains($0) }
    }

    func goToStage(_ stage: Int) {
        isJourneyOpen = false
        switch stage {
        case 0: go(to: .create)
        case 1: openEditor()
        case 2: go(to: .captions)
        default: go(to: .export)
        }
    }

    /// A failure from the assistant endpoint, as a sentence someone can act on.
    static func assistantFailureMessage(_ error: any Error) -> String {
        switch error as? AssistantClient.AssistantError {
        case .notConfigured: AppLocalization.string("assistant.failure.notConfigured")
        case .offline: AppLocalization.string("assistant.failure.offline")
        case .declined: AppLocalization.string("assistant.failure.declined")
        // Said precisely, because "something went wrong" cannot be acted on and each of these
        // has a different fix: a key that does not match, too many messages, the model failing.
        case .rejected(let status) where status == 401:
            AppLocalization.string("assistant.failure.unauthorized")
        case .rejected(let status) where status == 429:
            AppLocalization.string("assistant.failure.busy")
        case .rejected(let status):
            AppLocalization.string("assistant.failure.server \(status)")
        default: AppLocalization.string("assistant.failure.generic")
        }
    }

    /// Asks the model for an edit plan of the open project.
    func requestEditPlan(_ document: EditDocument, _ instruction: String) async throws -> EditPlan {
        guard settingsModel.settings.aiProcessing == .allowCloud else {
            throw DescribedError(message: Self.assistantFailureMessage(AssistantClient.AssistantError.declined))
        }
        do {
            return try await dependencies.assistantClient.editPlan(
                for: document,
                instruction: instruction,
                localeIdentifier: project.localeIdentifier
            )
        } catch {
            throw DescribedError(message: Self.assistantFailureMessage(error))
        }
    }
}

/// An error whose description is already written for people.
struct DescribedError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
