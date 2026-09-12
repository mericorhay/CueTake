import DesignSystem
import Domain
import SwiftUI

/// Full script, one card per segment. Tapping a card reveals the AI rewrite actions.
public struct ScriptScreen: View {
    @Binding private var project: Project
    @State private var openSegment: Segment.ID?

    private let onBack: () -> Void
    private let onOpenStudio: () -> Void

    public init(
        project: Binding<Project>,
        onBack: @escaping () -> Void,
        onOpenStudio: @escaping () -> Void
    ) {
        self._project = project
        self.onBack = onBack
        self.onOpenStudio = onOpenStudio
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 11) {
                    ForEach(Array(project.segments.enumerated()), id: \.element.id) { index, segment in
                        card(for: segment, at: index)
                            .dsEnter(.rise(duration: 0.5, delay: Double(index) * 0.06))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            DSPrimaryButton(
                String(localized: "script.studio", bundle: .module),
                verticalPadding: 18,
                fontSize: 16,
                action: onOpenStudio
            )
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(DS.Palette.screen)
        .dsEnter(.screen())
    }

    private var header: some View {
        HStack {
            DSCircleButton("←", action: onBack)
            Spacer(minLength: 0)
            DSKicker(String(localized: "script.kicker \(project.wordCount)", bundle: .module))
            Spacer(minLength: 0)
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 22)
        .padding(.top, 62)
        .padding(.bottom, 14)
    }

    private func card(for segment: Segment, at index: Int) -> some View {
        let isOpen = openSegment == segment.id
        let color = DS.Palette.segment(at: segment.role.paletteIndex)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(segment.role.displayLabel)
                    .dsFont(.mono, .medium, 11, letterSpacing: 0.14)
                    .foregroundStyle(DS.Palette.ink(0.55))

                Spacer(minLength: 0)

                Text("\(Int(segment.barWeight))s")
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.28))
            }

            Text(segment.script)
                .dsFont(.sans, .regular, 16, lineHeight: 1.5)
                .foregroundStyle(DS.Palette.ink)
                .multilineTextAlignment(.leading)
                .padding(.top, 10)

            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(DS.Palette.hairline(0.08))
                        .frame(height: 1)
                        .padding(.bottom, 13)

                    Text("script.rewriteAs", bundle: .module)
                        .dsFont(.mono, .medium, 9, letterSpacing: 0.14)
                        .foregroundStyle(DS.Palette.ink(0.3))
                        .padding(.bottom, 9)

                    FlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
                        ForEach(RewriteAction.allCases, id: \.self) { action in
                            rewriteButton(action, index: index)
                        }
                    }
                }
                .padding(.top, 14)
                .dsEnter(.rise(duration: 0.3))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(isOpen ? DS.Palette.surfaceActive : DS.Palette.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(isOpen ? color : DS.Palette.hairline(0.07), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(DS.Easing.ease(0.3)) {
                openSegment = isOpen ? nil : segment.id
            }
        }
    }

    private func rewriteButton(_ action: RewriteAction, index: Int) -> some View {
        Button {
            withAnimation(DS.Easing.ease(0.3)) {
                project.segments[index].script = action.apply(
                    to: project.segments[index].script,
                    locale: project.locale
                )
            }
        } label: {
            Text(String(localized: action.labelKey, bundle: .module))
                .dsFont(.sans, .medium, 12)
                .foregroundStyle(DS.Palette.lime)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .fill(DS.Palette.lime(0.1))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .stroke(DS.Palette.lime(0.28), lineWidth: 1)
                }
        }
        .buttonStyle(.dsPress)
    }
}

/// The rewrite chips. Until a real model is wired in, these apply the design's own
/// local transforms so the interaction behaves exactly as the prototype does.
public enum RewriteAction: String, CaseIterable, Sendable {
    case rewrite
    case shorter
    case longer
    case moreNatural
    case moreEnergetic

    var labelKey: String.LocalizationValue {
        switch self {
        case .rewrite: "script.action.rewrite"
        case .shorter: "script.action.shorter"
        case .longer: "script.action.longer"
        case .moreNatural: "script.action.moreNatural"
        case .moreEnergetic: "script.action.moreEnergetic"
        }
    }

    func apply(to text: String, locale: Locale) -> String {
        switch self {
        case .shorter:
            return firstSentence(of: text)
        case .longer:
            return text + " " + String(localized: "script.longer.addition", bundle: .module)
        case .moreNatural:
            return String(localized: "script.natural.prefix", bundle: .module) + " " + lowercasingFirst(text, locale)
        case .moreEnergetic:
            if text.hasSuffix(".") { return String(text.dropLast()) + "!" }
            if text.hasSuffix("?") { return text + "!" }
            return text
        case .rewrite:
            let sentences = splitSentences(text)
            if sentences.count > 1 {
                return sentences.reversed().joined(separator: " ")
            }
            return String(localized: "script.rewrite.prefix", bundle: .module) + " " + lowercasingFirst(text, locale)
        }
    }

    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "." || character == "!" || character == "?" {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { sentences.append(rest) }
        return sentences
    }

    private func firstSentence(of text: String) -> String {
        splitSentences(text).first ?? text
    }

    /// Locale-aware: Turkish "İ" lowercases to "i", not "i̇".
    private func lowercasingFirst(_ text: String, _ locale: Locale) -> String {
        guard let first = text.first else { return text }
        return String(first).lowercased(with: locale) + text.dropFirst()
    }
}
