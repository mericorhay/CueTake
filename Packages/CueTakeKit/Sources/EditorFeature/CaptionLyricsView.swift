import AVFoundation
import DesignSystem
import Domain
import SwiftUI
import UIKit

/// Every caption of the video as a lyrics sheet: the line being said large and lit, the ones
/// around it dim and soft, the list following the voice. A translation sits under each line.
///
/// It is where captions are read, not only styled: tap a line to hear it, hold it to correct it,
/// in the spoken language or in any translation. The video itself plays behind, blurred, the way
/// a song's cover fills the screen behind its lyrics.
struct CaptionLyricsView: View {
    @Bindable var model: EditorModel
    let onClose: () -> Void

    /// The translation shown under each line; nil shows the spoken line alone.
    @State private var language: String?
    @State private var rows: [LyricRow] = []
    @State private var editing: LyricRow?
    @State private var choosingLanguage = false
    /// A finger on the list stops it following the voice for a moment, as Music does.
    @State private var heldUntil = Date.distantPast
    @State private var lastActive: CaptionCue.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct LyricRow: Identifiable, Equatable {
        let id: CaptionCue.ID
        let text: String
        let words: [PlacedWord]
        let start: Double
        let end: Double
        let translations: [String: String]
        let editedTranslations: [String]
    }

