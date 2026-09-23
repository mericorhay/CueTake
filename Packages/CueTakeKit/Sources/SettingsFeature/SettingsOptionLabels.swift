import DesignSystem
import Domain
import Foundation

// MARK: - Option labels
//
// Domain owns the cases; what they are called on screen is this module's business.

extension CameraPosition {
    var label: String {
        switch self {
        case .front: AppLocalization.string("settings.camera.front", bundle: .module)
        case .back: AppLocalization.string("settings.camera.back", bundle: .module)
        }
    }
}

extension CaptionPreference {
    var label: String {
        switch self {
        case .off: AppLocalization.string("settings.captions.off", bundle: .module)
        case .pop: AppLocalization.string("settings.captions.pop", bundle: .module)
        case .clean: AppLocalization.string("settings.captions.clean", bundle: .module)
        case .karaoke: AppLocalization.string("settings.captions.karaoke", bundle: .module)
        case .bold: AppLocalization.string("settings.captions.bold", bundle: .module)
        case .boxed: AppLocalization.string("settings.captions.boxed", bundle: .module)
        case .minimal: AppLocalization.string("settings.captions.minimal", bundle: .module)
        case .neon: AppLocalization.string("settings.captions.neon", bundle: .module)
        case .story: AppLocalization.string("settings.captions.story", bundle: .module)
        }
    }
}

extension AIProcessing {
    var label: String {
        switch self {
        case .onDeviceOnly: AppLocalization.string("settings.ai.onDevice", bundle: .module)
        case .allowCloud: AppLocalization.string("settings.ai.cloud", bundle: .module)
        }
    }
}

extension ExportDestination {
    var label: String {
        switch self {
        case .photoLibrary: AppLocalization.string("settings.export.photos", bundle: .module)
        case .files: AppLocalization.string("settings.export.files", bundle: .module)
        }
    }
}

extension Bool {
    /// "On" or "Off" for the remember-my-style row.
    var rememberLabel: String {
        self
            ? AppLocalization.string("settings.rememberStyle.on", bundle: .module)
            : AppLocalization.string("settings.rememberStyle.off", bundle: .module)
    }
}
