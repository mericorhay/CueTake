import AIServices
import AuthenticationServices
import CaptureEngine
import Combine
import Foundation
import AssistantFeature
import DesignSystem
import Domain
import EditorFeature
import LibraryFeature
import OnboardingFeature
import PhotosUI
import UniformTypeIdentifiers
import ScriptFeature
import SettingsFeature
import StudioFeature
import SuflorFeature
import SwiftUI
import TeamFeature
import WorkflowsFeature

/// Hosts every screen and the tab bar. Features never navigate to each other directly —
/// they report what happened and this is the only place that decides where to go.
struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var pickedFootage: [PhotosPickerItem] = []
    @State private var pickedVideoLayer: PhotosPickerItem?
    @State private var pickedBrandLogo: PhotosPickerItem?
    @State private var showsTeam = false
    /// The limit card's own window, above every sheet.
    @State private var limitPresenter = LimitPresenter()
    @State private var showsSuflorReports = false
    @Environment(\.openURL) private var openURL
    @State private var showsCertificates = false
    @State private var showsVoiceProfile = false

    var body: some View {
        ZStack {
            DS.Palette.screen.ignoresSafeArea()

            // The design is drawn on a 402x874 frame — an iPhone 16 Pro screen — and every
            // screen's padding is measured from the device edge, not from the safe area: 78pt
            // of top padding is what clears the status bar. Laying these out inside the safe
            // area would add the insets on top, squeezing every screen from both ends.
            // `.container` is deliberate: the keyboard's inset must still push content up.
            screen
                .id(model.screen)
                // Every flow screen's back button reads this and shows the stage it belongs to,
                // with the journey map one tap away. Root screens have the tab bar instead.
                .environment(\.dsJourney, model.screen.isRoot || model.screen == .onboarding || model.screen == .suflor ? nil : model.journeyContext)
                .ignoresSafeArea(.container)
                // Each screen plays the design's own `scin` entrance on arrival, so only the
                // exit is described here: without it the outgoing screen is cut rather than
                // handed over, and every navigation reads as a jump.
                .transition(.asymmetric(insertion: .identity, removal: .opacity))

            if model.screen.isRoot {
                tabBar
                    .frame(maxWidth: DS.Layout.column)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 20)
                    .ignoresSafeArea(.container)
            }
        }
        .overlay {
            if let busy = model.busy {
                BusyOverlay(status: busy)
            }
        }
        .animation(DS.Motion.settle, value: model.busy)
        .overlay(alignment: .top) {
            StatusToasts(activity: model.activity, notice: model.notice)
        }
        .task { model.startPlusStore() }
        .onChange(of: model.access.request?.id) { _, id in
            limitPresenter.hide()
            guard id != nil, let request = model.access.request else { return }
            limitPresenter.show(
                LimitSheet(
                    request: request,
                    plan: model.access.plan,
                    resetsAt: model.access.resetsAt,
                    price: model.plusStore.price,
                    onUpgrade: { model.upgradeToPlus() },
                    onClose: { model.access.request = nil }
                )
            )
        }
        .animation(DS.Easing.ease(0.22), value: model.screen)
        // Bound here rather than inside CreateScreen: the picker outlives that screen's identity,
        // and the import writes to the project, which is this layer's business.
        .photosPicker(
            isPresented: $model.isPickingFootage,
            selection: $pickedFootage,
            maxSelectionCount: 30,
            // Photos too: each becomes a clip of its own, held for a few seconds.
            matching: .any(of: [.videos, .images])
        )
        .photosPicker(isPresented: $model.isPickingVideoLayer, selection: $pickedVideoLayer, matching: .videos)
        .photosPicker(isPresented: $model.isPickingBrandLogo, selection: $pickedBrandLogo, matching: .images)
        .onChange(of: pickedBrandLogo) { _, item in
            guard let item else { return }
            pickedBrandLogo = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                await model.adoptBrandLogo(data)
            }
        }
        // Files rather than the photo picker: music does not live in the photo library. Copying
        // happens in the importer, so the security-scoped loan this hands back only has to survive
        // the copy.
        .fileImporter(
            isPresented: $model.isPickingAudio,
            // Anything, not a list of audio types. People keep sound in files the system does not
            // label as audio — a voice memo exported by another app, a track inside a video, a
            // download with the wrong extension — and the importer already refuses what has no
            // audio track in it. Guessing from the type was rejecting files that work.
            allowedContentTypes: [.audio, .movie, .item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            Task { await model.importAudio(urls) }
        }
        .onChange(of: pickedFootage) { _, items in
            guard !items.isEmpty else { return }
            let picked = items
            pickedFootage = []
            Task { await model.importFootage(picked) }
        }
        .onChange(of: pickedVideoLayer) { _, item in
            guard let item else { return }
            pickedVideoLayer = nil
            Task { await model.importVideoLayer(item) }
        }
        .sheet(isPresented: $model.isJourneyOpen) {
            JourneyMapSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
        }
        .sheet(isPresented: $model.isAssistantOpen) {
            AssistantScreen(model: model.assistant) { model.isAssistantOpen = false }
                .presentationDetents([.large])
                .presentationCornerRadius(34)
                .presentationBackground(DS.Palette.screen)
        }
        .preferredColorScheme(.dark)
        .task {
            await model.restore()
            model.wireAssistant()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-voice-preview") { showsVoiceProfile = true }
            if ProcessInfo.processInfo.arguments.contains("-certificates-preview") { showsCertificates = true }
            #endif
            // Maintenance deliberately follows visible launch work. It already waits for the app
            // to settle, and must never delay a screen or an accessibility snapshot.
            await model.cleanStorageAfterLaunch()
        }
        .onChange(of: model.project) { model.scheduleSave() }
        .task { await model.accountModel.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.accountModel.refresh() } }
            // Leaving the app: the projects go to the creator's iCloud while iOS allows.
            if phase == .background, model.access.plan == .pro { model.cloudBackup.backUpInBackground() }
        }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            Task { await model.accountModel.revokeLocalSession() }
        }
    }

    /// The script screen's rewrites on the server, or nil in a build without the assistant.
    private var scriptRewrite: ScriptScreen.ServerRewrite? {
        guard model.settingsModel.settings.aiProcessing == .allowCloud,
              model.dependencies.assistantClient.isConfigured else { return nil }
        let model = model
        return { text, direction, role, script, locale in
            try await model.rewriteOnServer(text: text, direction: direction, role: role, script: script, localeIdentifier: locale)
        }
    }

    /// The brand report after the take of an ad, or nil for any other video.
    private var adReport: (() -> Void)? {
        guard model.isAdProject else { return nil }
        let model = model
        return { model.openAdReport() }
    }

    /// The AI edit tool's line to the model, or nil in a build without the assistant.
    private var aiEdit: ((EditDocument, String) async throws -> EditPlan)? {
        guard model.settingsModel.settings.aiProcessing == .allowCloud,
              model.dependencies.assistantClient.isConfigured else { return nil }
        let model = model
        return { document, instruction in
            try await model.requestEditPlan(document, instruction)
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch model.screen {
        case .onboarding:
            OnboardingScreen { model.completeOnboarding() }

        case .home:
            HomeScreen(
                recents: model.recentItems,
                onCreate: { model.go(to: .create) },
                onOpenProject: { item in Task { await model.openProject(id: item.id) } },
                onOpenAllProjects: { model.go(to: .projects) },
                onOpenWorkflow: { model.go(to: .workflows) },
                workflows: model.homeWorkflows,
                onRunWorkflow: { id in model.openHomeWorkflow(id) },
                onTeleprompter: { model.startTeleprompter() },
                onSuflor: { model.startSuflor() }
            )

        case .create:
            CreateScreen(onBack: { model.go(to: .home) }) { destination in
                switch destination {
                case .importFootage: model.isPickingFootage = true
                case .prompt: model.go(to: .prompt)
                case .script: model.startWithScript()
                case .workflow: model.go(to: .workflows)
                case .studio: model.startRecording()
                }
            }

        case .prompt:
            PromptScreen(
                model: model.promptModel,
                onBack: { model.go(to: .create) },
                onGenerated: { await model.generateScript() }
            )

        case .blueprint:
            BlueprintScreen(
                project: $model.project,
                onBack: { model.go(to: .prompt) },
                onOpenScript: { model.openScriptFromBlueprint() },
                onOpenStudio: { model.openStudioFromPlan() }
            )

        case .script:
            ScriptScreen(
                project: $model.project,
                onBack: { model.leaveScript() },
                onOpenStudio: { model.openStudioFromPlan() },
                serverRewrite: scriptRewrite,
                library: model.scriptLibrary,
                writer: { [model] brief in try await model.writeScriptDraft(brief) }
            )

        case .studio:
            StudioScreen(
                model: model.studioModel,
                camera: model.settingsModel.settings.defaultCamera,
                onBack: { model.go(to: model.studioReturn) },
                onOpenEditor: { model.openEditor() },
                onFinished: { Task { await model.finishStudioCapture() } },
                onBeginCapture: { await model.beginStudioCapture() },
                onWriteScript: { model.openScriptFromStudio() }
            )

        case .complete:
            CompleteScreen(
                project: model.project,
                onRetake: { model.startRetake(of: $0) },
                onEdit: { model.openEditor() },
                onDone: { model.go(to: .export) },
                onReport: adReport,
                onQuickFinish: { model.quickFinish() }
            )

        case .editor:
            EditorScreen(
                model: model.editorModel,
                onPrepare: { await model.prepareEditorPlayback() },
                onBack: { model.go(to: .home) },
                onExport: { model.go(to: .export) },
                onCaptions: { model.go(to: .captions) },
                onRetake: { model.startRetake(of: $0) },
                onAddAudio: { model.isPickingAudio = true },
                onAddVideo: { model.isPickingVideoLayer = true },
                saveLabel: model.saveLabel,
                isSaving: model.isSaving,
                onSave: { model.saveNow() },
                onTranscribe: { Task { await model.transcribeNewTakes() } },
                onAIEdit: aiEdit,
                onAllowCloudAI: model.dependencies.assistantClient.isConfigured
                    ? { model.settingsModel.update(\.aiProcessing, to: .allowCloud) }
                    : nil,
                brandTools: model.brandTools,
                versionTools: model.versionTools
            )
            // A different project is a different editor: its playback is prepared afresh.
            .id(ObjectIdentifier(model.editorModel))
            .onChange(of: model.editorModel.project) {
                guard !model.editorModel.isAIDriving else { return }
                model.adoptEditorEdits()
            }
            .onChange(of: model.editorModel.isAIDriving) { _, driving in
                if !driving { model.adoptEditorEdits() }
            }

        case .retake:
            if let retakeModel = model.retakeModel {
                RetakeScreen(
                    model: retakeModel,
                    camera: model.settingsModel.settings.defaultCamera,
                    onBeginCapture: { await model.beginRetakeCapture() },
                    onBack: { model.openEditor() },
                    onKeep: { _ in model.keepRetake() }
                )
            }

        case .captions:
            CaptionsScreen(
                // Bound, not copied: every retyped word and nudged timing is the project's.
                project: $model.project,
                frames: model.editorModel.thumbnails,
                onStyleChange: { model.applyCaptionStyle($0) },
                onBack: { model.openEditor() },
                onExport: { model.go(to: .export) },
                onTranscribe: { Task { await model.transcribeNewTakes() } }
            )

        case .export:
            ExportScreen(
                model: model.exportModel,
                // Both copies: the editor's is what comes back to the app when it is next opened.
                format: Binding(
                    get: { model.project.format },
                    set: { format in
                        model.project.format = format
                        model.editorModel.project.format = format
                    }
                ),
                warnings: { platform in platform.warnings(for: model.project, duration: model.editorModel.duration) },
                onRender: { Task { await model.exportForPlatforms() } },
                onBack: { model.openEditor() },
                onDone: { model.finishExport() }
            )

        case .projects:
            ProjectsScreen(
                projects: model.projectItems,
                onDeleteProjects: { items in Task { await model.deleteProjects(ids: items.map(\.id)) } }
            ) { item in
                Task { await model.openProject(id: item.id) }
            }

        case .workflows:
            WorkflowsScreen(
                workflows: model.workflows,
                onOpen: { model.openWorkflow($0) },
                onCreate: { model.createWorkflow() },
                onCreateWithAI: { await model.createWorkflowWithAI($0) },
                onDuplicate: { workflow in Task { await model.duplicateWorkflow(workflow) } },
                onDelete: { workflow in Task { await model.deleteWorkflow(id: workflow.id) } },
                recipes: model.recipes,
                onRunRecipe: { model.runRecipe($0) }
            )
            .task { await model.loadWorkflows() }

        case .workflowDetail:
            if let studio = model.workflowStudio {
                WorkflowStudioScreen(
                    model: studio,
                    onBack: { model.closeWorkflow() },
                    onSave: { model.saveWorkflow() },
                    onRun: { model.startWorkflowRun() },
                    onStop: { model.stopWorkflowRun() },
                    onAskAI: { Task { await model.askWorkflowAI() } },
                    onPickClips: { model.pickClipsForWorkflow() },
                    onDelete: { Task { await model.deleteWorkflow() } },
                    onOpenResult: { model.openWorkflowResult() },
                    onResend: { model.resendWorkflowDelivery() }
                )
            }

        case .suflor:
            SuflorScreen(model: model.suflorModel) { model.leaveAd() }

        case .settings:
            SettingsScreen(
                model: model.settingsModel,
                account: model.accountModel,
                storage: model.storageLabel,
                onCleanStorage: {
                    let message = await model.cleanStorageNow()
                    return (message: message, storage: model.storageLabel)
                },
                // Teams are locked until tried on two phones; only the light can be previewed.
                onTeam: model.isTeamSharingAvailable ? { showsTeam = true } : nil,
                onPreviewLight: { showsTeam = true },
                certificates: model.certificationSummary,
                onCertificates: { showsCertificates = true },
                voiceProfile: model.voiceProfile,
                onVoiceProfile: { showsVoiceProfile = true },
                testFreePlan: AccessModel.isTestFlight
                    ? Binding(get: { model.access.testsFreePlan }, set: { model.access.testsFreePlan = $0 })
                    : nil,
                plus: model.plusUsage,
                onUpgrade: { model.upgradeToPlus() },
                onRestore: { model.restorePlus() },
                onManageSubscription: {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
                },
                suflorReports: model.suflorReportCount > 0 ? "\(model.suflorReportCount)" : AppLocalization.string("suflorReports.none"),
                onSuflorReports: { showsSuflorReports = true },
                allowsHighResolution: { model.access.use(.highResolutionCapture) },
                captureResolutions: CameraSession.supportedResolutions(for: model.settingsModel.settings.defaultCamera),
                cloudBackup: model.cloudBackupRow
            )
            .sheet(isPresented: $showsSuflorReports) {
                SuflorReportsList(
                    isLocked: model.access.plan != .pro,
                    onOpen: { report in
                        showsSuflorReports = false
                        model.openSavedSuflorReport(report)
                    },
                    onClose: { showsSuflorReports = false }
                )
                .presentationDetents([.medium, .large])
            }
            .task { await model.refreshStorage() }
            .fullScreenCover(isPresented: $showsVoiceProfile) {
                VoiceProfileScreen(
                    profile: $model.voiceProfile,
                    isMeasuring: model.isMeasuringVoice,
                    onMeasure: { Task { await model.measureVoiceProfile() } },
                    onClose: { showsVoiceProfile = false }
                )
            }
            .fullScreenCover(isPresented: $showsCertificates) {
                CertificatesScreen(
                    progress: model.certification,
                    canSign: model.dependencies.assistantClient.isConfigured,
                    onName: { model.setCertificateName($0) },
                    onSign: { await model.signCertificate($0) },
                    reviewCandidates: model.reviewCandidates,
                    onReview: { await model.requestReview(of: $0) },
                    onClose: { showsCertificates = false }
                )
            }
            .fullScreenCover(isPresented: $showsTeam) {
                TeamScreen(isSharingAvailable: model.isTeamSharingAvailable, tools: model.teamTools) { showsTeam = false }
            }
        }
    }

    /// The tabs, and the assistant beside them at the same height — part of the navigation, not a
    /// chat bubble floating over it. The tab bar's own trailing inset is the gap between the two.
    private var tabBar: some View {
        HStack(spacing: 0) {
            DSTabBar(
                items: [
                    .init(id: Screen.home, title: AppLocalization.string("tab.home")),
                    .init(id: Screen.projects, title: AppLocalization.string("tab.projects")),
                    .init(id: Screen.workflows, title: AppLocalization.string("tab.workflows")),
                    .init(id: Screen.settings, title: AppLocalization.string("tab.settings")),
                ],
                selection: model.screen
            ) { tab in
                model.go(to: tab)
            }

            AssistantLauncherButton { model.openAssistant() }
                .padding(.trailing, 14)
        }
    }
}
