import CoreGraphics
import DesignSystem
import Domain
import SwiftUI

/// The captions studio: pick a look, place it on the picture, and fix every line by hand.
///
/// It used to be a style picker over a grey plate showing the first nine cues, none of which could
/// be touched — so a misheard word went all the way to the export. Now the preview is the clip's own
/// frame with the real overlay drawn on it (the same one the editor uses, from the same numbers the
/// export burns in), the caption is dragged to where it should sit, and the list below is every cue
/// in the video: tap one to retype it, move its start and end, split it or join it to the next.
public struct CaptionsScreen: View {
    /// The pack last applied here, to mark it.
    @State private var appliedPack: String?
    @Binding private var project: Project
    /// Frames sampled from each take, for putting the caption over the picture it belongs to.
    private let frames: [Take.ID: [CGImage]]
    /// Reports the look upward: the app regroups cues when the number of words per line changes.
    private let onStyleChange: (CaptionStyle) -> Void
    private let onBack: () -> Void
    private let onExport: () -> Void
    private let onTranscribe: () -> Void

    /// The whole look, preset plus every adjustment. One value for every caption in the video.
    @State private var look: CaptionStyle
    @State private var positionY: Double
    @State private var showsTuning = false
    @State private var selectedCueID: CaptionCue.ID?
    @State private var dragOriginY: Double?
    @State private var previewHeight: CGFloat = 1
    @State private var snapTick = 0
    @State private var confirmsRebuild = false
    @FocusState private var focusedCue: CaptionCue.ID?
    @Namespace private var styleSelection

    /// Where a caption clicks into place while it is dragged: top, middle, lower third, bottom.
    private static let snapPoints: [Double] = [0.12, 0.5, 0.72, 0.86]

    private static let quickPositions: [(point: Double, symbol: String)] = [
        (0.12, "arrow.up.to.line"),
        (0.5, "align.vertical.center"),
        (0.86, "arrow.down.to.line"),
    ]

    public init(
        project: Binding<Project>,
        frames: [Take.ID: [CGImage]] = [:],
        onStyleChange: @escaping (CaptionStyle) -> Void = { _ in },
        onBack: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onTranscribe: @escaping () -> Void = {}
    ) {
        self._project = project
        self.frames = frames
        self.onStyleChange = onStyleChange
        self.onBack = onBack
        self.onExport = onExport
        self.onTranscribe = onTranscribe
        let current = project.wrappedValue.captionStyle
        _look = State(initialValue: current)
        _positionY = State(initialValue: current.position.y)
    }

    // MARK: - Data

    struct CueRow: Identifiable {
        var id: CaptionCue.ID { cue.id }
        let segmentIndex: Int
        let cue: CaptionCue
        /// Where it lands in the finished video, with its spoken words. Nil for a cue that sits
        /// past the end of its trimmed clip and will not be shown.
        let placed: PlacedCue?
    }

    private var rows: [CueRow] {
        let placed = Dictionary(project.captionCues.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return project.segments.enumerated().flatMap { index, segment in
            segment.captions.map { CueRow(segmentIndex: index, cue: $0, placed: placed[$0.id]) }
        }
    }

    private var selectedRow: CueRow? {
        let all = rows
        return all.first { $0.id == selectedCueID } ?? all.first
    }

    private var hasFootage: Bool {
        project.segments.contains { $0.selectedTake != nil }
    }

    /// The look being previewed. Built locally so a drag moves the caption at sixty frames a second
    /// rather than at the pace of a project write.
    private var previewStyle: CaptionStyle {
        var style = look
        style.position = CaptionPosition(x: 0.5, y: positionY)
        return style
    }

    private var aspect: CGFloat {
        let size = project.format.renderSize
        return CGFloat(size.width) / CGFloat(max(1, size.height))
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)

            preview
                .frame(maxHeight: focusedCue != nil ? 150 : (showsTuning ? 210 : 330))
                .padding(.top, 12)
                .padding(.horizontal, 18)

            if focusedCue == nil {
                looks
                    .padding(.top, 14)
                    .padding(.horizontal, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            cueList
                .padding(.top, 12)
        }
        .padding(.top, 58)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dsScreenLayout(scrolls: true)
        .background(DS.Palette.screen)
        .animation(DS.Motion.settle, value: focusedCue)
        .sensoryFeedback(.selection, trigger: snapTick)
        .confirmationDialog(
            AppLocalization.string("captions.rebuild", bundle: .module),
            isPresented: $confirmsRebuild,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.string("captions.rebuild", bundle: .module), role: .destructive) {
                rebuildFromSpeech()
            }
        } message: {
            Text("captions.rebuild.note", bundle: .module)
        }
        .dsEnter(.screen())
    }

