import DesignSystem
import Domain
import SwiftUI

/// What is being typed into, from the editor.
enum TextEntryTarget: Hashable {
    case caption(CaptionCue.ID)
    case overlay(Overlay.ID)
}

/// Typing, just above the keyboard.
///
/// A text field inside a panel under the timeline sat exactly where the keyboard comes up, so the
/// words being typed disappeared behind it. The field the user types into now rides on top of
/// the keyboard, with the picture above still showing the change.
struct TextEntryBar: View {
    let title: String
    @Binding var text: String
    let onDone: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: title)
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.ink(0.6))
                Spacer(minLength: 0)
                Button(action: onDone) {
                    Text("editor.done", bundle: .module)
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(DS.Palette.lime))
                }
                .buttonStyle(.dsPress(radius: 20))
            }
            TextField("", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(onDone)
                .dsFont(.sans, .semibold, 16)
                .foregroundStyle(DS.Palette.ink)
                .tint(DS.Palette.lime)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.hairline(0.08)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet, topTrailingRadius: DS.Radius.sheet, style: .continuous)
                .fill(DS.Palette.glassSheet(0.98))
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Palette.hairline(0.1)).frame(height: 1)
        }
        .onAppear { focused = true }
        // The keyboard going away by itself — a swipe, the system — ends the typing too.
        .onChange(of: focused) { _, isFocused in
            if !isFocused { onDone() }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// A field that looks like where text goes, and opens the bar above the keyboard when tapped.
struct TextEntryField: View {
    let text: String
    let placeholder: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(verbatim: text.isEmpty ? placeholder : text)
                    .dsFont(.sans, .semibold, 15)
                    .foregroundStyle(text.isEmpty ? DS.Palette.ink(0.35) : DS.Palette.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "keyboard")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Palette.ink(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.hairline(0.07)))
        }
        .buttonStyle(.dsPress(radius: 12))
    }
}
