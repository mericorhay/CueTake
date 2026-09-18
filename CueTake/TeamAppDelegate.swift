import CloudKit
import UIKit

/// Where team invites opened from Messages or Mail arrive, until the app is ready for them.
@MainActor
final class ShareInbox {
    static let shared = ShareInbox()

    /// Set by the app once teams have started; anything that came in before it is handed over then.
    var onAccept: ((CKShare.Metadata) -> Void)? {
        didSet { flush() }
    }

    private var waiting: [CKShare.Metadata] = []

    func receive(_ metadata: CKShare.Metadata) {
        waiting.append(metadata)
        flush()
    }

    private func flush() {
        guard let onAccept, !waiting.isEmpty else { return }
        let arrived = waiting
        waiting = []
        arrived.forEach(onAccept)
    }
}

/// Only for teams: push for sync, and the scene hook that receives invites.
///
/// Everything here is switched on by `CUETAKE_TEAMS` alone. A scene delegate sits in the path of
/// every launch, and without teams there is no reason to put anything there.
final class TeamAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if CUETAKE_TEAMS
        // A teammate's save wakes the sync engine with a silent push.
        application.registerForRemoteNotifications()
        #endif
        return true
    }

    #if CUETAKE_TEAMS
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = TeamSceneDelegate.self
        return configuration
    }
    #endif
}

final class TeamSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// An invite that launched the app.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            ShareInbox.shared.receive(metadata)
        }
    }

    /// An invite opened while the app was running.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        ShareInbox.shared.receive(cloudKitShareMetadata)
    }
}
