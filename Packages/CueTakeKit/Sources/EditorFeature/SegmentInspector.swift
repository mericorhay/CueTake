import DesignSystem
import Domain
import SwiftUI

/// The five tabs, filled in.
///
/// They were stand-ins: five labels over one card that said roughly the same thing five times.
/// What each tab is *for* was already decided by its name, so the job here was to make each one
/// actually do it — the script tab edits the script, the take tab switches takes, the timing tab
/// is where a clip's speed lives — rather than to invent five new ideas.
///
/// Everything writes through `EditorModel`, never into the array behind its back: one place stamps
/// the edit, and the app layer sees every change the same way whether it came from a tool, a
/// gesture or one of these fields.
struct SegmentInspector: View {
    @Bindable var model: EditorModel
    /// By identity, not position: a cut, an AI edit or an undo can remove or move the clip while
    /// this panel is on screen, and a stored position then reads past the end of the array.
    let segmentID: Segment.ID
    /// Opens the captions screen, where the look and every caption in the video are edited at once.
    var onOpenCaptions: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where the clip is now. Past the end when it is gone, so every model call guarding its index
    /// does nothing rather than editing whichever clip took its place.
    private var index: Int {
        model.project.segments.firstIndex { $0.id == segmentID } ?? Int.max
    }

    private var segment: Segment {
        model.project.segments.first { $0.id == segmentID } ?? Segment(id: segmentID, role: .mainPoint, script: "")
    }

    var body: some View {
        if model.project.segments.contains(where: { $0.id == segmentID }) {
            switch model.inspectorTab {
            case .script: script
            case .caption: captions
            case .timing: timing
            case .take: takes
            case .style: style
            }
        }
    }

    // MARK: - Script

