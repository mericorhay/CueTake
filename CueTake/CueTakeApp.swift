import DesignSystem
import Domain
import SettingsFeature
import SwiftUI

@main
struct CueTakeApp: App {
    @UIApplicationDelegateAdaptor(TeamAppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppContent(model: model, settings: model.settingsModel)
        }
    }
}

/// Reads the language model directly so every explicit selection invalidates the locale
/// environment, including a second or third change while the language sheet is still open.
private struct AppContent: View {
    @Bindable var model: AppModel
    @Bindable var settings: SettingsModel

    var body: some View {
        RootView(model: model)
            .environment(\.locale, settings.settings.language.locale)
            // Type follows the reader's text size this far; past it the layouts stop holding.
            .dynamicTypeSize(...DS.largestTextSize)
            .task { model.startCertificationClock() }
    }
}
