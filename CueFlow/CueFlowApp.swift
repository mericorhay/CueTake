import DesignSystem
import SwiftUI

@main
struct CueFlowApp: App {
    private let dependencies = AppDependencies.live

    var body: some Scene {
        WindowGroup {
            // Root routing between features goes here (AppRouter) once features have screens.
            Palette.background.ignoresSafeArea()
        }
    }
}
