import DesignSystem
import Domain
import SwiftUI

/// Asks a model which runs of sentences make good shorts. Throws a sentence people can read.
public typealias HighlightRequester = @MainActor @Sendable ([SpokenSentence], String, HighlightLength, Int) async throws -> [HighlightPick]

/// The shorts found in this video.
public struct ShortsState: Equatable {
    public enum Phase: Equatable {
        case idle
        case finding
        case ready
        /// Nothing has been transcribed, so there are no sentences to choose from.
        case noSpeech
    }

    public var phase: Phase = .idle
    public var candidates: [HighlightCandidate] = []
    /// Why the model was not asked, or what it said when it failed. The device's picks still show.
    public var note: String?
    public var instruction = ""
    public var lengthIndex = 1
    /// Candidates already made into projects.
    public var created: Set<String> = []

    public var length: HighlightLength {
        HighlightLength.all[min(max(lengthIndex, 0), HighlightLength.all.count - 1)]
    }
}

// MARK: - Model

extension EditorModel {
    static let shortsCount = 6

    /// Finds shorts: the device scores every run of sentences, and a model — when allowed — picks
    /// its own, which are scored the same way and listed first.
    public func findShorts() {
        shortsTask?.cancel()
        let sentences = project.spokenSentences
        guard !sentences.isEmpty else {
            shorts.phase = .noSpeech
            shorts.candidates = []
            return
        }
        let length = shorts.length
        let locale = project.locale
        let instruction = shorts.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let local = HighlightFinder.candidates(in: sentences, length: length, count: Self.shortsCount, locale: locale)
        shorts.note = nil
        guard let highlightRequester else {
            shorts.candidates = local
            shorts.phase = .ready
            return
        }
        shorts.phase = .finding
        shortsTask = Task { [weak self] in
            var picks: [HighlightPick] = []
            var note: String?
            do {
                picks = try await highlightRequester(sentences, instruction, length, Self.shortsCount)
            } catch {
                note = error.localizedDescription
            }
            guard !Task.isCancelled, let self else { return }
            withAnimation(DS.Motion.settle) {
                self.shorts.candidates = HighlightFinder.merge(
                    picks: picks,
                    local: local,
                    sentences: sentences,
                    length: length,
                    count: Self.shortsCount,
                    locale: locale
                )
                self.shorts.note = note
                self.shorts.phase = .ready
            }
        }
    }

    /// Plays a candidate and stops at its end.
    public func previewShort(_ candidate: HighlightCandidate) {
        pause()
        seek(to: candidate.start)
        togglePlayback()
        shortPreviewTask?.cancel()
        let end = candidate.end
        shortPreviewTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.isPlaying else { return }
                if self.playhead >= end {
                    self.pause()
                    return
                }
            }
        }
    }

    /// Makes a candidate into its own vertical project and hands it to the app to open.
    public func createShort(_ candidate: HighlightCandidate) {
        pause()
        let clip = project.extractingClip(from: candidate.start, to: candidate.end, title: candidate.title)
        guard !clip.segments.isEmpty else { return }
        shorts.created.insert(candidate.id)
        onCreateShort?(clip)
    }

    /// Follows the speaker's face in every clip: what a short cut from wide footage needs.
    public func followFacesInAllClips(mediaDirectory: URL? = nil) async {
        if let mediaDirectory { self.mediaDirectory = mediaDirectory }
        let clips = aiTrackClips(nil)
        guard !clips.isEmpty else { return }
        let found = await aiFindFaces(in: clips, closeness: 0.12)
        guard !found.isEmpty else { return }
        record("editor.change.follow", symbol: "person.crop.rectangle")
        _ = aiApplyFaceTracks(found)
        project.updatedAt = .now
    }
}

// MARK: - Panel

