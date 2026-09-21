import AccountEngine
import DesignSystem
import Foundation
import Domain
import SwiftUI
import UIKit

public struct SettingsScreen: View {
    private let model: SettingsModel
    private let account: AccountModel
    private let storage: String?
    private let onCleanStorage: (() -> Void)?
    private let onTeam: (() -> Void)?
    private let onPreviewLight: (() -> Void)?
    private let certificates: String?
    private let onCertificates: (() -> Void)?
    private let voiceProfile: CreatorVoiceProfile?
    private let onVoiceProfile: (() -> Void)?
    @State private var destination: SettingsDestination?
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: SettingsModel, account: AccountModel, storage: String? = nil,
                onCleanStorage: (() -> Void)? = nil, onTeam: (() -> Void)? = nil,
                onPreviewLight: (() -> Void)? = nil, certificates: String? = nil,
                onCertificates: (() -> Void)? = nil, voiceProfile: CreatorVoiceProfile? = nil,
                onVoiceProfile: (() -> Void)? = nil) {
        self.model = model; self.account = account; self.storage = storage
        self.onCleanStorage = onCleanStorage; self.onTeam = onTeam; self.onPreviewLight = onPreviewLight
        self.certificates = certificates; self.onCertificates = onCertificates
        self.voiceProfile = voiceProfile; self.onVoiceProfile = onVoiceProfile
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("settings.studio.kicker", bundle: .module)
                            .font(DS.mono(11)).tracking(2).foregroundStyle(DS.Palette.accent)
                        Text("settings.title", bundle: .module)
                            .font(DS.archivo(.bold, 38)).tracking(-1.4)
                            .foregroundStyle(DS.Palette.ink).accessibilityAddTraits(.isHeader)
                        Text("settings.studio.subtitle", bundle: .module)
                            .font(DS.sans(.regular, 15)).foregroundStyle(DS.Palette.ink(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .settingsEntrance(appeared, delay: 0, reduced: reduceMotion)

                    Button { destination = .account } label: {
                        HStack(alignment: .center, spacing: 18) {
                            AccountEmblem(compact: true, connected: account.account != nil)
                                .frame(width: 64, height: 72)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(account.account?.name.isEmpty == false ? account.account!.name : settingsText(account.account == nil ? "account.invite" : "account.title"))
                                    .font(DS.archivo(.semibold, 23)).tracking(-0.6)
                                    .foregroundStyle(DS.Palette.ink)
                                Text(account.account == nil ? "account.invite.detail" : "account.connected.detail", bundle: .module)
                                    .font(DS.sans(.regular, 13)).foregroundStyle(DS.Palette.ink(0.65))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DS.Palette.accent).accessibilityHidden(true)
                        }
                        .padding(20)
                        .background {
                            RoundedRectangle(cornerRadius: 28).fill(DS.Palette.surface)
                                .overlay(alignment: .leading) {
                                    RadialGradient(colors: [DS.Palette.accent(0.15), .clear], center: .leading, startRadius: 0, endRadius: 230)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 28))
                        }
                        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(DS.Palette.accent(0.2), lineWidth: 1))
                    }
                    .buttonStyle(SettingsPressStyle())
                    .settingsEntrance(appeared, delay: 0.04, reduced: reduceMotion)

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("settings.section.workspace")
                        VStack(spacing: 8) {
                            category(.capture, subtitle: "\(model.settings.defaultCamera.label) · \(model.settings.captureResolution.label)")
                            category(.editing, subtitle: model.settings.captionPreset.label)
                            category(.intelligence, subtitle: model.settings.aiProcessing.label)
                            category(.device, subtitle: settingsText("settings.device.summary"))
                        }
                    }
                    .settingsEntrance(appeared, delay: 0.08, reduced: reduceMotion)

                    if onVoiceProfile != nil || onCertificates != nil || onTeam != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("settings.section.creator")
                            VStack(spacing: 1) {
                                if let onVoiceProfile {
                                    Button(action: onVoiceProfile) {
                                        SettingsRow(icon: "waveform", title: settingsText("settings.voice"),
                                                    detail: voiceProfile?.wordsPerMinute.map { "\(Int($0.rounded())) " + settingsText("settings.voice.pace") }
                                                        ?? settingsText("settings.voice.empty"))
                                    }
                                }
                                if let onCertificates {
                                    Button(action: onCertificates) {
                                        SettingsRow(icon: "rosette", title: settingsText("settings.certificates"), detail: certificates)
                                    }
                                }
                                if let onTeam {
                                    Button(action: onTeam) {
                                        SettingsRow(icon: "person.2", title: settingsText("settings.team"), detail: settingsText("settings.team.value"))
                                    }
                                }
                            }
                            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                            .buttonStyle(SettingsPressStyle())
                        }
                        .settingsEntrance(appeared, delay: 0.12, reduced: reduceMotion)
                    }

                    VStack(spacing: 8) {
                        Text("CueTake").font(DS.archivo(.bold, 20)).tracking(-0.6)
                        Text(Self.version).font(DS.mono(11))
                            .onLongPressGesture(minimumDuration: 2) { onPreviewLight?() }
                        Text("settings.footer", bundle: .module).font(DS.sans(.regular, 12))
                    }
                    .foregroundStyle(DS.Palette.ink(0.4))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .padding(.horizontal, 22)
                .padding(.top, max(geometry.safeAreaInsets.top, 54) + 16)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20) + 100)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(DS.Palette.screen)
        .onAppear {
            appeared = true
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-account-preview") { destination = .account }
            if ProcessInfo.processInfo.arguments.contains("-privacy-preview") { destination = .device }
            #endif
        }
        .sheet(item: $destination) { selected in
            if selected == .account {
                AccountSheet(model: account)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(32)
            } else {
                SettingsPanel(destination: selected, model: model, storage: storage, onCleanStorage: onCleanStorage)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(32)
            }
        }
    }

    private func category(_ value: SettingsDestination, subtitle: String) -> some View {
        Button { destination = value } label: {
            SettingsRow(icon: value.icon, title: settingsText(value.title), detail: subtitle)
                .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(SettingsPressStyle())
    }

    private func sectionTitle(_ key: String.LocalizationValue) -> some View {
        Text(settingsText(key)).font(DS.sans(.semibold, 13))
            .foregroundStyle(DS.Palette.ink(0.55)).padding(.leading, 4).accessibilityAddTraits(.isHeader)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "—") (\(info?["CFBundleVersion"] as? String ?? "—"))"
    }
}

