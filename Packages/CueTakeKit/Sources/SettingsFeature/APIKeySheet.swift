import DesignSystem
import Persistence
import SwiftUI

/// Where an API key can be entered and kept.
///
/// Stored in the Keychain on this phone only. Nothing reads it yet — this is the place for it,
/// ready for when a feature does.
struct APIKeySheet: View {
    let onClose: () -> Void

    @State private var draft = ""
    @State private var stored = false
    @State private var justSaved = false
    @FocusState private var focused: Bool

    static let store = KeychainStore(account: "api-key")

    var body: some View {
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
                }
                .buttonStyle(.dsPressIcon)
            }

            Text("settings.apiKey.note", bundle: .module)
                .dsFont(.sans, .regular, 13, lineHeight: 1.45)
                .foregroundStyle(DS.Palette.ink(0.55))

            HStack(spacing: 10) {
                Image(systemName: stored ? "key.fill" : "key")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(stored ? DS.Palette.lime : DS.Palette.ink(0.5))
                    .symbolEffect(.bounce, value: justSaved)

                SecureField(
                    String(localized: stored ? "settings.apiKey.replace" : "settings.apiKey.placeholder", bundle: .module),
                    text: $draft
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .dsFont(.mono, .medium, 14)
                .foregroundStyle(DS.Palette.ink)
            }
            .padding(14)
            .dsCard(radius: 16)

            HStack(spacing: 10) {
                if stored {
                    DSSecondaryButton(String(localized: "settings.apiKey.remove", bundle: .module), verticalPadding: 14, fontSize: 14) {
                        Self.store.delete()
                        withAnimation(DS.Motion.settle) { stored = false }
                    }
                }
                DSPrimaryButton(String(localized: "settings.apiKey.save", bundle: .module), verticalPadding: 14, fontSize: 14, glow: false) {
                    let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, Self.store.save(value) else { return }
                    draft = ""
                    focused = false
                    withAnimation(DS.Motion.bloom) {
                        stored = true
                        justSaved.toggle()
                    }
                }
                .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }

            if stored {
                Label {
                    Text("settings.apiKey.stored", bundle: .module)
                        .dsFont(.sans, .medium, 12)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                }
                .foregroundStyle(DS.Palette.lime)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(DS.Palette.screen)
        .onAppear { stored = Self.store.read() != nil }
    }
}
