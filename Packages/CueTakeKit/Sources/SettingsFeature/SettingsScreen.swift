import DesignSystem
import Domain
import Persistence
import SwiftUI
import UIKit

public struct SettingsScreen: View {
    private let model: SettingsModel

    /// What the app takes on the phone, or nil while it is measured.
    private let storage: String?
    private let onCleanStorage: (() -> Void)?
    /// Opens the team screen. Nil where there is none.
    private let onTeam: (() -> Void)?
    /// A preview of the light two phones make, behind a long press on the version: for trying the
    /// animation while teams themselves are switched off.
    private let onPreviewLight: (() -> Void)?
    /// Where the creator stands toward the certificates, and the way in. Nil hides the row.
    private let certificates: String?
    private let onCertificates: (() -> Void)?
    /// One line about the voice profile, and the way into it.
    private let voiceProfile: CreatorVoiceProfile?
    private let onVoiceProfile: (() -> Void)?

    public init(
        model: SettingsModel,
        storage: String? = nil,
        onCleanStorage: (() -> Void)? = nil,
        onTeam: (() -> Void)? = nil,
        onPreviewLight: (() -> Void)? = nil,
        certificates: String? = nil,
        onCertificates: (() -> Void)? = nil,
        voiceProfile: CreatorVoiceProfile? = nil,
        onVoiceProfile: (() -> Void)? = nil
    ) {
        self.voiceProfile = voiceProfile
        self.onVoiceProfile = onVoiceProfile
        self.certificates = certificates
        self.onCertificates = onCertificates
        self.model = model
        self.storage = storage
        self.onCleanStorage = onCleanStorage
        self.onTeam = onTeam
        self.onPreviewLight = onPreviewLight
    }

    @State private var showsConverter = false
    @State private var showsAPIKey = false

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DSHeadline(String(localized: "settings.title", bundle: .module), size: 34)

                profile
                    .padding(.top, 22)
                    .padding(.bottom, onCertificates == nil ? 22 : 12)

                if let onCertificates {
                    certificateRow(onCertificates)
                        .padding(.bottom, onVoiceProfile == nil ? 22 : 12)
                }

                if let onVoiceProfile {
                    voiceRow(onVoiceProfile)
                        .padding(.bottom, 22)
                }

