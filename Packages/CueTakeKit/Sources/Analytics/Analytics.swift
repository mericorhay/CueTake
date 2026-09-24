import Foundation
@preconcurrency import PostHog
import Synchronization

/// Product analytics, through PostHog. The one place the app talks to it.
///
/// What leaves the phone is which features are used, where the limits are hit and whether
/// CueTake+ is bought: named events with a handful of plain properties. Never a script, a caption,
/// a title, a file name, a frame or a recording. There is no session replay and no automatic screen
/// or tap capture, because the screens show people's faces and words. The id is a random one
/// PostHog makes on the phone, never tied to the account or the Apple ID.
///
/// The key comes from `Analytics.json` in the app bundle, which CI writes from repository secrets.
/// Without it nothing is sent, and every call here does nothing.
public enum Analytics {
    private struct Config: Decodable {
        var apiKey: String
        var host: String?
    }

    private static let optOutKey = "cuetake.analytics.optOut"
    private static let started = Mutex(false)

    /// Starts PostHog once, when the build has a key and the person has not turned it off.
    public static func start(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "Analytics", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(Config.self, from: data),
              !config.apiKey.isEmpty
        else { return }
        let first = started.withLock { value in
            defer { value = true }
            return !value
        }
        guard first else { return }

        let settings = PostHogConfig(apiKey: config.apiKey, host: config.host ?? "https://us.i.posthog.com")
        settings.captureApplicationLifecycleEvents = true
        settings.captureScreenViews = false
        PostHogSDK.shared.setup(settings)
        if !isOn { PostHogSDK.shared.optOut() }
    }

    public static var isConfigured: Bool { started.withLock { $0 } }

    /// The Settings switch. On unless the person turned it off.
    public static var isOn: Bool {
        get { !UserDefaults.standard.bool(forKey: optOutKey) }
        set {
            UserDefaults.standard.set(!newValue, forKey: optOutKey)
            guard isConfigured else { return }
            if newValue { PostHogSDK.shared.optIn() } else { PostHogSDK.shared.optOut() }
        }
    }

    /// One thing that happened, with its plain properties.
    public static func track(_ event: String, _ properties: [String: AnalyticsValue] = [:]) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture(event, properties: properties.mapValues(\.raw))
    }

    /// Sent with every event from now on: the plan, the app's language.
    public static func remember(_ properties: [String: AnalyticsValue]) {
        guard isConfigured else { return }
        PostHogSDK.shared.register(properties.mapValues(\.raw))
    }

    /// Sends what is waiting now, rather than at the next batch: called when the app leaves the
    /// screen, so a short session is not lost.
    public static func flush() {
        guard isConfigured else { return }
        PostHogSDK.shared.flush()
    }

    /// A screen the person moved to, by our own name for it.
    public static func screen(_ name: String) {
        guard isConfigured else { return }
        PostHogSDK.shared.screen(name)
    }
}

/// The only kinds of value an event may carry: no free text from the person gets in by accident.
public enum AnalyticsValue: Sendable, Hashable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    case text(String)
    case number(Double)
    case flag(Bool)

    public init(stringLiteral value: String) { self = .text(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(booleanLiteral value: Bool) { self = .flag(value) }

    public static func int(_ value: Int) -> AnalyticsValue { .number(Double(value)) }

    var raw: Any {
        switch self {
        case .text(let value): value
        case .number(let value): value
        case .flag(let value): value
        }
    }
}