    private var header: some View {
        HStack(spacing: 10) {
            DSBackButton(size: 34, fontSize: 15, action: onBack)
            DSKicker(AppLocalization.string("captions.kicker", bundle: .module), color: DS.Palette.ink(0.55))
            Spacer(minLength: 0)

            if focusedCue != nil {
                Button {
                    focusedCue = nil
                } label: {
                    Text("captions.done", bundle: .module)
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.ink)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .dsGlass(tint: DS.Palette.glass(0.6), in: Capsule())
                }
                .buttonStyle(.dsPress)
                .transition(.scale.combined(with: .opacity))
            } else {
                Menu {
                    Button {
                        onTranscribe()
                    } label: {
                        Label(AppLocalization.string("captions.listen", bundle: .module), systemImage: "waveform.and.person.filled")
                    }
                    .disabled(!hasFootage)

                    Button(role: .destructive) {
                        confirmsRebuild = true
                    } label: {
                        Label(AppLocalization.string("captions.rebuild", bundle: .module), systemImage: "arrow.counterclockwise")
                    }
                    .disabled(rows.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Palette.ink)
                        .frame(width: 34, height: 34)
                        .dsGlass(tint: DS.Palette.glass(0.6), in: Circle())
                }

                Button(action: onExport) {
                    Text("captions.export", bundle: .module)
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(DS.Palette.accent))
                }
                .buttonStyle(.dsPress)
            }
        }
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack {
            backdrop

            if let row = selectedRow {
                let cue = row.placed ?? PlacedCue(id: row.cue.id, text: row.cue.text, range: row.cue.range)
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    CaptionOverlay(
                        cue: cue,
                        style: previewStyle,
                        locale: project.locale,
                        time: Self.loopTime(for: cue, at: timeline.date)
                    )
                }
                .id("\(cue.id)-\(cue.text)-\(look.presetID)")
                .transition(CaptionOverlay.transition(for: previewStyle))
            }

            if dragOriginY != nil {
                guides
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            previewHeight = max(1, height)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous)
                .stroke(DS.Palette.hairline(dragOriginY == nil ? 0.08 : 0.3), lineWidth: 1)
        }
        .overlay {
            if rows.isEmpty { emptyState }
        }
        .contentShape(Rectangle())
        .gesture(positionDrag, including: rows.isEmpty ? .subviews : .all)
        .animation(DS.Motion.settle, value: selectedCueID)
        .animation(DS.Motion.snap, value: look)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let image = frame(for: selectedRow) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .overlay(Color.black.opacity(0.12))
                .transition(.opacity)
                .id(ObjectIdentifier(image))
        } else {
            LinearGradient(
                colors: [DS.Palette.camera, Color(hex: 0x1C1C24), DS.Palette.camera],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// Dashed lines at the places a caption usually belongs, shown only while one is being moved.
    private var guides: some View {
        GeometryReader { proxy in
            ForEach(Self.snapPoints, id: \.self) { point in
                let isOn = abs(positionY - point) < 0.001
                Path { path in
                    let y = proxy.size.height * point
                    path.move(to: CGPoint(x: 12, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width - 12, y: y))
                }
                .stroke(
                    isOn ? DS.Palette.lime : DS.Palette.hairline(0.28),
                    style: StrokeStyle(lineWidth: isOn ? 1.5 : 1, dash: [5, 5])
                )
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    /// Drag anywhere on the picture to move the caption up or down. It clicks into the usual
    /// places, with a tick you can feel, and anywhere between is allowed too.
    private var positionDrag: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragOriginY == nil {
                    withAnimation(DS.Easing.ease(0.2)) { dragOriginY = positionY }
                    focusedCue = nil
                }
                let raw = (dragOriginY ?? positionY) + value.translation.height / previewHeight
                var next = min(max(raw, 0.08), 0.92)
                if let snap = Self.snapPoints.first(where: { abs($0 - next) < 0.025 }) {
                    next = snap
                    if abs(positionY - snap) > 0.001 { snapTick += 1 }
                }
                positionY = next
            }
            .onEnded { _ in
                withAnimation(DS.Easing.ease(0.25)) { dragOriginY = nil }
                report()
            }
    }

    /// A clock that plays the cue over and over with a short rest, so karaoke visibly fills and
    /// every look can be judged moving rather than frozen.
    static func loopTime(for cue: PlacedCue, at date: Date) -> Double {
        let length = max(0.3, cue.range.duration.seconds)
        let cycle = length + 0.7
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        return cue.range.start.seconds + min(phase, length - 0.01)
    }

    private func frame(for row: CueRow?) -> CGImage? {
        guard let row, project.segments.indices.contains(row.segmentIndex),
              let take = project.segments[row.segmentIndex].selectedTake,
              let images = frames[take.id], !images.isEmpty
        else { return nil }
        let length = max(0.01, take.sourceRange.duration.seconds)
        let middle = row.cue.range.start.seconds + row.cue.range.duration.seconds / 2
        let index = Int(middle / length * Double(images.count))
        return images[min(max(0, index), images.count - 1)]
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: hasFootage ? "captions.bubble" : "film.stack")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(DS.Palette.ink(0.7))
                .symbolEffect(.pulse, options: .repeating)

            Text(hasFootage ? "captions.empty.title" : "captions.noFootage.title", bundle: .module)
                .dsFont(.archivo, .bold, 18)
                .foregroundStyle(DS.Palette.ink)
                .multilineTextAlignment(.center)

            Text(hasFootage ? "captions.empty.note" : "captions.noFootage.note", bundle: .module)
                .dsFont(.sans, .regular, 12, lineHeight: 1.45)
                .foregroundStyle(DS.Palette.ink(0.55))
                .multilineTextAlignment(.center)

            if hasFootage {
                Button(action: onTranscribe) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.and.person.filled")
                            .font(.system(size: 12, weight: .semibold))
                        Text("captions.empty.action", bundle: .module)
                            .dsFont(.sans, .semibold, 14)
                    }
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(DS.Palette.accent))
                }
                .buttonStyle(.dsPress(radius: 30))
            }
        }
        .padding(22)
        .frame(maxWidth: 290)
        .dsGlass(
            tint: DS.Palette.glassSheet(0.9),
            in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous),
            border: DS.Palette.hairline(0.12)
        )
        .dsEnter(.rise(duration: 0.4))
    }

    // MARK: - Looks

    private var looks: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(CaptionStyle.presetIDs, id: \.self) { presetID in
                            lookCard(presetID)
                                .frame(width: 84)
                                .id(presetID)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .onAppear { proxy.scrollTo(look.presetID, anchor: .center) }
            }

            StylePackRow(selected: appliedPack) { pack in
                withAnimation(DS.Motion.settle) {
                    project.apply(pack)
                    look = project.captionStyle
                    appliedPack = pack.id
                }
                snapTick += 1
                report()
            }

            HStack(spacing: 8) {
                DSKicker(AppLocalization.string("captions.position", bundle: .module), size: 10, color: DS.Palette.ink(0.52))
                Text("captions.drag.hint", bundle: .module)
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.ink(0.56))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                ForEach(Self.quickPositions, id: \.point) { item in
                    quickPositionButton(item.point, symbol: item.symbol)
                }
            }

            Button {
                withAnimation(DS.Motion.bloom) { showsTuning.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .symbolEffect(.bounce, value: showsTuning)
                    Text("captions.tune", bundle: .module)
                        .dsFont(.sans, .semibold, 13)
                    if isCustomized {
                        Text("captions.tune.customized", bundle: .module)
                            .dsFont(.mono, .medium, 10)
                            .foregroundStyle(DS.Palette.inkInverse)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DS.Palette.lime))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                    Text("captions.tune.allClips", bundle: .module)
                        .dsFont(.sans, .regular, 11)
                        .foregroundStyle(DS.Palette.ink(0.56))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(showsTuning ? 180 : 0))
                }
                .foregroundStyle(DS.Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.06)))
            }
            .buttonStyle(.dsPress(radius: 14))

            if showsTuning {
                ScrollView {
                    VStack(spacing: 10) {
                        CaptionTuningPanel(look: $look, onCommit: report)
                        CaptionWindowControl(
                            window: $project.captionWindow,
                            duration: project.segments.reduce(0) { $0 + $1.barWeight }
                        )
                    }
                }
                .frame(maxHeight: 300)
                .scrollIndicators(.hidden)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func quickPositionButton(_ point: Double, symbol: String) -> some View {
        let isOn = abs(positionY - point) < 0.001
        return Button {
            withAnimation(DS.Motion.snap) { positionY = point }
            snapTick += 1
            report()
        } label: {
            Image(systemName: symbol)
                .dsActionName(symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.7))
                .frame(width: 30, height: 30)
                .background(Circle().fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07)))
        }
        .buttonStyle(.dsPressIcon)
    }

    /// Each look shown in its own type, colour and emphasis, so choosing is recognising rather
    /// than reading.
    private func lookCard(_ presetID: String) -> some View {
        let isOn = look.presetID == presetID
        return Button {
            guard !isOn else { return }
            // A preset is a fresh start: its own size, colours, motion and words per line.
            withAnimation(DS.Motion.snap) { look = CaptionStyle.preset(presetID, position: look.position) }
            appliedPack = nil
            snapTick += 1
            report()
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(white: 0.18))
                    CaptionSwatch(style: CaptionStyle.preset(presetID), size: 13)
                }
                .frame(height: 34)

                Text(verbatim: CaptionStyleCatalog.label(presetID))
                    .dsFont(.sans, .medium, 11)
                    .foregroundStyle(isOn ? DS.Palette.ink : DS.Palette.ink(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .fill(DS.Palette.accent(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                                .stroke(DS.Palette.accent(0.7), lineWidth: 1.2)
                        )
                        .matchedGeometryEffect(id: "look", in: styleSelection)
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .fill(DS.Palette.hairline(0.05))
                }
            }
            .scaleEffect(isOn ? 1 : 0.97)
        }
        .buttonStyle(.dsPress(radius: DS.Radius.m))
        .accessibilityLabel(Text(verbatim: CaptionStyleCatalog.label(presetID)))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Cue list

    private var cueList: some View {
        let all = rows
        let selected = selectedRow?.id
        let edited = all.filter(\.cue.isUserEdited).count

        return VStack(alignment: .leading, spacing: 8) {
            if !all.isEmpty {
                HStack {
                    DSKicker(AppLocalization.string("captions.count \(all.count)", bundle: .module), size: 10, color: DS.Palette.ink(0.52))
                    Spacer(minLength: 0)
                    if fastCount > 0 {
                        Label {
                            Text("captions.tooFast \(fastCount)", bundle: .module)
                        } icon: {
                            Image(systemName: "hare.fill")
                        }
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.accent)
                        .help(Text("captions.tooFast.hint", bundle: .module))
                    }
                    if edited > 0 {
                        Text("captions.editedCount \(edited)", bundle: .module)
                            .dsFont(.mono, .medium, 10)
                            .foregroundStyle(DS.Palette.lime.opacity(0.8))
                            .contentTransition(.numericText())
                    }
                }
                .padding(.horizontal, 22)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(all) { row in
                            cueRow(row, isSelected: row.id == selected)
                                .id(row.id)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 40)
                    .animation(DS.Motion.settle, value: all.map(\.id))
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: selectedCueID) { _, id in
                    guard let id else { return }
                    withAnimation(DS.Motion.settle) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private func cueRow(_ row: CueRow, isSelected: Bool) -> some View {
        let start = row.placed?.range.start.seconds
        let length = row.placed?.range.duration.seconds ?? row.cue.range.duration.seconds

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(verbatim: start.map(Self.timecode) ?? "—")
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.ink(0.4))
                    .contentTransition(.numericText())

                if row.cue.isUserEdited {
                    Text("captions.edited", bundle: .module)
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DS.Palette.lime))
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer(minLength: 0)

                Text(verbatim: String(format: "%.1fs", length))
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.52))
                    .contentTransition(.numericText())
            }

            if isSelected {
                TextField(
                    AppLocalization.string("captions.placeholder", bundle: .module),
                    text: textBinding(for: row),
                    axis: .vertical
                )
                .dsFont(.sans, .semibold, 16)
                .foregroundStyle(DS.Palette.ink)
                .tint(DS.Palette.accent)
                .focused($focusedCue, equals: row.id)
                .submitLabel(.done)

                timing(row)
                actions(row)
            } else {
                Text(row.cue.text)
                    .dsFont(.sans, .medium, 15)
                    .foregroundStyle(DS.Palette.ink(0.78))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? DS.Palette.surfaceActive : DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? DS.Palette.accent(0.45) : DS.Palette.hairline(0.06), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            guard !isSelected else { return }
            withAnimation(DS.Motion.settle) { selectedCueID = row.id }
        }
        .opacity(row.placed == nil ? 0.5 : 1)
    }

    private func timing(_ row: CueRow) -> some View {
        HStack(spacing: 8) {
            stepper(AppLocalization.string("captions.edit.start", bundle: .module), value: row.cue.range.start.seconds) { delta in
                edit(row) { $0.nudgeCaption(row.id, start: delta) }
            }
            stepper(AppLocalization.string("captions.edit.end", bundle: .module), value: row.cue.range.end.seconds) { delta in
                edit(row) { $0.nudgeCaption(row.id, end: delta) }
            }
        }
    }

    /// Minus and plus a tenth of a second, repeating while held. Seconds within the clip, which is
    /// what the numbers mean to someone lining a word up with a mouth.
    private func stepper(_ title: String, value: Double, onStep: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 0) {
            stepButton("minus") { onStep(-0.1) }

            VStack(spacing: 1) {
                Text(title)
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.56))
                Text(verbatim: String(format: "%.1f s", value))
                    .dsFont(.mono, .medium, 13)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText(value: value))
                    .animation(DS.Motion.snap, value: value)
            }
            .frame(maxWidth: .infinity)

            stepButton("plus") { onStep(0.1) }
        }
        .padding(4)
        .background(Capsule().fill(DS.Palette.hairline(0.06)))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .dsActionName(symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(DS.Palette.hairline(0.08)))
        }
        .buttonRepeatBehavior(.enabled)
        .buttonStyle(.dsPressIcon)
    }

    private func actions(_ row: CueRow) -> some View {
        let segment = project.segments[row.segmentIndex]
        return HStack(spacing: 6) {
            actionButton("captions.edit.split", symbol: "scissors", enabled: segment.canSplitCaption(row.id)) {
                edit(row) { $0.splitCaption(row.id) }
            }
            actionButton("captions.edit.merge", symbol: "arrow.trianglehead.merge", enabled: segment.canMergeCaption(row.id)) {
                edit(row) { $0.mergeCaptionWithNext(row.id) }
            }
            Spacer(minLength: 0)
            actionButton("captions.edit.delete", symbol: "trash", enabled: true, destructive: true) {
                delete(row)
            }
        }
    }

    private func actionButton(
        _ key: String.LocalizationValue,
        symbol: String,
        enabled: Bool,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(DS.Motion.settle) { action() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(AppLocalization.string(key, bundle: .module))
                    .dsFont(.sans, .medium, 12)
            }
            .foregroundStyle(destructive ? DS.Palette.accent : DS.Palette.ink(0.85))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Capsule().fill(destructive ? DS.Palette.accent(0.12) : DS.Palette.hairline(0.07)))
        }
        .buttonStyle(.dsPress(radius: 20))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    // MARK: - Editing

    private func textBinding(for row: CueRow) -> Binding<String> {
        Binding(
            get: {
                guard project.segments.indices.contains(row.segmentIndex) else { return "" }
                return project.segments[row.segmentIndex].captions.first { $0.id == row.id }?.text ?? ""
            },
            set: { text in
                guard project.segments.indices.contains(row.segmentIndex) else { return }
                // Return on a vertical field inserts a newline; on a caption it means "done".
                if text.contains("\n") {
                    focusedCue = nil
                }
                let clean = text.replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .newlines)
                project.segments[row.segmentIndex].setCaptionText(row.id, to: clean)
                project.updatedAt = .now
            }
        )
    }

    private func edit(_ row: CueRow, _ change: (inout Segment) -> Void) {
        guard project.segments.indices.contains(row.segmentIndex) else { return }
        change(&project.segments[row.segmentIndex])
        project.updatedAt = .now
    }

    /// Removes a cue and moves the selection to its neighbour, so a run of bad lines can be
    /// cleared with repeated taps in one place.
    private func delete(_ row: CueRow) {
        let all = rows
        let index = all.firstIndex { $0.id == row.id } ?? 0
        let next = all.indices.contains(index + 1) ? all[index + 1].id : (index > 0 ? all[index - 1].id : nil)
        focusedCue = nil
        edit(row) { $0.removeCaption(row.id) }
        selectedCueID = next
    }

    private func rebuildFromSpeech() {
        let maxWords = look.maxWordsPerCue
        for index in project.segments.indices {
            project.segments[index].refreshCaptions(maxWordsPerCue: maxWords)
        }
        project.updatedAt = .now
        selectedCueID = nil
    }

    private func report() {
        onStyleChange(previewStyle)
    }

    /// Cues shown faster than most people read.
    private var fastCount: Int {
        CaptionReadability.tooFast(project.captionCues).count
    }

    private var isCustomized: Bool {
        var preset = CaptionStyle.preset(look.presetID, position: look.position)
        preset.position = look.position
        return preset != look
    }

    static func timecode(_ seconds: Double) -> String {
        let whole = Int(seconds)
        let tenth = Int((seconds - Double(whole)) * 10)
        return String(format: "%d:%02d.%d", whole / 60, whole % 60, tenth)
    }
}

