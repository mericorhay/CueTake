import SwiftUI

@main
struct CueTakeApp: App {
    @UIApplicationDelegateAdaptor(TeamAppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