    private var activeIndex: Int? {
        let time = model.playhead
        return rows.lastIndex { $0.start <= time + 0.05 }
    }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                header
                languageBar
                    .padding(.top, 12)
                lyrics
                transport
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            rebuild()
            language = model.project.captionLanguage ?? model.project.translationLanguages.first
        }
        .onChange(of: model.project.segments) { rebuild() }
        .onChange(of: model.project.captionWindow) { rebuild() }
        .sheet(item: $editing) { row in
            LyricEditor(model: model, row: row, language: language) { editing = nil }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $choosingLanguage) {
            LanguagePicker(model: model, existing: model.project.translationLanguages) { code in
                choosingLanguage = false
                language = code
                Task { await model.translateCaptions(to: code) }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Pieces

    /// The video, huge and blurred, darkened so white text always reads.
    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.04)], startPoint: .top, endPoint: .bottom)
            if let player = model.player {
                LyricsPlayerLayer(player: player)
                    .scaleEffect(1.6)
                    .blur(radius: 60)
                    .opacity(0.75)
            }
            LinearGradient(
                colors: [.black.opacity(0.35), .black.opacity(0.15), .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white.opacity(0.14)))
            }
            .buttonStyle(.dsPressIcon)
            .accessibilityLabel(Text("editor.panel.close", bundle: .module))

            VStack(alignment: .leading, spacing: 1) {
                Text("lyrics.title", bundle: .module)
                    .dsFont(.sans, .bold, 16)
                    .foregroundStyle(.white)
                Text("lyrics.count \(rows.count)", bundle: .module)
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            onVideoPill
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    /// Which language the video itself shows, and a tap to show the one being read.
    private var onVideoPill: some View {
        let showing = model.project.captionLanguage
        let reading = language
        let matches = showing == reading || (showing == nil && reading == nil)
        return Button {
            withAnimation(DS.Motion.snap) { model.showCaptions(in: reading) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: matches ? "checkmark.circle.fill" : "rectangle.inset.bottomleft.filled")
                Text(matches
                     ? AppLocalization.string("lyrics.onVideo \(name(showing ?? model.spokenLanguage))", bundle: .module)
                     : AppLocalization.string("lyrics.putOnVideo", bundle: .module))
                    .lineLimit(1)
            }
            .dsFont(.sans, .semibold, 12)
            .foregroundStyle(matches ? Color.white.opacity(0.8) : Color.black)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(matches ? Color.white.opacity(0.14) : Color.white))
        }
        .buttonStyle(.dsPress(radius: 17))
        .disabled(matches)
        .contentTransition(.opacity)
    }

    private var languageBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                chip(title: name(model.spokenLanguage), subtitle: AppLocalization.string("lyrics.original", bundle: .module), isOn: language == nil) {
                    language = nil
                }
                ForEach(model.project.translationLanguages, id: \.self) { code in
                    chip(title: name(code), subtitle: nil, isOn: language == code) { language = code }
                        .contextMenu {
                            Button(role: .destructive) {
                                if language == code { language = nil }
                                model.removeCaptionTranslation(code)
                            } label: {
                                Label(AppLocalization.string("lyrics.removeLanguage", bundle: .module), systemImage: "trash")
                            }
                        }
                }
                if let progress = model.translationProgress {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("lyrics.translating \(Int(progress * 100))", bundle: .module)
                            .contentTransition(.numericText())
                    }
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Capsule().fill(.white.opacity(0.14)))
                } else if model.canTranslateCaptions {
                    Button { choosingLanguage = true } label: {
                        Label(AppLocalization.string("lyrics.translate", bundle: .module), systemImage: "globe")
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.dsPress(radius: 19))
                }
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottomLeading) {
            if let failure = model.translationFailure {
                Text(failure)
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.accent)
                    .padding(.horizontal, 20)
                    .offset(y: 20)
            }
        }
    }

    private func chip(title: String, subtitle: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(DS.Motion.snap) { action() } }) {
            HStack(spacing: 5) {
                Text(verbatim: title)
                if let subtitle {
                    Text(verbatim: subtitle).opacity(0.6)
                }
            }
            .dsFont(.sans, .semibold, 12)
            .foregroundStyle(isOn ? Color.black : Color.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Capsule().fill(isOn ? Color.white : Color.white.opacity(0.12)))
        }
        .buttonStyle(.dsPress(radius: 19))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var lyrics: some View {
        let active = activeIndex
        return ScrollViewReader { proxy in
            ScrollView {
                if rows.isEmpty {
                    Text("lyrics.empty", bundle: .module)
                        .dsFont(.sans, .medium, 15)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(40)
                        .frame(maxWidth: .infinity)
                }
                LazyVStack(alignment: .leading, spacing: 30) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        line(row, distance: active.map { index - $0 } ?? index + 1)
                            .id(row.id)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 36)
                .padding(.bottom, 320)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in heldUntil = .now.addingTimeInterval(3) })
            .onChange(of: active.map { rows[$0].id }) { _, id in
                guard let id, id != lastActive else { return }
                lastActive = id
                guard Date.now >= heldUntil else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.6, dampingFraction: 0.86)) {
                    proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: 0.28))
                }
            }
            .onAppear {
                if let active { proxy.scrollTo(rows[active].id, anchor: UnitPoint(x: 0, y: 0.28)) }
            }
        }
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06), .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// One line: lit word by word while it is said, dimmer and softer the further it is.
    private func line(_ row: LyricRow, distance: Int) -> some View {
        let isActive = distance == 0
        let far = Double(abs(distance))
        let following = Date.now >= heldUntil
        let translated = language.flatMap { row.translations[$0] }.flatMap { $0.isEmpty ? nil : $0 }

        return Button {
            model.seek(to: row.start + 0.01)
            if !model.isPlaying { model.togglePlayback() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                spoken(row, isActive: isActive)
                    .font(.system(size: 30, weight: .bold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let translated {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: translated)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white.opacity(isActive ? 0.78 : 0.34))
                            .fixedSize(horizontal: false, vertical: true)
                        if let language, row.editedTranslations.contains(language) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                } else if language != nil {
                    Text("lyrics.notTranslated", bundle: .module)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.28))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(isActive ? 1 : 0.96, anchor: .leading)
            .blur(radius: following && !reduceMotion ? min(far * 0.9, 3) : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: isActive)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
            model.pause()
            editing = row
        })
        .accessibilityHint(Text("lyrics.lineHint", bundle: .module))
    }

    /// The spoken line, its said words bright while it plays.
    private func spoken(_ row: LyricRow, isActive: Bool) -> Text {
        guard isActive, !row.words.isEmpty else {
            return Text(verbatim: row.text).foregroundStyle(.white.opacity(isActive ? 1 : 0.32))
        }
        let time = model.playhead
        return row.words.enumerated().reduce(Text(verbatim: "")) { text, item in
            let (index, word) = item
            let said = word.range.start.seconds <= time
            let piece = Text(verbatim: (index == 0 ? "" : " ") + word.text)
                .foregroundStyle(.white.opacity(said ? 1 : 0.42))
            return text + piece
        }
    }

    private var transport: some View {
        HStack(spacing: 18) {
            Text(verbatim: MediaTime(seconds: model.playhead).timecode)
                .dsFont(.mono, .medium, 12)
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
                .frame(width: 64, alignment: .leading)

            Spacer(minLength: 0)

            Button { model.togglePlayback() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(.white))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.dsPressIcon)
            .accessibilityLabel(model.isPlaying ? AppLocalization.string("lyrics.pause", bundle: .module) : AppLocalization.string("lyrics.play", bundle: .module))

            Spacer(minLength: 0)

            Button {
                guard let active = activeIndex ?? (rows.isEmpty ? nil : 0) else { return }
                model.pause()
                editing = rows[active]
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 44)
            }
            .buttonStyle(.dsPressIcon)
            .disabled(rows.isEmpty)
            .accessibilityLabel(Text("lyrics.edit", bundle: .module))
        }
        .padding(.horizontal, 26)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    // MARK: - Data

    private func name(_ code: String) -> String {
        CaptionTranslation.name(of: code, in: AppLocalization.locale)
    }

    /// The spoken lines as the video times them, with every translation beside each.
    private func rebuild() {
        var spokenProject = model.project
        spokenProject.captionLanguage = nil
        var cues: [CaptionCue.ID: CaptionCue] = [:]
        for segment in model.project.segments {
            for cue in segment.captions { cues[cue.id] = cue }
        }
        rows = spokenProject.captionCues.map { placed in
            let cue = cues[placed.id]
            return LyricRow(
                id: placed.id,
                text: placed.text,
                words: placed.words,
                start: placed.range.start.seconds,
                end: placed.range.end.seconds,
                translations: cue?.translations ?? [:],
                editedTranslations: cue?.editedTranslations ?? []
            )
        }
    }
}

