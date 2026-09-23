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
    /// The line to open on: the caption that was tapped.
    var focus: CaptionCue.ID? = nil
    let onClose: () -> Void

    /// The translation shown under each line; nil shows the spoken line alone.
    @State private var language: String?
    @State private var rows: [LyricRow] = []
    @State private var editing: LyricRow?
    @State private var picking: PickerMode?
    /// The line being said now, kept here so the list redraws per line, not per frame.
    @State private var activeID: CaptionCue.ID?
    /// Off once a finger scrolls the list, as in Music; "back to now" turns it on again.
    @State private var following = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum PickerMode: String, Identifiable {
        case translate
        case spoken
        var id: String { rawValue }
    }

    struct LyricRow: Identifiable, Equatable {
        let id: CaptionCue.ID
        let text: String
        let words: [PlacedWord]
        let start: Double
        let end: Double
        let translations: [String: String]
        let editedTranslations: [String]
    }

    private var activeIndex: Int? { activeID.flatMap { id in rows.firstIndex { $0.id == id } } }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                header
                status
                lyrics
                transport
            }
        }
        .background { PlayheadWatcher(model: model, rows: rows, active: $activeID) }
        .preferredColorScheme(.dark)
        .onAppear {
            rebuild()
            language = model.project.captionLanguage ?? model.project.translationLanguages.first
            if let focus, let row = rows.first(where: { $0.id == focus }) {
                model.pause()
                model.seek(to: row.start + 0.01)
                activeID = row.id
            }
        }
        .onChange(of: model.project.segments) { rebuild() }
        .onChange(of: model.project.captionWindow) { rebuild() }
        .sheet(item: $editing) { row in
            LyricEditor(model: model, row: row, language: language) { editing = nil }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $picking) { mode in
            LanguagePicker(model: model, mode: mode) { code in
                picking = nil
                switch mode {
                case .translate:
                    language = code
                    Task { await model.translateCaptions(to: code) }
                case .spoken:
                    language = nil
                    Task { await model.speechRelistener?(code) }
                }
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
        HStack(spacing: 10) {
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
            languageMenu
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    /// Everything about languages in one place: what is read here, translating, and hearing the
    /// footage again when its language was guessed wrong.
    private var languageMenu: some View {
        Menu {
            Section(AppLocalization.string("lyrics.captionLanguage", bundle: .module)) {
                Button {
                    withAnimation(DS.Motion.snap) { language = nil }
                } label: {
                    choice(name(model.spokenLanguage) + " · " + AppLocalization.string("lyrics.original", bundle: .module), isOn: language == nil)
                }
                ForEach(model.project.translationLanguages, id: \.self) { code in
                    Button {
                        withAnimation(DS.Motion.snap) { language = code }
                    } label: {
                        choice(name(code), isOn: language == code)
                    }
                }
            }
            if model.canTranslateCaptions, model.translationProgress == nil {
                Button { picking = .translate } label: {
                    Label(AppLocalization.string("lyrics.translate", bundle: .module), systemImage: "globe")
                }
            }
            if let language {
                Button(role: .destructive) {
                    self.language = nil
                    model.removeCaptionTranslation(language)
                } label: {
                    Label(AppLocalization.string("lyrics.removeLanguage", bundle: .module), systemImage: "trash")
                }
            }
            if model.speechRelistener != nil, !model.relistening {
                Divider()
                Button { picking = .spoken } label: {
                    Label(AppLocalization.string("lyrics.wrongLanguage", bundle: .module), systemImage: "waveform")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text(verbatim: name(language ?? model.spokenLanguage))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .dsFont(.sans, .semibold, 13)
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Capsule().fill(.white))
        }
    }

    @ViewBuilder
    private func choice(_ title: String, isOn: Bool) -> some View {
        if isOn {
            Label(title, systemImage: "checkmark")
        } else {
            Text(verbatim: title)
        }
    }

    /// Work in progress, a failure, or the offer to put the language being read on the video.
    private var status: some View {
        let showing = model.project.captionLanguage
        let matches = showing == language
        return Group {
            if model.relistening {
                progressPill(Text("lyrics.relistening", bundle: .module))
            } else if let progress = model.translationProgress {
                progressPill(Text("lyrics.translating \(Int(progress * 100))", bundle: .module))
            } else if let failure = model.translationFailure {
                Text(verbatim: failure)
                    .dsFont(.sans, .medium, 12)
                    .foregroundStyle(DS.Palette.accent)
            } else if !matches {
                Button {
                    withAnimation(DS.Motion.snap) { model.showCaptions(in: language) }
                } label: {
                    Label(AppLocalization.string("lyrics.putOnVideo", bundle: .module), systemImage: "rectangle.inset.bottomleft.filled")
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(.white.opacity(0.16)))
                }
                .buttonStyle(.dsPress(radius: 17))
            } else {
                Text(verbatim: AppLocalization.string("lyrics.onVideo \(name(showing ?? model.spokenLanguage))", bundle: .module))
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .animation(DS.Motion.snap, value: model.relistening)
    }

    private func progressPill(_ text: Text) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(.white)
            text.contentTransition(.numericText())
        }
        .dsFont(.sans, .semibold, 12)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(.white.opacity(0.14)))
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
                // Not lazy: scrolling to a line needs every line measured. A lazy stack guesses the
                // height of lines it has not drawn, so the list landed short of the voice and jumped.
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        LyricLine(
                            model: model,
                            row: row,
                            distance: active.map { index - $0 } ?? index + 1,
                            language: language,
                            softens: following && !reduceMotion,
                            onTap: { hear(row, proxy: proxy) },
                            onEdit: {
                                model.pause()
                                editing = row
                            }
                        )
                        .id(row.id)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 40)
                .padding(.bottom, 360)
            }
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { following = false }
            }
            .onChange(of: activeID) { _, id in
                guard following, let id else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.88)) {
                    proxy.scrollTo(id, anchor: Self.anchor)
                }
            }
            .onChange(of: following) { _, now in
                guard now, let activeID else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
                    proxy.scrollTo(activeID, anchor: Self.anchor)
                }
            }
            .onAppear {
                guard let id = activeID ?? rows.first?.id else { return }
                DispatchQueue.main.async { proxy.scrollTo(id, anchor: Self.anchor) }
            }
            .overlay(alignment: .bottom) {
                if !following, activeID != nil {
                    Button {
                        following = true
                    } label: {
                        Label(AppLocalization.string("lyrics.backToNow", bundle: .module), systemImage: "arrow.down.to.line")
                            .dsFont(.sans, .semibold, 13)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(Capsule().fill(.white))
                            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                    }
                    .buttonStyle(.dsPress(radius: 20))
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(DS.Motion.snap, value: following)
        }
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// Where the line being said sits: a third of the way down, as in Music.
    private static let anchor = UnitPoint(x: 0, y: 0.3)

    /// A tapped line is heard from its start, and the list follows the voice from there.
    private func hear(_ row: LyricRow, proxy: ScrollViewProxy) {
        model.seek(to: row.start + 0.01)
        activeID = row.id
        following = true
        withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
            proxy.scrollTo(row.id, anchor: Self.anchor)
        }
        if !model.isPlaying { model.togglePlayback() }
    }

    private var transport: some View {
        HStack(spacing: 18) {
            PlayheadClock(model: model)
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

/// Reads the playhead so the list does not have to: the list redraws when the line changes, not
/// thirty times a second.
private struct PlayheadWatcher: View {
    @Bindable var model: EditorModel
    let rows: [CaptionLyricsView.LyricRow]
    @Binding var active: CaptionCue.ID?

    var body: some View {
        let time = model.playhead
        // The line whose time holds the playhead; in a pause between lines, the one just said.
        let id = rows.last { $0.start <= time + 0.05 }?.id
        Color.clear
            .onChange(of: id, initial: true) { _, new in
                if active != new { active = new }
            }
    }
}

private struct PlayheadClock: View {
    @Bindable var model: EditorModel

    var body: some View {
        Text(verbatim: MediaTime(seconds: model.playhead).timecode)
            .dsFont(.mono, .medium, 12)
            .foregroundStyle(.white.opacity(0.7))
            .monospacedDigit()
    }
}

/// One line: lit word by word while it is said, dimmer and softer the further it is.
private struct LyricLine: View {
    let model: EditorModel
    let row: CaptionLyricsView.LyricRow
    let distance: Int
    let language: String?
    let softens: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isActive = distance == 0
        let far = Double(abs(distance))
        let translated = language.flatMap { row.translations[$0] }.flatMap { $0.isEmpty ? nil : $0 }

        VStack(alignment: .leading, spacing: 8) {
            Group {
                if isActive {
                    ActiveWords(model: model, row: row)
                } else {
                    Text(verbatim: row.text).foregroundStyle(.white.opacity(0.34))
                }
            }
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

            if isActive, !model.isPlaying {
                Button(action: onEdit) {
                    Label(AppLocalization.string("lyrics.fix", bundle: .module), systemImage: "pencil")
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().fill(.white.opacity(0.18)))
                }
                .buttonStyle(.dsPress(radius: 15))
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(isActive ? 1 : 0.96, anchor: .leading)
        .blur(radius: softens ? min(far * 0.9, 3) : 0)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(action: onEdit) {
                Label(AppLocalization.string("lyrics.fix", bundle: .module), systemImage: "pencil")
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: isActive)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("lyrics.lineHint", bundle: .module))
    }
}

/// The line being said, its said words bright. The only part of the list that reads the playhead.
private struct ActiveWords: View {
    @Bindable var model: EditorModel
    let row: CaptionLyricsView.LyricRow

    var body: some View {
        if row.words.isEmpty {
            Text(verbatim: row.text).foregroundStyle(.white)
        } else {
            let time = model.playhead
            row.words.enumerated().reduce(Text(verbatim: "")) { text, item in
                let (index, word) = item
                let said = word.range.start.seconds <= time + 0.03
                return text + Text(verbatim: (index == 0 ? "" : " ") + word.text)
                    .foregroundStyle(.white.opacity(said ? 1 : 0.45))
            }
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
    let mode: CaptionLyricsView.PickerMode
    let onPick: (String) -> Void

    private var codes: [String] {
        switch mode {
        case .translate: CaptionTranslation.languages.filter { $0 != model.spokenLanguage }
        case .spoken: CaptionTranslation.languages
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                DSKicker(mode == .translate
                    ? AppLocalization.string("lyrics.translate", bundle: .module)
                    : AppLocalization.string("lyrics.spoken.title", bundle: .module))
                Group {
                    if mode == .translate {
                        Text("lyrics.translate.note", bundle: .module)
                    } else {
                        Text("lyrics.spoken.note", bundle: .module)
                    }
                }
                .dsFont(.sans, .regular, 12, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.58))
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(codes, id: \.self) { code in
                        Button { onPick(code) } label: {
                            HStack {
                                Text(verbatim: CaptionTranslation.name(of: code, in: AppLocalization.locale))
                                    .dsFont(.sans, .semibold, 15)
                                    .foregroundStyle(DS.Palette.ink)
                                Text(verbatim: CaptionTranslation.name(of: code, in: Locale(identifier: code)))
                                    .dsFont(.sans, .regular, 13)
                                    .foregroundStyle(DS.Palette.ink(0.45))
                                Spacer(minLength: 0)
                                trailing(code)
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

    @ViewBuilder
    private func trailing(_ code: String) -> some View {
        switch mode {
        case .translate:
            if model.project.translationLanguages.contains(code) {
                Text("lyrics.translate.again", bundle: .module)
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.lime)
            } else {
                Image(systemName: "globe").foregroundStyle(DS.Palette.ink(0.4))
            }
        case .spoken:
            if code == model.spokenLanguage {
                Image(systemName: "checkmark").foregroundStyle(DS.Palette.lime)
            } else {
                Image(systemName: "waveform").foregroundStyle(DS.Palette.ink(0.4))
            }
        }
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
