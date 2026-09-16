import DesignSystem
import Domain
import GenerationEngine
import Persistence
import SwiftUI

/// The user's own keys for video models: one row per provider, each saved, checked and removed
/// on its own.
///
/// Keys stay in this iPhone's Keychain. Requests go from the phone straight to the provider, so
/// nothing here passes through our server.
struct APIKeySheet: View {
    let onClose: () -> Void

    static let keys = ProviderKeyStore()

    /// How many providers have a key, for the settings row.
    static var connectedCount: Int {
        GenerationProviderID.allCases.filter { keys.hasKey(for: $0) }.count
    }

    @State private var expanded: GenerationProviderID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("settings.apiKey", bundle: .module)
                        .dsFont(.archivo, .bold, 22)
                        .foregroundStyle(DS.Palette.ink)
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DS.Palette.ink)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(DS.Palette.hairline(0.1)))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPressIcon)
                    .accessibilityLabel(Text("settings.apiKey.close", bundle: .module))
                }

                Text("settings.apiKey.note", bundle: .module)
                    .dsFont(.sans, .regular, 13, lineHeight: 1.45)
                    .foregroundStyle(DS.Palette.ink(0.55))

                VStack(spacing: 10) {
                    ForEach(GenerationProviderID.allCases) { provider in
                        ProviderKeyRow(
                            provider: provider,
                            isExpanded: expanded == provider,
                            onToggle: {
                                withAnimation(DS.Motion.settle) {
                                    expanded = expanded == provider ? nil : provider
                                }
                            }
                        )
                    }
                }
            }
            .padding(22)
        }
        .scrollIndicators(.hidden)
        .background(DS.Palette.screen)
    }
}

private struct ProviderKeyRow: View {
    let provider: GenerationProviderID
    let isExpanded: Bool
    let onToggle: () -> Void

    private enum Check: Equatable {
        case idle, checking, valid, invalid, unknown
    }

    @State private var draft = ""
    @State private var suffix: String?
    @State private var check: Check = .idle
    @State private var savePulse = 0
    @FocusState private var focused: Bool

