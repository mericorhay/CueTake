import DesignSystem
import Domain
import Foundation

// The prompter's controls are driven by enums, but their labels are shown to the user, so they
// come from the catalog rather than from `rawValue`.

extension TeleprompterModel.Preset {
    var labelKey: String.LocalizationValue {
        switch self {
        case .camera: "teleprompter.preset.camera"
        case .compact: "teleprompter.preset.compact"
        case .band: "teleprompter.preset.band"
        case .full: "teleprompter.preset.full"
        case .corner: "teleprompter.preset.corner"
        case .custom: "teleprompter.preset.custom"
        }
    }

    var label: String {
        AppLocalization.string(labelKey, bundle: .module)
    }

    /// Uppercased for the panel's badge. Locale-aware, so Turkish keeps its dotted İ.
    func uppercasedLabel(locale: Locale) -> String {
        label.uppercased(with: locale)
    }
}

extension TeleprompterModel.SettingsTab {
    var label: String {
        switch self {
        case .layout: AppLocalization.string("teleprompter.tab.layout", bundle: .module)
        case .flow: AppLocalization.string("teleprompter.tab.flow", bundle: .module)
        }
    }
}

extension TeleprompterModel.Alignment {
    var label: String {
        switch self {
        case .left: AppLocalization.string("teleprompter.align.left", bundle: .module)
        case .center: AppLocalization.string("teleprompter.align.center", bundle: .module)
        }
    }
}

extension TeleprompterModel.HighlightMode {
    var label: String {
        switch self {
        case .word: AppLocalization.string("teleprompter.mode.word", bundle: .module)
        case .line: AppLocalization.string("teleprompter.mode.line", bundle: .module)
        case .karaoke: AppLocalization.string("teleprompter.mode.karaoke", bundle: .module)
        }
    }
}
