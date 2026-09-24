import Foundation
import Synchronization

/// Settings the app reads from our server at launch, so limits and switches change without an
/// app update. Everything is optional: a missing value keeps what the app ships with, and a build
/// that never reaches the server behaves exactly as written.
///
/// Served by the assistant Worker at `GET /config` (`backend/assistant/config.js`).
public struct RemoteSettings: Hashable, Sendable, Codable {
    /// Monthly limits by meter key, then plan: `{"aiEdit": {"free": 5, "pro": 150}}`. A negative
    /// number means no limit.
    public var limits: [String: [String: Int]]?
    /// Video styles the free plan may use, by raw value. Replaces the built-in list when present.
    public var freeStyles: [String]?
    /// On/off switches, for turning a feature off in a hurry or trying one out.
    public var flags: [String: Bool]?
    /// Free-form values: a paywall line, a provider name.
    public var values: [String: String]?

    public init(limits: [String: [String: Int]]? = nil, freeStyles: [String]? = nil,
                flags: [String: Bool]? = nil, values: [String: String]? = nil) {
        self.limits = limits
        self.freeStyles = freeStyles
        self.flags = flags
        self.values = values
    }

    public func flag(_ name: String, default fallback: Bool) -> Bool { flags?[name] ?? fallback }
    public func value(_ name: String) -> String? { values?[name] }

    /// What is in force now. Set once at launch from the cached copy, again when the server answers.
    public static var current: RemoteSettings { store.withLock { $0 } }

    public static func apply(_ settings: RemoteSettings) { store.withLock { $0 = settings } }

    private static let store = Mutex(RemoteSettings())
}