// MARK: - Fine tuning

extension CaptionsScreen {
    static let colorSwatches: [(id: String, color: RGBAColor)] = [
        ("white", .white),
        ("black", .black),
        ("lime", RGBAColor(red: 0xE8 / 255, green: 1, blue: 0x4F / 255)),
        ("yellow", RGBAColor(red: 1, green: 0.84, blue: 0.04)),
        ("coral", RGBAColor(red: 1, green: 0x5A / 255, blue: 0x4F / 255)),
        ("sky", RGBAColor(red: 0.35, green: 0.78, blue: 1)),
    ]

    static let plateSwatches: [(id: String, color: RGBAColor)] = [
        ("dark", RGBAColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 0.62)),
        ("white", RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.96)),
        ("coral", RGBAColor(red: 1, green: 0x5A / 255, blue: 0x4F / 255, alpha: 0.95)),
        ("lime", RGBAColor(red: 0xE8 / 255, green: 1, blue: 0x4F / 255, alpha: 0.95)),
    ]

    static let sizeRange: ClosedRange<Double> = 0.018...0.075
}

/// Every setting of the look, for all captions at once.
///
/// The presets decide a lot — face, size, case, colour, plate, words per line — and the only way to
/// change any of it used to be to pick a different preset, or to fix captions one clip at a time.
/// These controls change the look of every caption in the video together, on top of whichever
/// preset they started from, and the preview shows each change as it happens.
struct CaptionTuningPanel: View {
    @Binding var look: CaptionStyle
    /// Called when a change is finished, rather than for every step of a slider.
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Size
            VStack(alignment: .leading, spacing: 6) {
                row("captions.tune.size") {
                    Text(verbatim: "\(Int((look.relativeFontSize / 0.04 * 100).rounded()))%")
                        .dsFont(.mono, .medium, 11)
                        .foregroundStyle(DS.Palette.ink(0.7))
                        .contentTransition(.numericText())
                }
                HStack(spacing: 10) {
                    Image(systemName: "textformat.size.smaller")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.ink(0.5))
                    Slider(
                        value: $look.relativeFontSize,
                        in: CaptionsScreen.sizeRange,
                        onEditingChanged: { editing in if !editing { onCommit() } }
                    )
                    .tint(DS.Palette.accent)
                    Image(systemName: "textformat.size.larger")
                        .font(.system(size: 15))
                        .foregroundStyle(DS.Palette.ink(0.5))
                }
            }

            // Words per line
            VStack(alignment: .leading, spacing: 6) {
                row("captions.tune.words") {
                    Text(verbatim: "\(look.maxWordsPerCue)")
                        .dsFont(.mono, .medium, 11)
                        .foregroundStyle(DS.Palette.ink(0.7))
                        .contentTransition(.numericText())
                }
                HStack(spacing: 5) {
                    ForEach(1...8, id: \.self) { count in
                        let isOn = look.maxWordsPerCue == count
                        Button {
                            guard !isOn else { return }
                            withAnimation(DS.Motion.snap) { look.maxWordsPerCue = count }
                            onCommit()
                        } label: {
                            Text(verbatim: "\(count)")
                                .dsFont(.mono, .medium, 12)
                                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(isOn ? DS.Palette.accent : DS.Palette.hairline(0.07))
                                )
                        }
                        .buttonStyle(.dsPress(radius: 9))
                    }
                }
            }

            CaptionMotionTuning(look: $look, onCommit: onCommit)

            // Case
            VStack(alignment: .leading, spacing: 6) {
                row("captions.tune.case") { EmptyView() }
                HStack(spacing: 6) {
                    caseChip(.natural, "Aa")
                    caseChip(.uppercase, "AA")
                    caseChip(.lowercase, "aa")
                }
            }

            // Colours
            VStack(alignment: .leading, spacing: 6) {
                row("captions.tune.color") { EmptyView() }
                swatches(CaptionsScreen.colorSwatches, selected: look.textColor, allowsNone: false) { color in
                    look.textColor = color ?? .white
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                row("captions.tune.highlight") { EmptyView() }
                swatches(CaptionsScreen.colorSwatches, selected: look.highlightColor, allowsNone: true) { color in
                    look.highlightColor = color
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                row("captions.tune.plate") { EmptyView() }
                swatches(CaptionsScreen.plateSwatches, selected: look.backgroundColor, allowsNone: true) { color in
                    look.backgroundColor = color
                }
            }

            Button {
                withAnimation(DS.Motion.settle) {
                    look = CaptionStyle.preset(look.presetID, position: look.position)
                }
                onCommit()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("captions.tune.reset", bundle: .module)
                        .dsFont(.sans, .medium, 12)
                }
                .foregroundStyle(DS.Palette.ink(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(DS.Palette.hairline(0.07)))
            }
            .buttonStyle(.dsPress(radius: 20))
            .disabled(look == CaptionStyle.preset(look.presetID, position: look.position))
            .opacity(look == CaptionStyle.preset(look.presetID, position: look.position) ? 0.4 : 1)
        }
        .padding(14)
        .dsGlass(
            tint: DS.Palette.glassSheet(0.9),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous),
            border: DS.Palette.hairline(0.1)
        )
    }

    private func row<Trailing: View>(_ key: String.LocalizationValue, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            DSKicker(AppLocalization.string(key, bundle: .module), size: 10, color: DS.Palette.ink(0.56))
            Spacer(minLength: 0)
            trailing()
        }
    }

    private func caseChip(_ textCase: CaptionTextCase, _ label: String) -> some View {
        let isOn = look.textCase == textCase
        return Button {
            withAnimation(DS.Motion.snap) { look.textCase = textCase }
            onCommit()
        } label: {
            Text(verbatim: label)
                .dsFont(.sans, .semibold, 13)
                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07)))
        }
        .buttonStyle(.dsPress(radius: 10))
    }

    private func swatches(
        _ options: [(id: String, color: RGBAColor)],
        selected: RGBAColor?,
        allowsNone: Bool,
        onPick: @escaping (RGBAColor?) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            if allowsNone {
                let isOn = selected == nil
                Button {
                    withAnimation(DS.Motion.snap) { onPick(nil) }
                    onCommit()
                } label: {
                    Image(systemName: "nosign")
                        .dsActionName("nosign")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(DS.Palette.hairline(0.07)))
                        .overlay(Circle().stroke(isOn ? DS.Palette.accent : .clear, lineWidth: 2).padding(-3))
                }
                .buttonStyle(.dsPressIcon)
            }
            ForEach(options, id: \.id) { option in
                let isOn = selected.map { Self.close($0, option.color) } ?? false
                Button {
                    withAnimation(DS.Motion.snap) { onPick(option.color) }
                    onCommit()
                } label: {
                    Circle()
                        .fill(CaptionOverlay.color(option.color))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(DS.Palette.hairline(0.25), lineWidth: 1))
                        .overlay(Circle().stroke(isOn ? DS.Palette.accent : .clear, lineWidth: 2).padding(-3))
                        .scaleEffect(isOn ? 1.08 : 1)
                }
                .buttonStyle(.dsPressIcon)
            }
            Spacer(minLength: 0)
        }
    }

    private static func close(_ a: RGBAColor, _ b: RGBAColor) -> Bool {
        abs(a.red - b.red) < 0.02 && abs(a.green - b.green) < 0.02 && abs(a.blue - b.blue) < 0.02
    }
}

