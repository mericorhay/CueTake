import DesignSystem
import Domain
import Foundation
import Persistence
import Testing
@testable import SettingsFeature

@MainActor
struct SettingsLanguageTests {
    @Test func languageCanBeChangedRepeatedlyAndPersistsEveryChoice() {
        let previous = UserDefaults.standard.string(forKey: "cuetake.language.override")
        defer { AppLocalization.select(languageCode: previous) }

        let store = InMemorySettingsStore()
        let model = SettingsModel(store: store)

        for language in [AppLanguage.english, .spanish, .turkish, .english] {
            model.setLanguage(language)
            #expect(model.settings.language == language)
            #expect(store.load().language == language)
            #expect(AppLocalization.locale.identifier == language.localeIdentifier)
        }
    }
}
