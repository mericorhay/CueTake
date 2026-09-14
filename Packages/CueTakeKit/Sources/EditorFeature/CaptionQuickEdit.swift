import DesignSystem
import Domain
import SwiftUI

/// Captions edited where they are seen: tap one on the picture, and its words, size, length, look
/// and place are right there — no trip to the captions screen for a typo.
extension EditorModel {
    /// The clip a caption belongs to.
    public func segmentIndex(ofCaption id: CaptionCue.ID) -> Int? {
        project.segments.firstIndex { $0.captions.contains { $0.id == id } }
    }

    /// Changes the caption look for the whole video, as one edit per gesture.
    ///
    /// Words per caption regroup every clip's captions from what was said; anything typed by hand
    /// is kept where it was.
    public func updateCaptionStyle(coalescing key: String = "caption-style", _ change: (inout CaptionStyle) -> Void) {
        record("editor.change.captionStyle", symbol: "captions.bubble", coalescing: key)
        let previousWords = project.captionStyle.maxWordsPerCue
        var style = project.captionStyle
        change(&style)
        style.relativeFontSize = min(max(style.relativeFontSize, 0.018), 0.075)
        style.maxWordsPerCue = min(max(style.maxWordsPerCue, 1), 8)
        style.position = CaptionPosition(x: style.position.x, y: min(max(style.position.y, 0.08), 0.92))
        project.captionStyle = style
        if previousWords != style.maxWordsPerCue {
            for index in project.segments.indices {
                project.segments[index].refreshCaptions(
                    maxWordsPerCue: style.maxWordsPerCue,
                    carrying: project.segments[index].captions
                )
            }
        }
        project.updatedAt = .now
    }

    public func removeCaption(_ id: CaptionCue.ID) {
        guard let index = segmentIndex(ofCaption: id) else { return }
        record("editor.change.caption", symbol: "text.bubble")
        project.segments[index].removeCaption(id)
        project.updatedAt = .now
    }
}

/// The panel under the picture while a caption is being edited.
struct CaptionQuickPanel: View {
    @Bindable var model: EditorModel
    let captionID: CaptionCue.ID
    let onClose: () -> Void
    let onOpenAll: () -> Void
    /// Moves the panel to another caption: the one that replaced this after a change of words.
    var onSwitch: (CaptionCue.ID) -> Void = { _ in }
    /// Opens typing above the keyboard.
    var onType: () -> Void = {}

    @FocusState private var typing: Bool

    private var index: Int? { model.segmentIndex(ofCaption: captionID) }

    private var cue: CaptionCue? {
        guard let index else { return nil }
        return model.project.segments[index].captions.first { $0.id == captionID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.lime)
                Text("editor.captionQuick.title", bundle: .module)
                    .dsFont(.sans, .semibold, 15)
                    .foregroundStyle(DS.Palette.ink)
                Text("editor.captionQuick.hint", bundle: .module)
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.ink(0.4))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Text("editor.done", bundle: .module)
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(DS.Palette.ink))
                }
                .buttonStyle(.dsPress(radius: 20))
            }

            if let index, let cue {
                TextEntryField(
                    text: cue.text,
                    placeholder: String(localized: "editor.captionQuick.placeholder", bundle: .module),
                    action: onType
                )

                SpeechVersionsRow(model: model, captionID: captionID, onReplaced: onSwitch)
            }

            HStack(spacing: 10) {
                stepper(
                    "editor.captionQuick.size",
                    value: "\(Int((model.project.captionStyle.relativeFontSize / 0.042 * 100).rounded()))%"
                ) { direction in
                    model.updateCaptionStyle(coalescing: "caption-size") { $0.relativeFontSize += 0.003 * direction }
                }
                stepper("editor.captionQuick.words", value: "\(model.project.captionStyle.maxWordsPerCue)") { direction in
                    model.updateCaptionStyle(coalescing: "caption-words") { $0.maxWordsPerCue += Int(direction) }
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(CaptionStyle.presetIDs, id: \.self) { preset in
                        let isOn = model.project.captionStyle.presetID == preset
                        Button {
                            withAnimation(DS.Motion.snap) {
                                model.updateCaptionStyle(coalescing: "caption-preset-\(preset)") { style in
                                    style = CaptionStyle.preset(preset, position: style.position)
                                }
                            }
                        } label: {
                            Text(CaptionsScreen.Style(rawValue: preset)?.label ?? preset)
                                .dsFont(.sans, .medium, 12)
                                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.85))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(isOn ? DS.Palette.lime : DS.Palette.hairline(0.08)))
                        }
                        .buttonStyle(.dsPress(radius: 20))
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

            HStack(spacing: 8) {
                Button {
                    let id = captionID
                    onClose()
                    withAnimation(DS.Motion.settle) { model.removeCaption(id) }
                } label: {
                    Label {
                        Text("editor.captionQuick.delete", bundle: .module)
                    } icon: {
                        Image(systemName: "trash")
                    }
                    .dsFont(.sans, .semibold, 13)
                    .foregroundStyle(DS.Palette.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(DS.Palette.accent(0.12)))
                }
                .buttonStyle(.dsPress(radius: 20))

                Spacer(minLength: 0)

                Button(action: onOpenAll) {
                    Label {
                        Text("editor.captionQuick.all", bundle: .module)
                    } icon: {
                        Image(systemName: "list.bullet")
                    }
                    .dsFont(.sans, .semibold, 13)
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(DS.Palette.hairline(0.1)))
                }
                .buttonStyle(.dsPress(radius: 20))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: DS.Radius.hero, topTrailingRadius: DS.Radius.hero, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: DS.Radius.hero, topTrailingRadius: DS.Radius.hero, style: .continuous)
                        .fill(DS.Palette.glassSheet(0.94))
                )
        }
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Palette.hairline(0.1)).frame(height: 1)
        }
        .dsEnter(.rise(duration: 0.34))
        // The caption regrouped under it (words per caption): nothing left to edit here.
        .onChange(of: cue == nil) { _, gone in
            if gone { onClose() }
        }
    }

    private func stepper(_ key: String.LocalizationValue, value: String, step: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 0) {
            Button { withAnimation(DS.Motion.snap) { step(-1) } } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 38, height: 38)
            }
            .buttonRepeatBehavior(.enabled)
            VStack(spacing: 1) {
                Text(String(localized: key, bundle: .module))
                    .dsFont(.mono, .medium, 9)
                    .foregroundStyle(DS.Palette.ink(0.45))
                Text(verbatim: value)
                    .dsFont(.mono, .medium, 13)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            Button { withAnimation(DS.Motion.snap) { step(1) } } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 38, height: 38)
            }
            .buttonRepeatBehavior(.enabled)
        }
        .foregroundStyle(DS.Palette.ink)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.hairline(0.07)))
        .buttonStyle(.dsPressIcon)
    }
}
