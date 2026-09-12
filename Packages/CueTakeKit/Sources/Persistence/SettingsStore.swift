import Domain
import Foundation

/// Where `AppSettings` lives between launches.
///
/// A protocol rather than a direct `UserDefaults` call so tests and previews can hand the app a
/// store that keeps nothing, and so the choice of backing store stays one file's business.
public protocol SettingsStore: Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

/// Stores the settings as one JSON blob under a single key.
///
/// One key rather than a key per field: the settings are read and written as a whole, a partial
/// write is never meaningful, and it keeps `AppSettings` free to change shape without leaving
/// orphaned keys behind. Anything unreadable falls back to the defaults instead of throwing —
/// a corrupt preference is not worth failing a launch over.
///
/// `@unchecked` because `UserDefaults` is documented as thread-safe but is not annotated
/// `Sendable`. A final class with two immutable stored properties adds no mutable state of its own,
/// so the guarantee rests entirely on the one Foundation already makes.
public final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "app.settings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return .default }
        return settings
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Keeps settings for the lifetime of the process only. For previews and tests.
public final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: AppSettings

    public init(_ settings: AppSettings = .default) {
        self.settings = settings
    }

    public func load() -> AppSettings {
        lock.withLock { settings }
    }

    public func save(_ settings: AppSettings) {
        lock.withLock { self.settings = settings }
    }
}
