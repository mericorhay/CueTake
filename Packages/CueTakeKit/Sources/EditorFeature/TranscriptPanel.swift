import DesignSystem
import Domain
import SwiftUI

/// Editing by reading.
///
/// The words of the take, laid out as text, each one carrying the moment it was said. Tap a word
/// to hear it. Tap two to select everything between them. Delete, and the footage goes with the
/// words — not approximately, but at the exact times the transcriber reported.
///
/// This is the thing the whole speech pipeline was built for. Everything else in the editor asks
/// someone to find a moment by looking at it; this asks them to find it by reading, which is how
/// people actually remember what is in their own footage. Nobody thinks "the bit at 00:14". They
/// think "the bit where I said the thing about the lens".
struct TranscriptPanel: View {
    @Bindable var model: EditorModel
    let index: Int
    /// Runs transcription for takes that have none. Owned by the app layer, which knows where the
    /// media is.
    let onTranscribe: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchor: Int?
    @State private var head: Int?

    private var words: [TimedWord] { model.spokenWords(at: index) }

    private var selection: ClosedRange<Int>? {
        guard let anchor, let head else { return nil }
        return min(anchor, head)...max(anchor, head)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if words.isEmpty {
                empty
            } else {
                actions
                text
            }
        }
        .background(DS.Palette.screen)
        .animation(reduceMotion ? nil : DS.Motion.snap, value: anchor)
        .animation(reduceMotion ? nil : DS.Motion.snap, value: head)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                DSKicker(String(localized: "editor.transcript.title", bundle: .module))
                Text(
                    String(
                        localized: "editor.transcript.count \(words.count)",
                        bundle: .module
                    )
                )
                .dsFont(.sans, .regular, 11)
                .foregroundStyle(DS.Palette.ink(0.35))
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Palette.ink(0.6))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Palette.hairline(0.08)))
            }
            .buttonStyle(.dsPressIcon)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    /// Before there is a transcript there is nothing to read, and the honest thing is to say what
    /// it costs: it runs on the phone, so it is a wait rather than a bill.
    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("editor.transcript.empty", bundle: .module)
                .dsFont(.sans, .regular, 13, lineHeight: 1.45)
                .foregroundStyle(DS.Palette.ink(0.5))

            Button {
                onTranscribe()
                onClose()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.and.person.filled")
                        .font(.system(size: 13, weight: .semibold))
                    Text("editor.transcript.run", bundle: .module)
                        .dsFont(.sans, .semibold, 14)
                }
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DS.Palette.accent)
                )
            }
            .buttonStyle(.dsPress(radius: 16))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var actions: some View {
        let gaps = model.silenceGaps(at: index)

        return HStack(spacing: 8) {
            action(
                selection == nil ? "editor.transcript.selectHint" : "editor.transcript.delete",
                symbol: "trash",
                enabled: selection != nil,
                isDestructive: true
            ) {
                guard let selection else { return }
                let start = words[selection.lowerBound].range.start.seconds
                let end = words[selection.upperBound].range.end.seconds
                model.pulse(.delete)
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DS.Motion.settle) {
                    model.removeSpoken(at: index, from: start, to: end)
                }
                anchor = nil
                head = nil
            }

            action(
                gaps.isEmpty
                    ? "editor.transcript.noPauses"
                    : "editor.transcript.tighten \(gaps.count)",
                symbol: "arrow.right.and.line.vertical.and.arrow.left",
                enabled: !gaps.isEmpty
            ) {
                model.pulse(.split)
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DS.Motion.settle) {
                    model.tightenSilences(at: index)
                }
                anchor = nil
                head = nil
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    /// The words themselves.
    ///
    /// Laid out as running text rather than a list of rows, because that is what it is: reading a
    /// list of one-word rows is not reading. The flow layout is the same one the script screen
    /// uses for its chips.
    private var text: some View {
        ScrollView {
            FlowLayout(horizontalSpacing: 4, verticalSpacing: 6) {
                ForEach(Array(words.enumerated()), id: \.offset) { position, word in
                    let isSelected = selection?.contains(position) ?? false
                    let isSpeaking = model.isPlaying && Self.isUnderPlayhead(word, model: model, index: index)

                    Button {
                        tap(position, word)
                    } label: {
                        Text(word.text)
                            .dsFont(.sans, .regular, 15, lineHeight: 1.3)
                            .foregroundStyle(
                                isSelected ? DS.Palette.inkInverse : DS.Palette.ink(0.88)
                            )
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        isSelected
                                            ? DS.Palette.accent
                                            : (isSpeaking ? DS.Palette.lime(0.22) : .clear)
                                    )
                            )
                    }
                    .buttonStyle(.dsPress(radius: 6))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    /// First tap sets the anchor and plays from there; second tap extends to it.
    ///
    /// Playing on the first tap is the part that makes this trustworthy — you hear what you are
    /// about to delete before you delete it, without any extra control to learn.
    private func tap(_ position: Int, _ word: TimedWord) {
        let start = model.start(at: index) + word.range.start.seconds
        model.seek(to: start)

        if anchor == nil || (anchor != nil && head != nil) {
            anchor = position
            head = position
        } else {
            head = position
        }
    }

    static func isUnderPlayhead(_ word: TimedWord, model: EditorModel, index: Int) -> Bool {
        let offset = model.playhead - model.start(at: index)
        return offset >= word.range.start.seconds && offset < word.range.end.seconds
    }

    private func action(
        _ key: String.LocalizationValue,
        symbol: String,
        enabled: Bool,
        isDestructive: Bool = false,
        run: @escaping () -> Void
    ) -> some View {
        Button(action: run) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                Text(String(localized: key, bundle: .module))
                    .dsFont(.sans, .medium, 12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(
                enabled
                    ? (isDestructive ? DS.Palette.accent : DS.Palette.ink(0.85))
                    : DS.Palette.ink(0.25)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Palette.hairline(enabled ? 0.07 : 0.03))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 14))
        .disabled(!enabled)
    }
}