    /// Editable, because the script is the one thing in this app that is never finished. It is
    /// also what the prompter reads and what the captions are built from, so a typo fixed here is
    /// a typo fixed in three places.
    private var script: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(
                text: Binding(
                    get: { segment.script },
                    set: { text in model.updateSegment(at: index) { $0.script = text } }
                )
            )
            .dsFont(.sans, .regular, 14, lineHeight: 1.45)
            .foregroundStyle(DS.Palette.ink)
            .scrollContentBackground(.hidden)
            // Fixed, because `TextEditor` is greedy vertically and a minimum does not hold it:
            // left alone it eats the panel and pushes the buttons off the bottom.
            .frame(height: 104)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Palette.hairline(0.05))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Palette.hairline(0.08), lineWidth: 1)
            }

            Text(
                String(
                    localized: "editor.info.words \(segment.wordCount) \(Int(segment.barWeight))",
                    bundle: .module
                )
            )
            .dsFont(.mono, .medium, 10)
            .foregroundStyle(DS.Palette.ink(0.35))
        }
    }

    // MARK: - Captions

    /// One row per cue, each with its own time. Tapping a row moves the playhead to it, which is
    /// the only way to check a caption: against the moment it is on screen.
    private var captions: some View {
        VStack(alignment: .leading, spacing: 6) {
            // This tab is one clip's captions. The look, and all captions in one list, live on the
            // captions screen — said here, so nobody styles a video clip by clip.
            Button(action: onOpenCaptions) {
                HStack(spacing: 8) {
                    Image(systemName: "captions.bubble.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("editor.caption.openAll", bundle: .module)
                        .dsFont(.sans, .semibold, 12)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(DS.Palette.inkInverse)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.lime))
            }
            .buttonStyle(.dsPress(radius: 12))
            .padding(.bottom, 4)

            if segment.captions.isEmpty {
                empty("editor.caption.empty", "editor.caption.hint", symbol: "text.bubble")
            } else {
                ForEach(segment.captions) { cue in
                    HStack(spacing: 9) {
                        Button {
                            model.seek(to: model.start(at: index) + cue.range.start.seconds)
                        } label: {
                            Text(MediaTime(seconds: cue.range.start.seconds).timecode)
                                .dsFont(.mono, .medium, 10)
                                .foregroundStyle(DS.Palette.lime)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(DS.Palette.lime(0.12))
                                )
                        }
                        .buttonStyle(.dsPress(radius: 8))

                        TextField(
                            "",
                            text: Binding(
                                get: { cue.text },
                                set: { text in
                                    model.updateCaption(cue.id, at: index) { $0.text = text }
                                }
                            )
                        )
                        .dsFont(.sans, .regular, 13)
                        .foregroundStyle(DS.Palette.ink)
                        .textFieldStyle(.plain)

                        if cue.isUserEdited {
                            Image(systemName: "pencil")
                                .font(.system(size: 9))
                                .foregroundStyle(DS.Palette.ink(0.3))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.Palette.hairline(0.05))
                    )
                }
            }
        }
    }

    // MARK: - Timing

    /// Where a clip's relationship with time lives: how long it is, how fast it runs, whether it
    /// runs backwards, and whether it runs at all.
    private var timing: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                field(
                    "editor.timing.position",
                    value: model.rangeLabel(at: index)
                ) {
                    model.seekToStart(of: index)
                }

                // Read here; changed by pulling the clip's ends on the timeline above.
                field(
                    segment.playback.freeze == nil ? "editor.timing.duration" : "editor.timing.held",
                    value: String(format: "%.2f s", segment.barWeight)
                ) {
                    model.seekToStart(of: index)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                label("editor.timing.speed")

                HStack(spacing: 5) {
                    ForEach(ClipPlayback.speedChoices, id: \.self) { value in
                        chip(
                            SegmentInspector.speedLabel(value),
                            isOn: abs(segment.playback.speed - value) < 0.001
                                && segment.playback.freeze == nil,
                            enabled: segment.playback.freeze == nil
                        ) {
                            model.pulse(.speed)
                            model.updatePlayback(at: index) { $0.speed = value }
                        }
                    }
                }
            }

            HStack(spacing: 9) {
                toggle(
                    "editor.timing.reverse",
                    symbol: "arrow.uturn.backward",
                    isOn: segment.playback.isReversed,
                    enabled: segment.playback.freeze == nil
                ) {
                    model.updatePlayback(at: index) { $0.isReversed.toggle() }
                }

                toggle(
                    "editor.timing.freeze",
                    symbol: "snowflake",
                    isOn: segment.playback.freeze != nil,
                    enabled: true
                ) {
                    // The frame under the playhead, held as a clip of its own.
                    model.toggleFreeze(at: index)
                }
            }

            if let note = SegmentInspector.note(for: segment.playback) {
                Text(String(localized: note, bundle: .module))
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.ink(0.4))
                    .transition(.opacity)
            }
        }
        .dsMotion(DS.Motion.snap, reduced: reduceMotion, value: segment.playback)
    }

    // MARK: - Takes

    /// Every attempt, oldest first, with the one in the video marked.
    ///
    /// Takes are never deleted by switching between them — that is the point of keeping them — so
    /// this is a list of choices rather than a history.
    private var takes: some View {
        VStack(alignment: .leading, spacing: 6) {
            if segment.takes.isEmpty {
                empty("editor.take.empty", "editor.take.hint", symbol: "video.badge.plus")
            } else {
                ForEach(Array(segment.takes.enumerated()), id: \.element.id) { number, take in
                    let isOn = segment.selectedTakeID == take.id

                    Button {
                        model.selectTake(take.id, at: index)
                    } label: {
                        HStack(spacing: 10) {
                            Text(verbatim: "\(number + 1)")
                                .dsFont(.mono, .medium, 11)
                                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.5))
                                .frame(width: 24, height: 24)
                                .background(
                                    Circle().fill(isOn ? DS.Palette.accent : DS.Palette.hairline(0.08))
                                )

                            VStack(alignment: .leading, spacing: 1) {
                                Text(take.sourceRange.duration.timecode)
                                    .dsFont(.mono, .medium, 12)
                                    .foregroundStyle(DS.Palette.ink)
                                Text(take.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .dsFont(.sans, .regular, 10)
                                    .foregroundStyle(DS.Palette.ink(0.35))
                            }

                            Spacer(minLength: 0)

                            Text(String(localized: SegmentInspector.statusLabel(take.status), bundle: .module))
                                .dsFont(.mono, .medium, 9)
                                .foregroundStyle(DS.Palette.ink(0.4))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(DS.Palette.hairline(isOn ? 0.09 : 0.04))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(isOn ? DS.Palette.accent(0.5) : .clear, lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.dsPress(radius: 13))
                }
            }
        }
    }

    // MARK: - Style

    /// What this beat *is*, and how the prompter should read it. Both are per-segment, which is
    /// why they are here rather than in settings: a hook is read faster than a call to action.
    private var style: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                label("editor.style.role")

                FlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                    ForEach(SegmentInspector.roles, id: \.self) { role in
                        chip(role.displayLabel, isOn: segment.role == role) {
                            model.updateSegment(at: index) { $0.role = role }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    label("editor.style.prompterSpeed")
                    Spacer(minLength: 0)
                    Text(String(format: "%.2f×", segment.teleprompter.speedMultiplier))
                        .dsFont(.mono, .medium, 11)
                        .foregroundStyle(DS.Palette.ink(0.7))
                        .contentTransition(.numericText())
                }

                Slider(
                    value: Binding(
                        get: { segment.teleprompter.speedMultiplier },
                        set: { value in
                            model.updateSegment(at: index) { $0.teleprompter.speedMultiplier = value }
                        }
                    ),
                    in: 0.5...2
                )
                .tint(DS.Palette.lime)
            }

            VStack(alignment: .leading, spacing: 6) {
                label("editor.style.notes")

                TextField(
                    String(localized: "editor.style.notesPlaceholder", bundle: .module),
                    text: Binding(
                        get: { segment.teleprompter.speakerNotes ?? "" },
                        set: { text in
                            model.updateSegment(at: index) {
                                // Empty means no note, not a note that is empty: the prompter draws
                                // a panel for one and an empty panel is worse than none.
                                $0.teleprompter.speakerNotes = text.isEmpty ? nil : text
                            }
                        }
                    ),
                    axis: .vertical
                )
                .dsFont(.sans, .regular, 13)
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(1...3)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(DS.Palette.hairline(0.05))
                )
            }
        }
    }

    // MARK: - Parts

    private func label(_ key: String.LocalizationValue) -> some View {
        Text(String(localized: key, bundle: .module))
            .dsFont(.mono, .medium, 9, letterSpacing: 0.12)
            .foregroundStyle(DS.Palette.ink(0.38))
    }

    private func empty(
        _ title: String.LocalizationValue,
        _ hint: String.LocalizationValue,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                Text(String(localized: title, bundle: .module))
                    .dsFont(.sans, .semibold, 13)
            }
            .foregroundStyle(DS.Palette.ink(0.7))

            Text(String(localized: hint, bundle: .module))
                .dsFont(.sans, .regular, 11, lineHeight: 1.4)
                .foregroundStyle(DS.Palette.ink(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Palette.hairline(0.04))
        )
    }

    private func field(
        _ key: String.LocalizationValue,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                label(key)
                Text(value)
                    .dsFont(.mono, .medium, 12)
                    .foregroundStyle(DS.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(DS.Palette.hairline(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 13))
    }

    private func stepper(
        _ key: String.LocalizationValue,
        value: Double,
        change: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                label(key)
                Text(String(format: "%.1fs", value))
                    .dsFont(.mono, .medium, 12)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            Button { change(-0.2) } label: { nudge("minus") }
                .buttonStyle(.dsPressIcon)
            Button { change(0.2) } label: { nudge("plus") }
                .buttonStyle(.dsPressIcon)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(DS.Palette.hairline(0.05))
        )
    }

    private func nudge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(DS.Palette.ink(0.8))
            .frame(width: 24, height: 24)
            .background(Circle().fill(DS.Palette.hairline(0.09)))
    }

    private func chip(
        _ text: String,
        isOn: Bool,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(text)
                .dsFont(.mono, .medium, 11)
                .foregroundStyle(
                    enabled
                        ? (isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.6))
                        : DS.Palette.ink(0.2)
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07))
                )
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 11))
        .disabled(!enabled)
    }

    private func toggle(
        _ key: String.LocalizationValue,
        symbol: String,
        isOn: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .symbolEffect(.bounce, value: isOn)
                Text(String(localized: key, bundle: .module))
                    .dsFont(.sans, .medium, 12)
            }
            .foregroundStyle(
                enabled
                    ? (isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.65))
                    : DS.Palette.ink(0.2)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 13))
        .disabled(!enabled)
    }

    // MARK: - Labels

    static let roles: [SegmentRole] = [.hook, .intro, .mainPoint, .example, .callToAction]

    static func speedLabel(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))×" : "\(value)×"
    }

    static func statusLabel(_ status: TakeStatus) -> String.LocalizationValue {
        switch status {
        case .recording: "editor.take.status.recording"
        case .processing: "editor.take.status.processing"
        case .ready: "editor.take.status.ready"
        case .failed: "editor.take.status.failed"
        }
    }

    /// What the current playback is going to do to this clip, said plainly.
    ///
    /// The reverse note in particular is not optional: a reversed clip comes back silent, and
    /// finding that out at export is finding it out too late.
    static func note(for playback: ClipPlayback) -> String.LocalizationValue? {
        if playback.freeze != nil { return "editor.timing.freezeNote" }
        if playback.isReversed { return "editor.timing.reverseNote" }
        if playback.speed < 1 { return "editor.timing.slowNote" }
        return nil
    }
}
