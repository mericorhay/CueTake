import DesignSystem
import SwiftUI

@main
struct CueTakeApp: App {
    @UIApplicationDelegateAdaptor(TeamAppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                // Type follows the reader's text size this far; past it the layouts stop holding.
                .dynamicTypeSize(...DS.largestTextSize)
                .task { model.startCertificationClock() }
        }
    }
}
