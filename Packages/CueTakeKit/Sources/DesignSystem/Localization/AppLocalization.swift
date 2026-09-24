import Foundation
import ObjectiveC

/// One locale source for SwiftUI text and strings created in models, alerts and status rows.
///
/// Neither SwiftUI's locale environment nor `String(localized:locale:)` picks the language a string
/// is read in: both only format numbers and dates, and the lookup keeps using the language the
/// process started in. So a language chosen in the app is applied at the lookup itself: every
/// bundle's `localizedString(forKey:value:table:)` reads from that language's `.lproj` folder,
/// which SwiftUI's `Text`, `Button` and `Label` all go through. The choice is also written to
/// `AppleLanguages`, so the next launch starts in it and system-drawn text follows too.
public enum AppLocalization {
    // Localization is also needed by import/export workers. These operations only touch
    // Foundation's thread-safe defaults store, immutable locale values and a locked cache, so
    // keeping them nonisolated avoids forcing background media work onto the main actor.
    nonisolated private static let preferenceKey = "cuetake.language.override"
    nonisolated private static let systemLanguagesKey = "AppleLanguages"

    nonisolated public static var locale: Locale {
        guard let identifier = languageCode else { return .autoupdatingCurrent }
        return Locale(identifier: identifier)
    }

    /// The language picked in the app, or nil to follow the system.
    nonisolated public static var languageCode: String? {
        guard let identifier = UserDefaults.standard.string(forKey: preferenceKey), !identifier.isEmpty else { return nil }
        return identifier
    }

    nonisolated public static func select(languageCode: String?) {
        LanguageBundles.install()
        if let languageCode, !languageCode.isEmpty {
            UserDefaults.standard.set(languageCode, forKey: preferenceKey)
            UserDefaults.standard.set([languageCode], forKey: systemLanguagesKey)
        } else {
            UserDefaults.standard.removeObject(forKey: preferenceKey)
            UserDefaults.standard.removeObject(forKey: systemLanguagesKey)
        }
    }

    nonisolated public static func string(_ key: String.LocalizationValue, bundle: Bundle = .main) -> String {
        String(localized: key, bundle: LanguageBundles.bundle(for: bundle), locale: locale)
    }
}

/// The `.lproj` folder of the chosen language inside each bundle, and the lookup that reads from it.
nonisolated enum LanguageBundles {
    private nonisolated final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var installed = false
        var folders: [String: Bundle] = [:]
        var missing: Set<String> = []
    }

    nonisolated private static let cache = Cache()

    /// Routes every bundle's string lookup through the chosen language. Done once, on first use.
    nonisolated static func install() {
        cache.lock.lock()
        defer { cache.lock.unlock() }
        guard !cache.installed else { return }
        cache.installed = true
        let original = #selector(Bundle.localizedString(forKey:value:table:))
        let replacement = #selector(Bundle.cueTakeLocalizedString(forKey:value:table:))
        guard let a = class_getInstanceMethod(Bundle.self, original),
              let b = class_getInstanceMethod(Bundle.self, replacement)
        else { return }
        method_exchangeImplementations(a, b)
    }

    /// The chosen language's folder in `bundle`, or `bundle` itself when there is no choice or no
    /// folder for it.
    nonisolated static func bundle(for bundle: Bundle) -> Bundle {
        guard let code = AppLocalization.languageCode else { return bundle }
        return folder(in: bundle, code: code) ?? bundle
    }

    nonisolated static func folder(in bundle: Bundle, code: String) -> Bundle? {
        let path = bundle.bundlePath
        if path.hasSuffix(".lproj") { return nil }
        let key = path + "|" + code
        cache.lock.lock()
        if let found = cache.folders[key] { cache.lock.unlock(); return found }
        if cache.missing.contains(key) { cache.lock.unlock(); return nil }
        cache.lock.unlock()

        let base = String(code.prefix { $0 != "-" && $0 != "_" })
        var found: Bundle?
        for name in [code, base] {
            if let folder = bundle.path(forResource: name, ofType: "lproj"), let loaded = Bundle(path: folder) {
                found = loaded
                break
            }
        }

        cache.lock.lock()
        if let found { cache.folders[key] = found } else { cache.missing.insert(key) }
        cache.lock.unlock()
        return found
    }
}

extension Bundle {
    /// Swapped with `localizedString(forKey:value:table:)`: calling this name runs the original.
    @objc nonisolated func cueTakeLocalizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        // Only the app's own bundles. Apple's frameworks keep their strings outside the `.lproj`
        // folders, so reading them there gave raw keys: Sign in with Apple drew "CONTINUE_WITH_APPLE".
        if let code = AppLocalization.languageCode, !bundlePath.hasPrefix("/System"),
           let folder = LanguageBundles.folder(in: self, code: code) {
            let found = folder.cueTakeLocalizedString(forKey: key, value: value, table: tableName)
            if found != key || value == key { return found }
        }
        return cueTakeLocalizedString(forKey: key, value: value, table: tableName)
    }
}