enum SettingsDestination: String, Identifiable {
    case account, capture, editing, intelligence, device
    var id: Self { self }
    var title: String.LocalizationValue {
        switch self {
        case .account: "account.title"
        case .capture: "settings.section.capture"
        case .editing: "settings.section.editing"
        case .intelligence: "settings.section.intelligence"
        case .device: "settings.section.device"
        }
    }
    var detail: String.LocalizationValue {
        switch self {
        case .account: "account.invite.detail"
        case .capture: "settings.capture.detail"
        case .editing: "settings.editing.detail"
        case .intelligence: "settings.intelligence.detail"
        case .device: "settings.device.detail"
        }
    }
    var icon: String {
        switch self {
        case .account: "person.crop.circle"
        case .capture: "camera.aperture"
        case .editing: "slider.horizontal.3"
        case .intelligence: "sparkles"
        case .device: "lock.shield"
        }
    }
}

struct SettingsPanel: View {
    let destination: SettingsDestination
    let model: SettingsModel
    let storage: String?
    let onCleanStorage: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var showsKeys = false
    @State private var showsConverter = false
    @State private var confirmsCleaning = false
    @State private var keyCount = APIKeySheet.connectedCount

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                SettingsSheetHeader(icon: destination.icon, title: settingsText(destination.title), detail: settingsText(destination.detail)) { dismiss() }
                VStack(spacing: 1) { controls }
                    .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                Label(settingsText("settings.autosave"), systemImage: "checkmark.circle")
                    .font(DS.sans(.regular, 12)).foregroundStyle(DS.Palette.ink(0.45))
                    .frame(maxWidth: .infinity)
            }.padding(22).padding(.top, 14).padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(DS.Palette.screen)
        .sheet(isPresented: $showsKeys, onDismiss: { keyCount = APIKeySheet.connectedCount }) {
            APIKeySheet { showsKeys = false }.presentationDragIndicator(.visible).presentationCornerRadius(32)
        }
        .sheet(isPresented: $showsConverter) {
            ConverterSheet { showsConverter = false }.presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(32)
        }
        .confirmationDialog(settingsText("settings.storage.confirm"), isPresented: $confirmsCleaning, titleVisibility: .visible) {
            Button(settingsText("settings.storage.clean")) { onCleanStorage?() }
            Button(settingsText("account.cancel"), role: .cancel) { }
        } message: { Text("settings.storage.safe", bundle: .module) }
    }

    @ViewBuilder private var controls: some View {
        switch destination {
        case .capture:
            option("settings.camera", icon: "camera.rotate", options: CameraPosition.allCases, selected: model.settings.defaultCamera, label: \.label) { model.update(\.defaultCamera, to: $0) }
            option("settings.quality", icon: "4k.tv", options: VideoFormat.Resolution.allCases, selected: model.settings.captureResolution, label: \.label) { model.update(\.captureResolution, to: $0) }
        case .editing:
            option("settings.captions", icon: "captions.bubble", options: CaptionPreference.allCases, selected: model.settings.captionPreset, label: \.label) { model.update(\.captionPreset, to: $0) }
            Toggle(isOn: Binding(get: { model.settings.remembersStyle }, set: { model.update(\.remembersStyle, to: $0) })) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("settings.rememberStyle", bundle: .module).font(DS.sans(.semibold, 16))
                    Text("settings.rememberStyle.detail", bundle: .module).font(DS.sans(.regular, 13)).foregroundStyle(DS.Palette.ink(0.55))
                }
            }.tint(DS.Palette.accent).foregroundStyle(DS.Palette.ink).padding(20)
            option("settings.export", icon: "square.and.arrow.up", options: ExportDestination.allCases, selected: model.settings.exportDestination, label: \.label) { model.update(\.exportDestination, to: $0) }
            Button { showsConverter = true } label: {
                SettingsRow(icon: "arrow.triangle.2.circlepath", title: settingsText("settings.converter"), detail: settingsText("settings.converter.value"))
            }.buttonStyle(SettingsPressStyle())
        case .intelligence:
            VStack(alignment: .leading, spacing: 14) {
                ForEach(AIProcessing.allCases, id: \.self) { choice in
                    Button { model.update(\.aiProcessing, to: choice) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: model.settings.aiProcessing == choice ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.settings.aiProcessing == choice ? DS.Palette.accent : DS.Palette.ink(0.3))
                                .font(.system(size: 22)).contentTransition(.symbolEffect(.replace))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(choice.label).font(DS.sans(.semibold, 16)).foregroundStyle(DS.Palette.ink)
                                Text(choice == .onDeviceOnly ? "settings.ai.local.detail" : "settings.ai.cloud.detail", bundle: .module)
                                    .font(DS.sans(.regular, 13)).foregroundStyle(DS.Palette.ink(0.6))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }.padding(16)
                            .background(model.settings.aiProcessing == choice ? DS.Palette.accent(0.08) : .clear, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(model.settings.aiProcessing == choice ? DS.Palette.accent(0.3) : DS.Palette.hairline(0.06)))
                    }.buttonStyle(SettingsPressStyle()).accessibilityAddTraits(model.settings.aiProcessing == choice ? .isSelected : [])
                }
            }.padding(12)
            Button { showsKeys = true } label: {
                SettingsRow(icon: "key.horizontal", title: settingsText("settings.apiKey"),
                            detail: keyCount == 0 ? settingsText("settings.apiKey.none") : String(localized: "settings.apiKey.connected \(keyCount)", bundle: .module))
            }.buttonStyle(SettingsPressStyle())
        case .device:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                SettingsRow(icon: "globe", title: settingsText("settings.language"),
                            detail: Locale.current.localizedString(forLanguageCode: Bundle.main.preferredLocalizations.first ?? "en"))
            }.buttonStyle(SettingsPressStyle())
            if onCleanStorage != nil {
                Button { confirmsCleaning = true } label: {
                    SettingsRow(icon: "internaldrive", title: settingsText("settings.storage"),
                                detail: storage ?? settingsText("settings.storage.measuring"))
                }.buttonStyle(SettingsPressStyle())
            }
            VStack(alignment: .leading, spacing: 12) {
                Label(settingsText("settings.privacy.title"), systemImage: "hand.raised")
                    .font(DS.sans(.semibold, 16)).foregroundStyle(DS.Palette.ink)
                Text("settings.privacy.detail", bundle: .module)
                    .font(DS.sans(.regular, 14)).foregroundStyle(DS.Palette.ink(0.65)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(20)
        case .account: EmptyView()
        }
    }

    private func option<Value: Hashable>(_ title: String.LocalizationValue, icon: String, options: [Value], selected: Value,
                                         label: KeyPath<Value, String>, change: @escaping (Value) -> Void) -> some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, value in
                Button { change(value) } label: {
                    if value == selected { Label(value[keyPath: label], systemImage: "checkmark") }
                    else { Text(value[keyPath: label]) }
                }
            }
        } label: { SettingsRow(icon: icon, title: settingsText(title), detail: selected[keyPath: label], chevron: "chevron.up.chevron.down") }
        .buttonStyle(SettingsPressStyle())
    }
}

