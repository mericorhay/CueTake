import AccountEngine
import DesignSystem
import Foundation
import Domain
import SwiftUI
import UIKit

public struct SettingsScreen: View {
    @Bindable private var model: SettingsModel
    private let account: AccountModel
    private let storage: String?
    private let onCleanStorage: (() async -> (message: String, storage: String?))?
    private let onTeam: (() -> Void)?
    private let onPreviewLight: (() -> Void)?
    private let certificates: String?
    private let onCertificates: (() -> Void)?
    private let voiceProfile: CreatorVoiceProfile?
    private let onVoiceProfile: (() -> Void)?
    /// TestFlight only: act as the free plan, to try the limits. Nil hides the row.
    private let testFreePlan: Binding<Bool>?
    /// Anonymous usage statistics, on unless turned off. Nil hides the row.
    private let shareAnalytics: Binding<Bool>?
    /// The plan and this month's use; nil hides the CueTake+ card.
    private let plus: PlusUsage?
    private let onUpgrade: (() -> Void)?
    private let onRestore: (() -> Void)?
    /// The iCloud backup section; nil hides it.
    private let cloudBackup: CloudBackupRow?
    private let onManageSubscription: (() -> Void)?
    private let onRedeemCode: (() -> Void)?
    /// How many suflör reports are kept, and the way to them; nil hides the row.
    private let suflorReports: String?
    private let onSuflorReports: (() -> Void)?
    /// Asked before 4K capture is chosen; false keeps the current quality.
    private let allowsHighResolution: (() -> Bool)?
    /// The qualities this phone's camera records; nil offers them all.
    private let captureResolutions: [VideoFormat.Resolution]?
    @State private var destination: SettingsDestination?
    /// The TestFlight plan switch, shown after five taps on the version: out of sight for anyone
    /// who is not testing, App Review included.
    @AppStorage("cuetake.tester") private var isTester = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: SettingsModel, account: AccountModel, storage: String? = nil,
                onCleanStorage: (() async -> (message: String, storage: String?))? = nil, onTeam: (() -> Void)? = nil,
                onPreviewLight: (() -> Void)? = nil, certificates: String? = nil,
                onCertificates: (() -> Void)? = nil, voiceProfile: CreatorVoiceProfile? = nil,
                onVoiceProfile: (() -> Void)? = nil, testFreePlan: Binding<Bool>? = nil,
                plus: PlusUsage? = nil, onUpgrade: (() -> Void)? = nil, onRestore: (() -> Void)? = nil,
                onManageSubscription: (() -> Void)? = nil,
                suflorReports: String? = nil, onSuflorReports: (() -> Void)? = nil,
                allowsHighResolution: (() -> Bool)? = nil, captureResolutions: [VideoFormat.Resolution]? = nil,
                cloudBackup: CloudBackupRow? = nil, shareAnalytics: Binding<Bool>? = nil,
                onRedeemCode: (() -> Void)? = nil) {
        self.onRedeemCode = onRedeemCode
        self.shareAnalytics = shareAnalytics
        self.cloudBackup = cloudBackup
        self.captureResolutions = captureResolutions
        self.suflorReports = suflorReports
        self.onSuflorReports = onSuflorReports
        self.allowsHighResolution = allowsHighResolution
        self.testFreePlan = testFreePlan
        self.plus = plus
        self.onUpgrade = onUpgrade
        self.onRestore = onRestore
        self.onManageSubscription = onManageSubscription
        self._model = Bindable(wrappedValue: model); self.account = account; self.storage = storage
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
                                Text(accountName)
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

                    if let plus {
                        PlusCard(usage: plus, onUpgrade: onUpgrade, onManage: onManageSubscription, onRestore: onRestore, onRedeem: onRedeemCode)
                            .settingsEntrance(appeared, delay: 0.06, reduced: reduceMotion)
                    }

                    if let cloudBackup {
                        CloudBackupCard(row: cloudBackup)
                            .settingsEntrance(appeared, delay: 0.07, reduced: reduceMotion)
                    }

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

                    if onVoiceProfile != nil || onCertificates != nil || onTeam != nil || onSuflorReports != nil {
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
                                if let onSuflorReports {
                                    Button(action: onSuflorReports) {
                                        SettingsRow(icon: "doc.text.magnifyingglass", title: settingsText("settings.suflorReports"), detail: suflorReports)
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

                    if let shareAnalytics {
                        AnalyticsToggle(isOn: shareAnalytics)
                    }

                    if let testFreePlan, isTester {
                        Toggle(isOn: testFreePlan) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("settings.testFreePlan", bundle: .module)
                                    .font(DS.sans(.semibold, 15)).foregroundStyle(DS.Palette.ink)
                                Text("settings.testFreePlan.detail", bundle: .module)
                                    .font(DS.sans(.regular, 12)).foregroundStyle(DS.Palette.ink(0.55))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(DS.Palette.accent)
                        .padding(18)
                        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                    }

                    VStack(spacing: 8) {
                        Text("CueTake").font(DS.archivo(.bold, 20)).tracking(-0.6)
                        Text(Self.version).font(DS.mono(11))
                            .onTapGesture(count: 5) { if testFreePlan != nil { withAnimation(DS.Motion.settle) { isTester.toggle() } } }
                            .onLongPressGesture(minimumDuration: 2) { onPreviewLight?() }
                        Text("settings.footer", bundle: .module).font(DS.sans(.regular, 12))
                        HStack(spacing: 16) {
                            Link(settingsText("settings.terms"), destination: URL(string: "https://mericorhay.github.io/CueTake/#terms")!)
                            Link(settingsText("settings.privacy"), destination: URL(string: "https://mericorhay.github.io/CueTake/#privacy")!)
                        }
                        .font(DS.sans(.medium, 12))
                        .tint(DS.Palette.accent)
                        .padding(.top, 4)
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
            if ProcessInfo.processInfo.arguments.contains("-capture-preview") { destination = .capture }
            if ProcessInfo.processInfo.arguments.contains("-editing-preview") { destination = .editing }
            if ProcessInfo.processInfo.arguments.contains("-intelligence-preview") { destination = .intelligence }
            if ProcessInfo.processInfo.arguments.contains("-privacy-preview") { destination = .device }
            if ProcessInfo.processInfo.arguments.contains("-language-preview") { destination = .device }
            #endif
        }
        .sheet(item: $destination) { selected in
            if selected == .account {
                AccountSheet(model: account)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(32)
            } else {
                SettingsPanel(destination: selected, model: model, storage: storage, onCleanStorage: onCleanStorage, allowsHighResolution: allowsHighResolution, captureResolutions: captureResolutions)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(32)
            }
        }
    }

    private var accountName: String {
        if let name = account.account?.name, !name.isEmpty { return name }
        return settingsText(account.account == nil ? "account.invite" : "account.title")
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
    let onCleanStorage: (() async -> (message: String, storage: String?))?
    var allowsHighResolution: (() -> Bool)? = nil
    var captureResolutions: [VideoFormat.Resolution]? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsKeys = false
    @State private var showsConverter = false
    @State private var showsLanguage = false
    @State private var showsMemory = false
    @State private var memoryCount = AIMemory.facts.count
    @State private var confirmsCleaning = false
    @State private var keyCount = APIKeySheet.connectedCount
    @State private var isCleaning = false
    @State private var cleaningResult: String?
    @State private var displayedStorage: String?

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
        .onAppear {
            displayedStorage = storage
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-language-preview") {
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    showsLanguage = true
                }
            }
            #endif
        }
        .onChange(of: storage) { _, value in displayedStorage = value }
        .sheet(isPresented: $showsKeys, onDismiss: { keyCount = APIKeySheet.connectedCount }) {
            APIKeySheet { showsKeys = false }.presentationDragIndicator(.visible).presentationCornerRadius(32)
        }
        .sheet(isPresented: $showsConverter) {
            ConverterSheet { showsConverter = false }.presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(32)
        }
        .sheet(isPresented: $showsMemory, onDismiss: { memoryCount = AIMemory.facts.count }) {
            AIMemorySheet { showsMemory = false }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .sheet(isPresented: $showsLanguage) {
            LanguageSheet(model: model) { showsLanguage = false }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .confirmationDialog(settingsText("settings.storage.confirm"), isPresented: $confirmsCleaning, titleVisibility: .visible) {
            Button(settingsText("settings.storage.clean")) {
                Task {
                    isCleaning = true
                    cleaningResult = nil
                    if let result = await onCleanStorage?() {
                        withAnimation(reduceMotion ? nil : DS.Motion.snap) {
                            cleaningResult = result.message
                            displayedStorage = result.storage
                        }
                    }
                    isCleaning = false
                }
            }
            Button(settingsText("account.cancel"), role: .cancel) { }
        } message: { Text("settings.storage.safe", bundle: .module) }
    }

    @ViewBuilder private var controls: some View {
        switch destination {
        case .capture:
            option("settings.camera", icon: "camera.rotate", options: CameraPosition.allCases, selected: model.settings.defaultCamera, label: \.label) { model.update(\.defaultCamera, to: $0) }
            option("settings.quality", icon: "4k.tv", options: captureResolutions ?? VideoFormat.Resolution.allCases, selected: model.settings.captureResolution, label: \.label) { value in
                if value == .uhd4K, !(allowsHighResolution?() ?? true) { return }
                model.update(\.captureResolution, to: value)
            }
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
                                .font(.system(size: 22)).contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
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
            }.padding(12).sensoryFeedback(.selection, trigger: model.settings.aiProcessing)
            Button { showsKeys = true } label: {
                SettingsRow(icon: "key.horizontal", title: settingsText("settings.apiKey"),
                            detail: keyCount == 0 ? settingsText("settings.apiKey.none") : AppLocalization.string("settings.apiKey.connected \(keyCount)", bundle: .module))
            }.buttonStyle(SettingsPressStyle())
            Button { showsMemory = true } label: {
                SettingsRow(icon: "brain.head.profile", title: settingsText("settings.aiMemory"),
                            detail: memoryCount == 0 ? settingsText("settings.aiMemory.none") : AppLocalization.string("settings.aiMemory.value \(memoryCount)", bundle: .module))
            }.buttonStyle(SettingsPressStyle())
        case .device:
            Button { showsLanguage = true } label: {
                SettingsRow(icon: "globe", title: settingsText("settings.language"),
                            detail: languageName(model.settings.language))
            }.buttonStyle(SettingsPressStyle())
            if onCleanStorage != nil {
                Button { confirmsCleaning = true } label: {
                    SettingsRow(icon: "internaldrive", title: settingsText("settings.storage"),
                                detail: displayedStorage ?? settingsText("settings.storage.measuring"))
                }.buttonStyle(SettingsPressStyle()).disabled(isCleaning)
                if isCleaning {
                    ProgressView().tint(DS.Palette.accent).frame(maxWidth: .infinity).padding(16)
                }
                if let cleaningResult {
                    Text(cleaningResult).font(DS.sans(.regular, 14)).foregroundStyle(DS.Palette.ink(0.65))
                        .padding(.horizontal, 20).padding(.bottom, 16)
                        .accessibilityAddTraits(.updatesFrequently)
                }
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
        .sensoryFeedback(.selection, trigger: selected)
    }
}

func settingsText(_ key: String.LocalizationValue) -> String { AppLocalization.string(key, bundle: .module) }

private func languageName(_ language: AppLanguage) -> String {
    switch language {
    case .automatic: settingsText("settings.language.automatic")
    case .english: "English"
    case .spanish: "Español"
    case .turkish: "Türkçe"
    }
}

private struct LanguageSheet: View {
    let model: SettingsModel
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSheetHeader(
                    icon: "globe",
                    title: settingsText("settings.language"),
                    detail: settingsText("settings.language.detail"),
                    close: close
                )

                VStack(spacing: 8) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        let selected = model.settings.language == language
                        Button {
                            withAnimation(reduceMotion ? nil : DS.Motion.snap) {
                                model.setLanguage(language)
                            }
                        } label: {
                            HStack(spacing: 15) {
                                Text(languageName(language))
                                    .font(DS.archivo(.semibold, 18))
                                    .foregroundStyle(DS.Palette.ink)
                                Spacer(minLength: 0)
                                Text(language.localeIdentifier?.uppercased() ?? settingsText("settings.language.device"))
                                    .font(DS.mono(10)).tracking(1.2)
                                    .foregroundStyle(selected ? DS.Palette.accent : DS.Palette.ink(0.42))
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(selected ? DS.Palette.accent : DS.Palette.ink(0.2))
                                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                            }
                            .padding(.horizontal, 18)
                            .frame(minHeight: 66)
                            .background(selected ? DS.Palette.accent(0.09) : DS.Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? DS.Palette.accent(0.32) : DS.Palette.hairline(0.06)))
                        }
                        .buttonStyle(SettingsPressStyle())
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .padding(22).padding(.top, 14).padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(DS.Palette.screen)
        .sensoryFeedback(.selection, trigger: model.settings.language)
    }
}

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

/// The anonymous statistics switch. Keeps its own state: the value lives outside anything SwiftUI
/// watches, so without it the switch would not move when tapped.
private struct AnalyticsToggle: View {
    let isOn: Binding<Bool>
    @State private var value: Bool

    init(isOn: Binding<Bool>) {
        self.isOn = isOn
        _value = State(initialValue: isOn.wrappedValue)
    }

    var body: some View {
        Toggle(isOn: $value) {
            VStack(alignment: .leading, spacing: 3) {
                Text("settings.analytics", bundle: .module)
                    .font(DS.sans(.semibold, 15)).foregroundStyle(DS.Palette.ink)
                Text("settings.analytics.detail", bundle: .module)
                    .font(DS.sans(.regular, 12)).foregroundStyle(DS.Palette.ink(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(DS.Palette.accent)
        .padding(18)
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 24))
        .onChange(of: value) { _, new in isOn.wrappedValue = new }
    }
}
