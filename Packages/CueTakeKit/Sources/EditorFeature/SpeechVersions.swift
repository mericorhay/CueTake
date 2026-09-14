import DesignSystem
import Domain
import SwiftUI

/// The two listeners' versions of what was said, where a caption is being edited.
extension EditorModel {
    /// The passage a caption was read from, with the recording it belongs to.
    public func speechPassage(forCaption id: CaptionCue.ID) -> (recording: Recording.ID, passage: TranscriptPassage)? {
        guard let index = segmentIndex(ofCaption: id),
              let cue = project.segments[index].captions.first(where: { $0.id == id }),
              let take = project.segments[index].selectedTake,
              let versions = project.recording(id: take.recordingID)?.speech,
              versions.hasCloud
        else { return nil }
        let moment = take.sourceRange.start.seconds + cue.range.start.seconds + cue.range.duration.seconds / 2
        guard let passage = versions.passage(at: moment) else { return nil }
        return (take.recordingID, passage)
    }

    /// Uses one listener's words for a passage: every clip cut from that recording is read again.
    ///
    /// - Returns: the caption now at the same moment as `caption`, which the new words replaced.
    @discardableResult
    public func chooseSpeech(
        _ source: SpeechSource,
        passage: TranscriptPassage.ID,
        recording: Recording.ID,
        keeping caption: CaptionCue.ID? = nil
    ) -> CaptionCue.ID? {
        var anchor: (segment: Segment.ID, moment: Double)?
        if let caption, let index = segmentIndex(ofCaption: caption),
           let cue = project.segments[index].captions.first(where: { $0.id == caption }) {
            anchor = (project.segments[index].id, cue.range.start.seconds + cue.range.duration.seconds / 2)
        }
        record("editor.change.speechVersion", symbol: "waveform")
        project.choose(source, forPassage: passage, inRecording: recording, by: .user)
        guard let anchor, let segment = project.segment(id: anchor.segment) else { return nil }
        return segment.captions.min { a, b in
            distance(a, anchor.moment) < distance(b, anchor.moment)
        }?.id
    }

    private func distance(_ cue: CaptionCue, _ moment: Double) -> Double {
        if cue.range.start.seconds <= moment, moment <= cue.range.end.seconds { return 0 }
        return min(abs(cue.range.start.seconds - moment), abs(cue.range.end.seconds - moment))
    }
}

/// A quiet line under a caption: which listener its words came from, and — opened — both versions
/// side by side, either one a tap away.
struct SpeechVersionsRow: View {
    @Bindable var model: EditorModel
    let captionID: CaptionCue.ID
    /// Called with the caption that took the edited one's place.
    var onReplaced: (CaptionCue.ID) -> Void = { _ in }

    @State private var open = false

    var body: some View {
        if let found = model.speechPassage(forCaption: captionID) {
            let passage = found.passage
            let agrees = passage.agrees(locale: model.project.locale)
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(DS.Motion.snap) { open.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .semibold))
                        Text(Self.status(passage, agrees: agrees))
                            .dsFont(.sans, .medium, 11)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if !agrees {
                            Image(systemName: open ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .foregroundStyle(DS.Palette.ink(0.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(agrees)

                if open, !agrees {
                    HStack(alignment: .top, spacing: 8) {
                        card(.device, passage: passage, recording: found.recording)
                        card(.cloud, passage: passage, recording: found.recording)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func card(_ source: SpeechSource, passage: TranscriptPassage, recording: Recording.ID) -> some View {
        let isOn = passage.choice == source
        let text = passage.text(from: source)
        return Button {
            guard !isOn else { return }
            withAnimation(DS.Motion.settle) {
                if let replacement = model.chooseSpeech(source, passage: passage.id, recording: recording, keeping: captionID) {
                    onReplaced(replacement)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: source == .device ? "iphone" : "cloud")
                        .font(.system(size: 10, weight: .semibold))
                    Text(Self.name(source))
                        .dsFont(.mono, .medium, 9)
                    Spacer(minLength: 0)
                    if isOn {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.Palette.lime)
                    }
                }
                .foregroundStyle(DS.Palette.ink(0.55))
                Text(verbatim: text.isEmpty ? "—" : text)
                    .dsFont(.sans, .medium, 12)
                    .foregroundStyle(DS.Palette.ink(isOn ? 1 : 0.7))
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.hairline(isOn ? 0.1 : 0.05)))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isOn ? DS.Palette.lime(0.6) : DS.Palette.hairline(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.dsPress(radius: 12))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    static func name(_ source: SpeechSource) -> String {
        switch source {
        case .device: String(localized: "editor.speech.device", bundle: .module)
        case .cloud: String(localized: "editor.speech.cloud", bundle: .module)
        }
    }

    static func status(_ passage: TranscriptPassage, agrees: Bool) -> String {
        if agrees { return String(localized: "editor.speech.agree", bundle: .module) }
        let source = name(passage.choice)
        switch passage.decidedBy {
        case .ai: return String(localized: "editor.speech.byAI \(source)", bundle: .module)
        case .user: return String(localized: "editor.speech.byYou \(source)", bundle: .module)
        case .rule: return String(localized: "editor.speech.byRule \(source)", bundle: .module)
        }
    }
}