func settingsText(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

struct SettingsRow: View {
    let icon: String
    let title: String
    var detail: String?
    var chevron = "chevron.right"
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 19, weight: .medium))
                .foregroundStyle(DS.Palette.accent).frame(width: 42, height: 46)
                .background(DS.Palette.accent(0.08), in: RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(DS.sans(.semibold, 16)).foregroundStyle(DS.Palette.ink)
                if let detail {
                    Text(detail).font(DS.sans(.regular, 13)).foregroundStyle(DS.Palette.ink(0.55))
                }
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: chevron).font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.Palette.ink(0.3)).accessibilityHidden(true)
        }.padding(16).frame(minHeight: 78).contentShape(Rectangle())
    }
}

struct SettingsSheetHeader: View {
    let icon: String
    let title: String
    let detail: String
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).font(.system(size: 24)).foregroundStyle(DS.Palette.accent).accessibilityHidden(true)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink).frame(width: 44, height: 44)
                        .background(DS.Palette.surfaceRaised, in: Circle())
                }.buttonStyle(SettingsPressStyle()).accessibilityLabel(Text("settings.close", bundle: .module))
            }
            Text(title).font(DS.archivo(.bold, 30)).tracking(-1).foregroundStyle(DS.Palette.ink).accessibilityAddTraits(.isHeader)
            Text(detail).font(DS.sans(.regular, 15)).foregroundStyle(DS.Palette.ink(0.6)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(reduceMotion ? .linear(duration: 0.1) : DS.Motion.snap, value: configuration.isPressed)
    }
}

extension View {
    func settingsEntrance(_ appeared: Bool, delay: Double, reduced: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduced ? 0 : 14)
            .animation(reduced ? .easeOut(duration: 0.12) : DS.Motion.settle.delay(delay), value: appeared)
    }
}
