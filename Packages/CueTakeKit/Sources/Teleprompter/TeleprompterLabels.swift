import Domain
import Foundation

// The prompter's controls are driven by enums, but their labels are shown to the user, so they
// come from the catalog rather than from `rawValue`.

extension TeleprompterModel.Preset {
    var labelKey: String.LocalizationValue {
        switch self {
        case .compact: "teleprompter.preset.compact"
        case .band: "teleprompter.preset.band"
        case .full: "teleprompter.preset.full"
        case .corner: "teleprompter.preset.corner"
        case .custom: "teleprompter.preset.custom"
        }
    }

    var label: String {
        String(localized: labelKey, bundle: .module)
    }

    /// Uppercased for the panel's badge. Locale-aware, so Turkish keeps its dotted İ.
    func uppercasedLabel(locale: Locale) -> String {
        label.uppercased(with: locale)
    }
}

extension TeleprompterModel.SettingsTab {
    var label: String {
        switch self {
        case .layout: String(localized: "teleprompter.tab.layout", bundle: .module)
        case .flow: String(localized: "teleprompter.tab.flow", bundle: .module)
        }
    }
}

extension TeleprompterModel.Alignment {
    var label: String {
        switch self {
        case .left: String(localized: "teleprompter.align.left", bundle: .module)
        case .center: String(localized: "teleprompter.align.center", bundle: .module)
        }
    }
}

extension TeleprompterModel.HighlightMode {
    var label: String {
        switch self {
        case .word: String(localized: "teleprompter.mode.word", bundle: .module)
        case .line: String(localized: "teleprompter.mode.line", bundle: .module)
        case .karaoke: String(localized: "teleprompter.mode.karaoke", bundle: .module)
        }
    }
}
