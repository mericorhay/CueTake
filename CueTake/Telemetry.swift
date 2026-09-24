import AIServices
import Analytics
import DesignSystem
import Domain
import Foundation

/// Analytics and the server's settings, started together at launch.
///
/// Events are named here and in the few places that send one, always with plain values (a
/// feature's name, a count, a resolution), never anything the person wrote or recorded.
extension AppModel {
    func startTelemetry() {
        RemoteSettingsLoader.applyCached()
        Analytics.start()
        rememberForAnalytics()
        Analytics.track("app_launched", [
            "projects": .int(library.count),
            "signed_in": .flag(accountModel.account != nil),
            "icloud_backup": .flag(cloudBackup.isOn),
            "tester": .flag(AccessModel.isTestFlight),
        ])
        accountModel.onEvent = { [weak self] name in
            Analytics.track(name)
            self?.rememberForAnalytics()
        }
        Task { await RemoteSettingsLoader.refresh() }
    }

    /// Properties sent with every event from now on.
    func rememberForAnalytics() {
        Analytics.remember([
            "plan": .text(access.plan.rawValue),
            "app_language": .text(AppLocalization.languageCode ?? Locale.current.language.languageCode?.identifier ?? "system"),
            "build": .text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"),
            "signed_in": .flag(accountModel.account != nil),
            "icloud_backup": .flag(cloudBackup.isOn),
            "ai_cloud": .flag(settingsModel.settings.aiProcessing == .allowCloud),
        ])
    }
}

extension Screen {
    /// The screen's name in analytics.
    var analyticsName: String { String(describing: self) }
}

extension AccessPoint {
    /// The feature's name in analytics.
    var analyticsName: String {
        switch self {
        case .videoStyle(let style): "videoStyle.\(style.rawValue)"
        case .soundDesign: "soundDesign"
        case .beatSync: "beatSync"
        case .brandTemplate: "brandTemplate"
        case .multiPlatformExport: "multiPlatformExport"
        case .highResolutionExport: "highResolutionExport"
        case .highResolutionCapture: "highResolutionCapture"
        case .suflorReport: "suflorReport"
        case .iCloudBackup: "iCloudBackup"
        default: meterKey ?? "unknown"
        }
    }
}

extension AccessDecision {
    var analyticsName: String {
        switch self {
        case .allowed: "allowed"
        case .proOnly: "proOnly"
        case .limitReached: "limitReached"
        }
    }
}

/// Reads `GET /config` from the assistant Worker and keeps the last answer for the next launch,
/// so an offline start still has the limits the server last gave.
enum RemoteSettingsLoader {
    private static let cacheKey = "cuetake.remoteSettings.v1"

    static func applyCached() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let settings = try? JSONDecoder().decode(RemoteSettings.self, from: data)
        else { return }
        RemoteSettings.apply(settings)
    }

    static func refresh() async {
        guard let endpoint = AssistantClient.bundled().endpoint else { return }
        var request = URLRequest(url: endpoint.url.appending(path: "config"))
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(endpoint.appToken, forHTTPHeaderField: "x-cuetake-app")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let settings = try? JSONDecoder().decode(RemoteSettings.self, from: data)
        else { return }
        RemoteSettings.apply(settings)
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}