struct ShortsPanel: View {
    @Bindable var model: EditorModel
    /// The sheet says this in its own header.
    var showsHint = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHint {
                Text("editor.shorts.hint", bundle: .module)
                    .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.ink(0.58))
            }

            TextField(
                String(localized: "editor.shorts.placeholder", bundle: .module),
                text: $model.shorts.instruction
            )
            .dsFont(.sans, .regular, 13)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.hairline(0.07)))
            .submitLabel(.search)
            .onSubmit { model.findShorts() }

            HStack(spacing: 6) {
                ForEach(HighlightLength.all.indices, id: \.self) { index in
                    let length = HighlightLength.all[index]
                    let isOn = model.shorts.lengthIndex == index
                    Button {
                        model.shorts.lengthIndex = index
                    } label: {
                        Text("editor.shorts.length \(Int(length.minimum)) \(Int(length.maximum))", bundle: .module)
                            .dsFont(.mono, .medium, 11)
                            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.75))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(isOn ? DS.Palette.accent : DS.Palette.hairline(0.07)))
                    }
                    .buttonStyle(.dsPress(radius: 17))
                }
                Spacer(minLength: 0)
                Button {
                    model.findShorts()
                } label: {
                    HStack(spacing: 6) {
                        if model.shorts.phase == .finding {
                            ProgressView().controlSize(.mini).tint(DS.Palette.inkInverse)
                        } else {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(verbatim: model.shorts.candidates.isEmpty
                            ? String(localized: "editor.shorts.find", bundle: .module)
                            : String(localized: "editor.shorts.again", bundle: .module))
                            .dsFont(.sans, .semibold, 13)
                    }
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .background(Capsule().fill(DS.Palette.lime))
                }
                .buttonStyle(.dsPress(radius: 20))
                .disabled(model.shorts.phase == .finding)
            }

            switch model.shorts.phase {
            case .idle:
                EmptyView()
            case .finding:
                Text("editor.shorts.finding", bundle: .module)
                    .dsFont(.sans, .medium, 12)
                    .foregroundStyle(DS.Palette.ink(0.6))
            case .noSpeech:
                Label {
                    Text("editor.shorts.noSpeech", bundle: .module)
                } icon: {
                    Image(systemName: "waveform.slash")
                }
                .dsFont(.sans, .medium, 12)
                .foregroundStyle(DS.Palette.accent)
            case .ready:
                results
            }
        }
        .animation(DS.Motion.settle, value: model.shorts.phase)
    }

    @ViewBuilder
    private var results: some View {
        if let note = model.shorts.note {
            Label {
                Text("editor.shorts.deviceOnly \(note)", bundle: .module)
            } icon: {
                Image(systemName: "iphone")
            }
            .dsFont(.sans, .regular, 11)
            .foregroundStyle(DS.Palette.ink(0.55))
        }
        if model.shorts.candidates.isEmpty {
            Text("editor.shorts.none", bundle: .module)
                .dsFont(.sans, .medium, 12)
                .foregroundStyle(DS.Palette.ink(0.6))
        }
        ForEach(model.shorts.candidates) { candidate in
            ShortCard(
                candidate: candidate,
                created: model.shorts.created.contains(candidate.id),
                onPreview: { model.previewShort(candidate) },
                onCreate: { model.createShort(candidate) }
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

private struct ShortCard: View {
    let candidate: HighlightCandidate
    let created: Bool
    let onPreview: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if candidate.pickedByAI {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.Palette.lime)
                                .accessibilityLabel(Text("editor.shorts.byAI", bundle: .module))
                        }
                        Text("editor.shorts.range \(Self.clock(candidate.start)) \(Self.clock(candidate.end)) \(Int(candidate.duration.rounded()))", bundle: .module)
                            .dsFont(.mono, .medium, 10)
                            .foregroundStyle(DS.Palette.ink(0.5))
                    }
                    Text(verbatim: candidate.title)
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(2)
                    if let reason = candidate.reason, !reason.isEmpty {
                        Text(verbatim: reason)
                            .dsFont(.sans, .regular, 11)
                            .foregroundStyle(DS.Palette.ink(0.6))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Text(verbatim: "\(candidate.score)")
                    .dsFont(.mono, .medium, 15)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(candidate.score >= 70 ? DS.Palette.lime : DS.Palette.ink(0.6)))
                    .accessibilityLabel(Text("editor.shorts.score \(candidate.score)", bundle: .module))
            }

            HStack(spacing: 8) {
                bar("editor.shorts.hook", candidate.scores.hook)
                bar("editor.shorts.complete", candidate.scores.complete)
                bar("editor.shorts.pace", candidate.scores.pace)
                bar("editor.shorts.keywords", candidate.scores.keywords)
            }

            HStack(spacing: 8) {
                Button(action: onPreview) {
                    Label(String(localized: "editor.shorts.preview", bundle: .module), systemImage: "play.fill")
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .background(Capsule().fill(DS.Palette.hairline(0.1)))
                }
                .buttonStyle(.dsPress(radius: 20))
                Button(action: onCreate) {
                    Label(
                        created
                            ? String(localized: "editor.shorts.createAgain", bundle: .module)
                            : String(localized: "editor.shorts.create", bundle: .module),
                        systemImage: created ? "checkmark" : "rectangle.portrait.badge.plus"
                    )
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .background(Capsule().fill(DS.Palette.ink))
                }
                .buttonStyle(.dsPress(radius: 20))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.Palette.hairline(0.06)))
    }

    private func bar(_ key: String.LocalizationValue, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { box in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Palette.hairline(0.1))
                    Capsule()
                        .fill(value >= 0.7 ? DS.Palette.lime : DS.Palette.accent(0.8))
                        .frame(width: max(4, box.size.width * value))
                }
            }
            .frame(height: 5)
            Text(String(localized: key, bundle: .module))
                .dsFont(.sans, .medium, 9)
                .foregroundStyle(DS.Palette.ink(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: "\(Int((value * 100).rounded()))%"))
    }

    static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// The shorts panel as a sheet: it rides above the keyboard while the instruction is typed, which
/// a panel inside the editor cannot do — the editor ignores the keyboard so the picture never jumps.
struct ShortsSheet: View {
    @Bindable var model: EditorModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    DSKicker(String(localized: "editor.dock.shorts", bundle: .module))
                    Text("editor.shorts.hint", bundle: .module)
                        .dsFont(.sans, .regular, 11, lineHeight: 1.3)
                        .foregroundStyle(DS.Palette.ink(0.45))
                        .lineLimit(2)
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
                .accessibilityLabel(Text("editor.panel.close", bundle: .module))
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 12)

            ScrollView {
                ShortsPanel(model: model, showsHint: false)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(DS.Palette.screen)
    }
}
