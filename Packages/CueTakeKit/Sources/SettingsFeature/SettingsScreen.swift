import Domain
import Foundation

// MARK: - Option labels
//
// Domain owns the cases; what they are called on screen is this module's business.

extension CameraPosition {
    var label: String {
        switch self {
        case .front: String(localized: "settings.camera.front", bundle: .module)
        case .back: String(localized: "settings.camera.back", bundle: .module)
        }
    }
}

extension CaptionPreference {
    var label: String {
        switch self {
        case .off: String(localized: "settings.captions.off", bundle: .module)
        case .pop: String(localized: "settings.captions.pop", bundle: .module)
        case .clean: String(localized: "settings.captions.clean", bundle: .module)
        case .karaoke: String(localized: "settings.captions.karaoke", bundle: .module)
        case .bold: String(localized: "settings.captions.bold", bundle: .module)
        case .boxed: String(localized: "settings.captions.boxed", bundle: .module)
        case .minimal: String(localized: "settings.captions.minimal", bundle: .module)
        case .neon: String(localized: "settings.captions.neon", bundle: .module)
        case .story: String(localized: "settings.captions.story", bundle: .module)
        }
    }
}

extension AIProcessing {
    var label: String {
        switch self {
        case .onDeviceOnly: String(localized: "settings.ai.onDevice", bundle: .module)
        case .allowCloud: String(localized: "settings.ai.cloud", bundle: .module)
        }
    }
}

extension ExportDestination {
    var label: String {
        switch self {
        case .photoLibrary: String(localized: "settings.export.photos", bundle: .module)
        case .files: String(localized: "settings.export.files", bundle: .module)
        }
    }
}

extension Bool {
    /// "On" or "Off" for the remember-my-style row.
    var rememberLabel: String {
        self
            ? String(localized: "settings.rememberStyle.on", bundle: .module)
            : String(localized: "settings.rememberStyle.off", bundle: .module)
    }
}