/// When captions are on screen: the whole video, or only between two moments.
///
/// "From 29 seconds on", "only the first half" — a whole-video setting, not a per-caption one, so
/// nobody deletes captions one by one to get a quiet stretch.
struct CaptionWindowControl: View {
    @Binding var window: MediaTimeRange?
    let duration: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DSKicker(AppLocalization.string("captions.window", bundle: .module), size: 10, color: DS.Palette.ink(0.56))
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    choice("captions.window.all", isOn: window == nil) {
                        window = nil
                    }
                    choice("captions.window.between", isOn: window != nil) {
                        if window == nil {
                            window = MediaTimeRange(start: .zero, duration: MediaTime(seconds: max(0.5, duration)))
                        }
                    }
                }
            }

            if let current = window {
                HStack(spacing: 8) {
                    stepper("captions.window.from", value: current.start.seconds) { delta in
                        let end = current.end.seconds
                        let start = min(max(0, current.start.seconds + delta), end - 0.5)
                        window = MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: end - start))
                    }
                    stepper("captions.window.to", value: current.end.seconds) { delta in
                        let end = min(max(current.start.seconds + 0.5, current.end.seconds + delta), max(duration, current.start.seconds + 0.5))
                        window = MediaTimeRange(start: current.start, duration: MediaTime(seconds: end - current.start.seconds))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .dsGlass(
            tint: DS.Palette.glassSheet(0.9),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous),
            border: DS.Palette.hairline(0.1)
        )
        .animation(DS.Motion.settle, value: window == nil)
    }

    private func choice(_ key: String.LocalizationValue, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(AppLocalization.string(key, bundle: .module))
                .dsFont(.sans, .medium, 11)
                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07)))
        }
        .buttonStyle(.dsPress(radius: 20))
    }

    private func stepper(_ key: String.LocalizationValue, value: Double, onStep: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 0) {
            button("minus") { onStep(-0.5) }
            VStack(spacing: 1) {
                Text(AppLocalization.string(key, bundle: .module))
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.56))
                Text(verbatim: MediaTime(seconds: value).preciseTimecode)
                    .dsFont(.mono, .medium, 13)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText(value: value))
            }
            .frame(maxWidth: .infinity)
            button("plus") { onStep(0.5) }
        }
        .padding(4)
        .background(Capsule().fill(DS.Palette.hairline(0.06)))
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .dsActionName(symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(DS.Palette.hairline(0.08)))
        }
        .buttonRepeatBehavior(.enabled)
        .buttonStyle(.dsPressIcon)
    }
}