                VStack(spacing: 0) {
                    languageRow

                    picker("settings.camera", CameraPosition.allCases, model.settings.defaultCamera, \.label) {
                        model.update(\.defaultCamera, to: $0)
                    }

                    picker("settings.quality", VideoFormat.Resolution.allCases, model.settings.captureResolution, \.label) {
                        model.update(\.captureResolution, to: $0)
                    }

                    picker("settings.captions", CaptionPreference.allCases, model.settings.captionPreset, \.label) {
                        model.update(\.captionPreset, to: $0)
                    }

                    picker("settings.rememberStyle", [true, false], model.settings.remembersStyle, \.rememberLabel) {
                        model.update(\.remembersStyle, to: $0)
                    }

                    picker("settings.ai", AIProcessing.allCases, model.settings.aiProcessing, \.label) {
                        model.update(\.aiProcessing, to: $0)
                    }

                    picker("settings.export", ExportDestination.allCases, model.settings.exportDestination, \.label) {
                        model.update(\.exportDestination, to: $0)
                    }

                    Button {
                        showsConverter = true
                    } label: {
                        row(
                            String(localized: "settings.converter", bundle: .module),
                            value: String(localized: "settings.converter.value", bundle: .module)
                        )
                    }
                    .buttonStyle(.dsPress)

                    Button {
                        showsAPIKey = true
                    } label: {
                        row(
                            String(localized: "settings.apiKey", bundle: .module),
                            value: APIKeySheet.connectedCount == 0
                                ? String(localized: "settings.apiKey.none", bundle: .module)
                                : String(localized: "settings.apiKey.connected \(APIKeySheet.connectedCount)", bundle: .module)
                        )
                    }
                    .buttonStyle(.dsPress)

                    if let onTeam {
                        Button(action: onTeam) {
                            row(
                                String(localized: "settings.team", bundle: .module),
                                value: String(localized: "settings.team.value", bundle: .module)
                            )
                        }
                        .buttonStyle(.dsPress)
                    }

                    if let onCleanStorage {
                        Button(action: onCleanStorage) {
                            row(
                                String(localized: "settings.storage", bundle: .module),
                                value: storage.map { String(localized: "settings.storage.value \($0)", bundle: .module) }
                                    ?? String(localized: "settings.storage.measuring", bundle: .module)
                            )
                        }
                        .buttonStyle(.dsPress)
                    }

                    // No subscription row until there is a subscription: it said "Pro" to everyone.
                    staticRow("settings.version", Self.version, isLast: true)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 2) { onPreviewLight?() }
                }
                .dsCard(radius: DS.Radius.card)
            }
            .padding(.horizontal, 22)
            .padding(.top, 64)
            .padding(.bottom, 108)
        }
        .scrollIndicators(.hidden)
        .dsScreenLayout(scrolls: true)
        .background(DS.Palette.screen)
        .sheet(isPresented: $showsAPIKey) {
            APIKeySheet(onClose: { showsAPIKey = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsConverter) {
            ConverterSheet(onClose: { showsConverter = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .dsEnter(.screen())
    }

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }()

    private var profile: some View {
        HStack(spacing: 13) {
            Circle()
                .fill(DS.gradient(140, [DS.Palette.accentWarm, DS.Palette.accent]))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("settings.profile.name", bundle: .module)
                    .dsFont(.sans, .semibold, 15)
                    .foregroundStyle(DS.Palette.ink)
                Text("settings.profile.plan", bundle: .module)
                    .dsFont(.mono, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.56))
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .dsCard(radius: DS.Radius.card)
    }

    /// The way into the certificates, shown as the standing toward the next one.
    private func certificateRow(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: "rosette")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(DS.gradient(140, [DS.Palette.lime, DS.Palette.accentWarm])))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("settings.certificates", bundle: .module)
                        .dsFont(.sans, .semibold, 15)
                        .foregroundStyle(DS.Palette.ink)
                    if let certificates {
                        Text(verbatim: certificates)
                            .dsFont(.sans, .regular, 12)
                            .foregroundStyle(DS.Palette.ink(0.62))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink(0.52))
                    .accessibilityHidden(true)
            }
            .padding(15)
            .dsCard(radius: DS.Radius.card)
        }
        .buttonStyle(.dsPressCard)
    }

    private var voiceSummary: String {
        guard let pace = voiceProfile?.wordsPerMinute else { return String(localized: "settings.voice.empty", bundle: .module) }
        let sentence = Int((voiceProfile?.sentenceWords ?? 0).rounded())
        return String(localized: "settings.voice.summary \(Int(pace.rounded())) \(sentence)", bundle: .module)
    }

    private func voiceRow(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(DS.gradient(140, [DS.Palette.accentWarm, DS.Palette.accent])))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("settings.voice", bundle: .module)
                        .dsFont(.sans, .semibold, 15)
                        .foregroundStyle(DS.Palette.ink)
                    Text(verbatim: voiceSummary)
                        .dsFont(.sans, .regular, 12)
                        .foregroundStyle(DS.Palette.ink(0.62))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.ink(0.52))
                    .accessibilityHidden(true)
            }
            .padding(15)
            .dsCard(radius: DS.Radius.card)
        }
        .buttonStyle(.dsPressCard)
    }

    // MARK: - Rows

    /// iOS owns per-app language. A picker of our own here would either lie, or force every string
    /// in the app to be looked up against an override locale. So the row reports what the system
    /// is using and opens the one place where it can actually be changed.
    private var languageRow: some View {
        Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        } label: {
            row(String(localized: "settings.language", bundle: .module), value: Self.languageName)
        }
        .buttonStyle(.dsPress)
    }

    private static let languageName: String = {
        let identifier = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        return Locale.current.localizedString(forLanguageCode: identifier)?.capitalized(with: .current)
            ?? identifier
    }()

    private func picker<Option: Hashable>(
        _ titleKey: String.LocalizationValue,
        _ options: [Option],
        _ selection: Option,
        _ label: KeyPath<Option, String>,
        onSelect: @escaping (Option) -> Void
    ) -> some View {
        Menu {
            // A list of buttons rather than a Picker: the design's row *is* the label, and Picker
            // insists on bringing its own along.
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    onSelect(option)
                } label: {
                    if option == selection {
                        Label(option[keyPath: label], systemImage: "checkmark")
                    } else {
                        Text(option[keyPath: label])
                    }
                }
            }
        } label: {
            row(String(localized: titleKey, bundle: .module), value: selection[keyPath: label])
        }
    }

    private func staticRow(_ titleKey: String.LocalizationValue, _ value: String, isLast: Bool = false) -> some View {
        row(String(localized: titleKey, bundle: .module), value: value, chevron: false, isLast: isLast)
    }

    private func row(_ title: String, value: String, chevron: Bool = true, isLast: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .dsFont(.sans, .medium, 14)
                .foregroundStyle(DS.Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .dsFont(.sans, .regular, 13)
                .foregroundStyle(DS.Palette.ink(0.52))
                .lineLimit(1)

            if chevron {
                Text("›")
                    .font(.system(size: 15))
                    .foregroundStyle(DS.Palette.ink(0.25))
                    .padding(.leading, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(DS.Palette.hairline(0.05))
                    .frame(height: 1)
            }
        }
    }
}

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
    fileprivate var rememberLabel: String {
        self
            ? String(localized: "settings.rememberStyle.on", bundle: .module)
            : String(localized: "settings.rememberStyle.off", bundle: .module)
    }
}
