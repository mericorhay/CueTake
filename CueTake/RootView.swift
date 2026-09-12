import DesignSystem
import EditorFeature
import LibraryFeature
import OnboardingFeature
import ScriptFeature
import SettingsFeature
import StudioFeature
import SwiftUI
import WorkflowsFeature

/// Hosts every screen and the tab bar. Features never navigate to each other directly —
/// they report what happened and this is the only place that decides where to go.
struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            DS.Palette.screen.ignoresSafeArea()

            screen
                .id(model.screen)

            if model.screen.isRoot {
                tabBar
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var screen: some View {
        switch model.screen {
        case .onboarding:
            OnboardingScreen { model.go(to: .home) }

        case .home:
            HomeScreen(
                onCreate: { model.go(to: .create) },
                onOpenProject: { _ in model.openEditor() },
                onOpenAllProjects: { model.go(to: .projects) },
                onOpenWorkflow: { model.go(to: .workflowDetail) }
            )

        case .create:
            CreateScreen(onBack: { model.go(to: .home) }) { destination in
                switch destination {
                case .prompt: model.go(to: .prompt)
                case .script: model.go(to: .script)
                case .workflow: model.go(to: .workflowDetail)
                case .studio: model.openStudio()
                }
            }

        case .prompt:
            PromptScreen(
                model: model.promptModel,
                onBack: { model.go(to: .create) },
                onGenerated: { model.go(to: .blueprint) }
            )

        case .blueprint:
            BlueprintScreen(
                project: $model.project,
                onBack: { model.go(to: .prompt) },
                onOpenScript: { model.go(to: .script) },
                onOpenStudio: { model.openStudio() }
            )

        case .script:
            ScriptScreen(
                project: $model.project,
                onBack: { model.go(to: .blueprint) },
                onOpenStudio: { model.openStudio() }
            )

        case .studio:
            StudioScreen(
                model: model.studioModel,
                onBack: { model.go(to: .blueprint) },
                onOpenEditor: { model.openEditor() },
                onFinished: { model.go(to: .complete) }
            )

        case .complete:
            CompleteScreen(
                project: model.project,
                onRetake: { model.startRetakeFromComplete() },
                onEdit: { model.openEditor() },
                onDone: { model.go(to: .export) }
            )

        case .editor:
            EditorScreen(
                model: model.editorModel,
                onBack: { model.go(to: .home) },
                onExport: { model.go(to: .export) },
                onCaptions: { model.go(to: .captions) },
                onRetake: { model.startRetake(of: $0) }
            )

        case .retake:
            if let retakeModel = model.retakeModel {
                RetakeScreen(
                    model: retakeModel,
                    onBack: { model.openEditor() },
                    onKeep: { _ in model.keepRetake() }
                )
            }

        case .captions:
            CaptionsScreen(
                project: model.project,
                onBack: { model.openEditor() },
                onExport: { model.go(to: .export) }
            )

        case .export:
            ExportScreen(
                model: model.exportModel,
                onBack: { model.openEditor() },
                onDone: { model.finishExport() }
            )

        case .projects:
            ProjectsScreen { _ in model.openEditor() }

        case .workflows:
            WorkflowsScreen { _ in model.go(to: .workflowDetail) }

        case .workflowDetail:
            WorkflowDetailScreen(
                model: model.workflowModel,
                onBack: { model.go(to: .workflows) },
                onOpenResult: { model.openEditor() }
            )

        case .settings:
            SettingsScreen()
        }
    }

    private var tabBar: some View {
        DSTabBar(
            items: [
                .init(id: Screen.home, title: String(localized: "tab.home")),
                .init(id: Screen.projects, title: String(localized: "tab.projects")),
                .init(id: Screen.workflows, title: String(localized: "tab.workflows")),
                .init(id: Screen.settings, title: String(localized: "tab.settings")),
            ],
            selection: model.screen
        ) { tab in
            model.go(to: tab)
        }
    }
}
