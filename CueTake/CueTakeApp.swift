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
            RootView(model: model)
                .environment(\.locale, model.settingsModel.settings.language.locale)
                // Type follows the reader's text size this far; past it the layouts stop holding.
                .dynamicTypeSize(...DS.largestTextSize)
                .task { model.startCertificationClock() }
        }
    }
}
