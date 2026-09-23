import Foundation

/// One locale source for SwiftUI text and strings created in models, alerts and status rows.
///
/// SwiftUI's locale environment updates `Text` automatically, but `String(localized:)` otherwise
/// keeps using the process language. Routing those strings here prevents a mixed-language screen
/// after an in-app language change.
public enum AppLocalization {
    private static let preferenceKey = "cuetake.language.override"

    public static var locale: Locale {
        guard let identifier = UserDefaults.standard.string(forKey: preferenceKey), !identifier.isEmpty else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: identifier)
    }

    public static func select(languageCode: String?) {
        if let languageCode, !languageCode.isEmpty {
            UserDefaults.standard.set(languageCode, forKey: preferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: preferenceKey)
        }
    }

    public static func string(_ key: String.LocalizationValue, bundle: Bundle = .main) -> String {
        String(localized: key, bundle: bundle, locale: locale)
    }
}