// MARK: - Correcting a line

private struct LyricEditor: View {
    @Bindable var model: EditorModel
    let row: CaptionLyricsView.LyricRow
    let language: String?
    let onClose: () -> Void

    @State private var original = ""
    @State private var translated = ""
    @FocusState private var focus: Field?

    enum Field { case original, translated }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                DSKicker(AppLocalization.string("lyrics.editTitle", bundle: .module))
                Spacer(minLength: 0)
                Text(verbatim: MediaTime(seconds: row.start).timecode)
                    .dsFont(.mono, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.5))
            }

            field(CaptionTranslation.name(of: model.spokenLanguage, in: AppLocalization.locale), text: $original, focused: .original)
            if let language {
                field(CaptionTranslation.name(of: language, in: AppLocalization.locale), text: $translated, focused: .translated)
            }

            HStack(spacing: 10) {
                Button(action: onClose) {
                    Text("lyrics.cancel", bundle: .module)
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.ink(0.8))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Capsule().fill(DS.Palette.hairline(0.08)))
                }
                .buttonStyle(.dsPress(radius: 24))

                Button(action: save) {
                    Text("lyrics.save", bundle: .module)
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Capsule().fill(DS.Palette.lime))
                }
                .buttonStyle(.dsPress(radius: 24))
            }
        }
        .padding(20)
        .background(DS.Palette.screen)
        .onAppear {
            original = row.text
            translated = language.flatMap { row.translations[$0] } ?? ""
            focus = language == nil ? .original : .translated
        }
    }

    private func field(_ title: String, text: Binding<String>, focused: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.52))
            TextField("", text: text, axis: .vertical)
                .lineLimit(1...4)
                .dsFont(.sans, .semibold, 17)
                .focused($focus, equals: focused)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.06)))
        }
    }

    private func save() {
        if original.trimmingCharacters(in: .whitespaces) != row.text {
            model.correctCaption(row.id, text: original, language: nil)
        }
        if let language, translated.trimmingCharacters(in: .whitespaces) != (row.translations[language] ?? "") {
            model.correctCaption(row.id, text: translated, language: language)
        }
        onClose()
    }
}

// MARK: - Choosing a language

private struct LanguagePicker: View {
    @Bindable var model: EditorModel
    let existing: [String]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                DSKicker(AppLocalization.string("lyrics.translate", bundle: .module))
                Text("lyrics.translate.note", bundle: .module)
                    .dsFont(.sans, .regular, 12, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.ink(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(CaptionTranslation.languages.filter { $0 != model.spokenLanguage }, id: \.self) { code in
                        Button { onPick(code) } label: {
                            HStack {
                                Text(verbatim: CaptionTranslation.name(of: code, in: AppLocalization.locale))
                                    .dsFont(.sans, .semibold, 15)
                                    .foregroundStyle(DS.Palette.ink)
                                Text(verbatim: CaptionTranslation.name(of: code, in: Locale(identifier: code)))
                                    .dsFont(.sans, .regular, 13)
                                    .foregroundStyle(DS.Palette.ink(0.45))
                                Spacer(minLength: 0)
                                if existing.contains(code) {
                                    Text("lyrics.translate.again", bundle: .module)
                                        .dsFont(.mono, .medium, 10)
                                        .foregroundStyle(DS.Palette.lime)
                                } else {
                                    Image(systemName: "globe")
                                        .foregroundStyle(DS.Palette.ink(0.4))
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.05)))
                        }
                        .buttonStyle(.dsPress(radius: 14))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .background(DS.Palette.screen)
    }
}

/// The player drawn with no controls, for the blurred backdrop.
private struct LyricsPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    final class Host: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> Host {
        let view = Host()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: Host, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
