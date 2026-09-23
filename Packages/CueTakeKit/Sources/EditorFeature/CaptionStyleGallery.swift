import DesignSystem
import Domain
import SwiftUI

/// Names for caption looks, entrances, emphases and packs.
enum CaptionStyleCatalog {
    static func label(_ presetID: String) -> String {
        AppLocalization.string(String.LocalizationValue(stringLiteral: "captions.style." + presetID), bundle: .module)
    }

    static func label(_ entrance: CaptionEntrance) -> String {
        AppLocalization.string(String.LocalizationValue(stringLiteral: "captions.entrance." + entrance.rawValue), bundle: .module)
    }

    static func label(_ emphasis: CaptionEmphasis) -> String {
        AppLocalization.string(String.LocalizationValue(stringLiteral: "captions.emphasis." + emphasis.rawValue), bundle: .module)
    }

    static func label(pack: StylePack) -> String {
        AppLocalization.string(String.LocalizationValue(stringLiteral: "captions.pack." + pack.id), bundle: .module)
    }

    static func symbol(pack: StylePack) -> String {
        switch pack.id {
        case "viral": "flame.fill"
        case "energy": "bolt.fill"
        case "clean": "sparkles"
        case "talk": "mic.fill"
        case "story": "book.pages.fill"
        default: "film.fill"
        }
    }
}

/// A look shown as a tiny caption in its own face, colour, outline, plate and emphasis.
struct CaptionSwatch: View {
    let style: CaptionStyle
    var size: CGFloat = 15

    var body: some View {
        let font = style.fontName.map { Font.custom($0, fixedSize: size) } ?? .system(size: size, weight: .heavy)
        let words = style.textCase == .uppercase ? ["HEY", "YOU"] : (style.textCase == .lowercase ? ["hey", "you"] : ["Hey", "you"])
        HStack(spacing: size * 0.22) {
            word(words[0], font: font, lit: false)
            word(words[1], font: font, lit: true)
        }
        .padding(.horizontal, style.backgroundColor == nil ? 0 : size * 0.4)
        .padding(.vertical, style.backgroundColor == nil ? 0 : size * 0.15)
        .background {
            if let plate = style.backgroundColor {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(CaptionOverlay.color(plate))
            }
        }
    }

    @ViewBuilder
    private func word(_ text: String, font: Font, lit: Bool) -> some View {
        let emphasis = style.resolvedEmphasis
        let shows = lit && emphasis != .none
        let colour = shows ? (emphasis == .box ? style.boxedTextColor : style.emphasisColor) : style.textColor
        let weight = max(0.6, size * style.resolvedStrokeWeight * 0.4)
        let outline = CaptionOverlay.color(style.resolvedStrokeColor).opacity(style.resolvedStrokeWeight > 0.001 && !(shows && emphasis == .box) ? 0.95 : 0)
        Text(verbatim: text)
            .font(font)
            .foregroundStyle(CaptionOverlay.color(colour))
            .shadow(color: outline, radius: 0.3, x: weight, y: 0)
            .shadow(color: outline, radius: 0.3, x: -weight, y: 0)
            .shadow(color: outline, radius: 0.3, x: 0, y: weight)
            .shadow(color: outline, radius: 0.3, x: 0, y: -weight)
            .padding(.horizontal, shows && emphasis == .box ? size * 0.12 : 0)
            .background {
                if shows && emphasis == .box {
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .fill(CaptionOverlay.color(style.emphasisColor))
                }
            }
            .scaleEffect(shows && emphasis == .scale ? 1.15 : 1)
    }
}

/// One-tap packs: caption look, transitions and colour together.
struct StylePackRow: View {
    let selected: String?
    let onApply: (StylePack) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(StylePack.all) { pack in
                    let isOn = selected == pack.id
                    Button {
                        onApply(pack)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: CaptionStyleCatalog.symbol(pack: pack))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: CaptionStyleCatalog.label(pack: pack))
                                    .dsFont(.sans, .semibold, 12)
                                    .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink)
                                Text(verbatim: packDetail(pack))
                                    .dsFont(.sans, .regular, 10)
                                    .foregroundStyle(isOn ? DS.Palette.inkInverse.opacity(0.7) : DS.Palette.ink(0.45))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(
                            Capsule().fill(isOn ? DS.Palette.lime : DS.Palette.hairline(0.07))
                        )
                    }
                    .buttonStyle(.dsPress(radius: 22))
                    .accessibilityHint(Text(verbatim: packDetail(pack)))
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func packDetail(_ pack: StylePack) -> String {
        var parts = [CaptionStyleCatalog.label(pack.captionPreset)]
        if let transition = pack.transition {
            parts.append(AppLocalization.string(TransitionMarks.titleKey(transition), bundle: .module))
        }
        if let look = pack.look {
            parts.append(FilterPresets.label(look))
        }
        return parts.joined(separator: " · ")
    }
}

/// Entrance and emphasis choices, for the tuning panel.
struct CaptionMotionTuning: View {
    @Binding var look: CaptionStyle
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                DSKicker(AppLocalization.string("captions.tune.entrance", bundle: .module), size: 10, color: DS.Palette.ink(0.56))
                chips(CaptionEntrance.allCases, selected: look.resolvedEntrance, label: CaptionStyleCatalog.label) { value in
                    look.entrance = value
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                DSKicker(AppLocalization.string("captions.tune.emphasis", bundle: .module), size: 10, color: DS.Palette.ink(0.56))
                chips(CaptionEmphasis.allCases, selected: look.resolvedEmphasis, label: CaptionStyleCatalog.label) { value in
                    look.emphasis = value
                    if value != .none, look.highlightColor == nil {
                        look.highlightColor = look.emphasisColor
                    }
                }
            }
            Toggle(isOn: Binding(
                get: { look.keywordColor != nil },
                set: { on in
                    look.keywordColor = on ? (look.highlightColor ?? RGBAColor(red: 1, green: 0.84, blue: 0.04)) : nil
                    onCommit()
                }
            )) {
                Text("captions.tune.keywords", bundle: .module)
                    .dsFont(.sans, .medium, 12)
                    .foregroundStyle(DS.Palette.ink(0.85))
            }
            .tint(DS.Palette.accent)
            Toggle(isOn: Binding(
                get: { look.emoji == true },
                set: { on in
                    look.emoji = on
                    if on, look.keywordColor == nil { look.keywordColor = look.textColor }
                    onCommit()
                }
            )) {
                Text("captions.tune.emoji", bundle: .module)
                    .dsFont(.sans, .medium, 12)
                    .foregroundStyle(DS.Palette.ink(0.85))
            }
            .tint(DS.Palette.accent)
        }
    }

    private func chips<Value: Hashable>(
        _ values: [Value],
        selected: Value,
        label: @escaping (Value) -> String,
        choose: @escaping (Value) -> Void
    ) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(values, id: \.self) { value in
                    let isOn = value == selected
                    Button {
                        guard !isOn else { return }
                        withAnimation(DS.Motion.snap) { choose(value) }
                        onCommit()
                    } label: {
                        Text(verbatim: label(value))
                            .dsFont(.sans, .medium, 12)
                            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.75))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(isOn ? DS.Palette.accent : DS.Palette.hairline(0.07)))
                    }
                    .buttonStyle(.dsPress(radius: 17))
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}
