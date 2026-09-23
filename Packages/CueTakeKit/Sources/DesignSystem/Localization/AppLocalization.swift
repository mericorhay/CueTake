import Foundation

/// One locale source for SwiftUI text and strings created in models, alerts and status rows.
///
/// SwiftUI's locale environment updates `Text` automatically, but `String(localized:)` otherwise
/// keeps using the process language. Routing those strings here prevents a mixed-language screen
/// after an in-app language change.
public enum AppLocalization {
    // Localization is also needed by import/export workers. These operations only touch
    // Foundation's thread-safe defaults store and immutable locale values, so keeping them
    // nonisolated avoids forcing background media work onto the main actor.
    nonisolated private static let preferenceKey = "cuetake.language.override"

    nonisolated public static var locale: Locale {
        guard let identifier = UserDefaults.standard.string(forKey: preferenceKey), !identifier.isEmpty else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: identifier)
    }

    nonisolated public static func select(languageCode: String?) {
        if let languageCode, !languageCode.isEmpty {
            UserDefaults.standard.set(languageCode, forKey: preferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: preferenceKey)
        }
    }

    nonisolated public static func string(_ key: String.LocalizationValue, bundle: Bundle = .main) -> String {
        String(localized: key, bundle: bundle, locale: locale)
    }
}