    private var models: String {
        let names = VideoModelPreset.catalog.filter { $0.provider == provider && !$0.isCustom }.map(\.title)
        let own = names.joined(separator: " · ")
        if provider.acceptsAnyModel {
            let any = String(localized: "settings.apiKey.anyModel", bundle: .module)
            return own.isEmpty ? any : "\(own) · \(any)"
        }
        return own
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: savePulse)
                        .symbolEffect(.pulse, options: .repeating, isActive: check == .checking)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(DS.Palette.hairline(0.07)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: provider.displayName)
                            .dsFont(.sans, .semibold, 14)
                            .foregroundStyle(DS.Palette.ink)
                        Text(verbatim: models)
                            .dsFont(.sans, .regular, 11)
                            .foregroundStyle(DS.Palette.ink(0.5))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    statusChip
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Palette.ink(0.35))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress(radius: 16))

            if isExpanded {
                editor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .dsCard(radius: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: 1.2)
                .animation(DS.Motion.snap, value: check)
        }
        .keyframeAnimator(initialValue: 0.0, trigger: refusals) { content, offset in
            content.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(-8, duration: 0.07)
                SpringKeyframe(7, duration: 0.07)
                SpringKeyframe(-4, duration: 0.07)
                SpringKeyframe(0, duration: 0.14)
            }
        }
        .sensoryFeedback(.success, trigger: check) { _, new in new == .valid }
        .sensoryFeedback(.error, trigger: check) { _, new in new == .invalid }
        .animation(DS.Motion.settle, value: check)
        .onAppear { suffix = APIKeySheet.keys.suffix(for: provider) }
    }

    @State private var refusals = 0

    private var icon: String {
        switch check {
        case .valid: "checkmark.seal.fill"
        case .invalid: "key.slash"
        default: suffix == nil ? "key" : "key.fill"
        }
    }

    private var iconColor: Color {
        switch check {
        case .invalid: DS.Palette.accentWarm
        case .valid: DS.Palette.lime
        default: suffix == nil ? DS.Palette.ink(0.5) : DS.Palette.lime
        }
    }

    private var borderColor: Color {
        switch check {
        case .valid: DS.Palette.lime.opacity(0.55)
        case .invalid: DS.Palette.accentWarm.opacity(0.7)
        case .checking: DS.Palette.ink(0.25)
        default: .clear
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        if let suffix {
            Text(verbatim: "••\(suffix)")
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(check == .invalid ? DS.Palette.accentWarm : DS.Palette.lime)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(DS.Palette.hairline(0.08)))
        } else {
            Text("settings.apiKey.none", bundle: .module)
                .dsFont(.sans, .medium, 11)
                .foregroundStyle(DS.Palette.ink(0.4))
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SecureField(
                    suffix == nil
                        ? provider.keyHint
                        : String(localized: "settings.apiKey.replace", bundle: .module),
                    text: $draft
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(save)
                .dsFont(.mono, .medium, 13)
                .foregroundStyle(DS.Palette.ink)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.hairline(0.07)))

                Button(action: save) {
                    Text("settings.apiKey.save", bundle: .module)
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Capsule().fill(DS.Palette.lime))
                }
                .buttonStyle(.dsPress(radius: 22))
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
            }

            checkLine

            HStack(spacing: 8) {
                Link(destination: provider.keyPage) {
                    Label(String(localized: "settings.apiKey.getKey", bundle: .module), systemImage: "arrow.up.right.square")
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.ink(0.8))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(Capsule().fill(DS.Palette.hairline(0.08)))
                }
                if suffix != nil {
                    Button {
                        Task { await verify() }
                    } label: {
                        Label(String(localized: "settings.apiKey.test", bundle: .module), systemImage: "checkmark.shield")
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(DS.Palette.ink(0.8))
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(Capsule().fill(DS.Palette.hairline(0.08)))
                    }
                    .buttonStyle(.dsPress(radius: 18))
                    .disabled(check == .checking)

                    Spacer(minLength: 0)

                    Button {
                        APIKeySheet.keys.remove(for: provider)
                        withAnimation(DS.Motion.settle) {
                            suffix = nil
                            check = .idle
                        }
                    } label: {
                        Text("settings.apiKey.remove", bundle: .module)
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(DS.Palette.accentWarm)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                    }
                    .buttonStyle(.dsPress(radius: 18))
                }
            }
        }
    }

    @ViewBuilder
    private var checkLine: some View {
        Group {
        switch check {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("settings.apiKey.checking", bundle: .module)
            }
            .dsFont(.sans, .medium, 11)
            .foregroundStyle(DS.Palette.ink(0.55))
        case .valid:
            Label(String(localized: "settings.apiKey.valid", bundle: .module), systemImage: "checkmark.seal.fill")
                .dsFont(.sans, .medium, 11)
                .foregroundStyle(DS.Palette.lime)
        case .invalid:
            Label(String(localized: "settings.apiKey.invalid", bundle: .module), systemImage: "xmark.octagon.fill")
                .dsFont(.sans, .medium, 11)
                .foregroundStyle(DS.Palette.accentWarm)
        case .unknown:
            Label(String(localized: "settings.apiKey.unverified", bundle: .module), systemImage: "questionmark.circle")
                .dsFont(.sans, .medium, 11)
                .foregroundStyle(DS.Palette.ink(0.55))
        }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .id(check)
    }

    private func save() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, APIKeySheet.keys.save(value, for: provider) else { return }
        draft = ""
        focused = false
        withAnimation(DS.Motion.bloom) {
            suffix = APIKeySheet.keys.suffix(for: provider)
            savePulse += 1
        }
        Task { await verify() }
    }

    private func verify() async {
        guard let key = APIKeySheet.keys.key(for: provider) else { return }
        withAnimation(DS.Motion.snap) { check = .checking }
        let result = await VideoGenerationService().verify(key, for: provider)
        withAnimation(DS.Motion.snap) {
            check = switch result {
            case true?: .valid
            case false?: .invalid
            case nil: .unknown
            }
        }
        if result == false { refusals += 1 }
    }
}
