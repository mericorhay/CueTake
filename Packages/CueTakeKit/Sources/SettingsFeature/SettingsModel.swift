import Domain
import DesignSystem
import Observation
import Persistence

/// Holds the settings and writes every change straight through to the store.
///
/// There is no Save button and no dirty state: a preference screen that needs confirming is a
/// preference screen that loses edits when someone swipes back. Writes are cheap — one small JSON
/// blob — so the simple thing is also the correct one.
@MainActor
@Observable
public final class SettingsModel {
    public private(set) var settings: AppSettings

    private let store: any SettingsStore

    public init(store: any SettingsStore) {
        self.store = store
        self.settings = store.load()
        AppLocalization.select(languageCode: settings.language.localeIdentifier)
    }

    /// Applies one change. Callers pass a key path rather than a whole `AppSettings`, so a screen
    /// can never write back a stale copy of the fields it was not editing.
    public func update<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>, to value: Value) {
        settings[keyPath: keyPath] = value
        store.save(settings)
    }

    public func setLanguage(_ language: AppLanguage) {
        AppLocalization.select(languageCode: language.localeIdentifier)
        update(\.language, to: language)
    }
}
