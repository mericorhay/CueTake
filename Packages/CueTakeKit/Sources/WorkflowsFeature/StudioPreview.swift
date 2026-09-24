import DesignSystem
import Domain
import SwiftUI
import UIKit

/// What the workflow's video will look like, and the place to set that look by hand.
///
/// A phone-shaped frame in the workflow's shape, over a frame of the first clip, with the caption
/// in its real preset running a sample sentence word by word. The caption is dragged to where it
/// should sit for the whole workflow and pinched to its size; the title is dragged the same way.
/// Filter, zoom, title and logo switch on from the row underneath and show on the frame at once.
///
/// Changes are kept when a finger lifts, not on every frame of a drag: each change to the
/// definition is a save.
struct StudioPreview: View {
    @Bindable var model: WorkflowStudioModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// While a finger is on the caption: where it is and how big, before they are kept.
    @State private var liveCaptionY: Double?
    @State private var liveCaptionScale: Double?
    @State private var liveTitleY: Double?
    @State private var snapped: Double?
    @State private var showsSafeZone = false

    private var style: WorkflowStyle { model.definition.style }

    /// Where the caption snaps: the three named places.
    private static let guides: [Double] = [0.2, 0.5, 0.72]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            canvas
                .frame(maxWidth: .infinity)
            toolRow
            if let filter = step(of: "filter"), filter.isEnabled, case .filter(let options) = filter.kind {
                lookRow(filter.id, options: options)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Text("studio.preview.hint", bundle: .module)
                .dsFont(.sans, .regular, 12)
                .foregroundStyle(DS.Palette.ink(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .dsCard(radius: DS.Radius.cardLarge)
        .animation(reduceMotion ? nil : DS.Motion.settle, value: model.definition.steps)
        .sensoryFeedback(.selection, trigger: snapped)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            DSKicker(AppLocalization.string("studio.preview", bundle: .module), size: 10, color: DS.Palette.ink(0.56))
            Text(verbatim: StudioStyleCard.aspectLabel(style.aspect) + " · " + style.resolution.label + " · \(style.frameRate) fps")
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.4))
            Spacer(minLength: 0)
            Button {
                withAnimation(DS.Motion.settle) { showsSafeZone.toggle() }
            } label: {
                Label {
                    Text("studio.preview.safeZone", bundle: .module)
                } icon: {
                    Image(systemName: showsSafeZone ? "rectangle.inset.filled.and.person.filled" : "rectangle.dashed")
                }
                .dsFont(.sans, .medium, 11)
                .foregroundStyle(showsSafeZone ? DS.Palette.inkInverse : DS.Palette.ink(0.7))
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(Capsule().fill(showsSafeZone ? DS.Palette.lime : DS.Palette.hairline(0.07)))
            }
            .buttonStyle(.dsPress(radius: 16))
            .accessibilityAddTraits(showsSafeZone ? .isSelected : [])
        }
    }

    // MARK: - The frame

    private var aspect: CGFloat {
        switch style.aspect {
        case .portrait9x16: 9.0 / 16.0
        case .landscape16x9: 16.0 / 9.0
        case .square1x1: 1
        case .portrait4x5: 4.0 / 5.0
        }
    }

    private var canvas: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 3600 : 0.38)) { context in
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    scene(size: size, at: context.date)
                    if showsSafeZone { safeZone(size: size) }
                    if let titleStep = step(of: "addTitle"), titleStep.isEnabled, case .addTitle(let options) = titleStep.kind {
                        title(titleStep.id, options: options, size: size)
                    }
                    if let brand = step(of: "brandKit"), brand.isEnabled, case .brandKit(let options) = brand.kind, options.logo {
                        logo(size: size)
                    }
                    if style.captions { caption(size: size, at: context.date) }
                    sectionChip(at: context.date)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(10)
                    timeline(at: context.date)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(DS.Palette.hairline(0.12), lineWidth: 1)
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxHeight: aspect < 1 ? 460 : 260)
        }
        .animation(reduceMotion ? nil : DS.Motion.settle, value: style.aspect)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("studio.preview", bundle: .module))
    }

    /// The first clip's frame, or a stand-in: a person-shaped light on a dark set.
    @ViewBuilder
    private func scene(size: CGSize, at date: Date) -> some View {
        let zoom = zoomAmount(at: date)
        ZStack {
            if let data = model.previewFrame, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
            } else {
                standIn(size: size)
            }
        }
        .scaleEffect(1 + zoom)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.1), value: zoom)
        .modifier(LookModifier(look: activeLook, intensity: activeLookIntensity))
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func standIn(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.15, blue: 0.2), Color(red: 0.05, green: 0.05, blue: 0.07)],
                startPoint: .top, endPoint: .bottom
            )
            Circle()
                .fill(RadialGradient(colors: [DS.Palette.accentWarm.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: size.width * 0.5))
                .frame(width: size.width, height: size.width)
                .offset(x: -size.width * 0.28, y: -size.height * 0.22)
            Circle()
                .fill(RadialGradient(colors: [DS.Palette.lime.opacity(0.14), .clear], center: .center, startRadius: 0, endRadius: size.width * 0.4))
                .frame(width: size.width * 0.8, height: size.width * 0.8)
                .offset(x: size.width * 0.32, y: -size.height * 0.05)
            Image(systemName: "person.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: min(size.width, size.height) * 0.62)
                .offset(y: size.height * 0.2)
        }
        .frame(width: size.width, height: size.height)
    }

    /// Where TikTok and Reels draw their own buttons and text: the right-hand column, the caption
    /// block at the bottom and the tabs at the top.
    private func safeZone(size: CGSize) -> some View {
        let shade = DS.Palette.accent.opacity(0.22)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(shade)
                .frame(width: size.width, height: size.height * 0.08)
            Rectangle().fill(shade)
                .frame(width: size.width * 0.16, height: size.height * 0.42)
                .offset(x: size.width * 0.84, y: size.height * 0.44)
            Rectangle().fill(shade)
                .frame(width: size.width, height: size.height * 0.16)
                .offset(y: size.height * 0.84)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: - Caption

    private var captionY: Double { liveCaptionY ?? style.position.y }
    private var captionScale: Double { liveCaptionScale ?? style.captionFontScale }

    /// Behind the platform's own buttons or text when the video is posted.
    private var captionIsHidden: Bool { captionY > 0.83 || captionY < 0.1 }

    private func caption(size: CGSize, at date: Date) -> some View {
        let captionStyle = CaptionStyle.preset(style.captionPreset, position: CaptionPosition(x: 0.5, y: captionY))
        let words = sampleWords
        let perCue = max(1, captionStyle.maxWordsPerCue)
        let tick = reduceMotion ? 0 : Int(date.timeIntervalSinceReferenceDate / 0.38)
        let spoken = tick % max(1, words.count)
        let cueStart = (spoken / perCue) * perCue
        let cue = Array(words[cueStart..<min(words.count, cueStart + perCue)])
        let fontSize = max(9, CGFloat(captionStyle.relativeFontSize * captionScale) * size.height)
        let dragging = liveCaptionY != nil || liveCaptionScale != nil

        return ZStack {
            if dragging {
                ForEach(Self.guides, id: \.self) { guide in
                    Rectangle()
                        .fill(DS.Palette.lime.opacity(snapped == guide ? 0.9 : 0.25))
                        .frame(height: 1)
                        .position(x: size.width / 2, y: size.height * CGFloat(guide))
                }
            }
            CaptionSample(style: captionStyle, words: cue, spokenIndex: spoken - cueStart, fontSize: fontSize)
                .frame(maxWidth: size.width * 0.86)
                .padding(8)
                .overlay {
                    if dragging || captionIsHidden {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(captionIsHidden ? DS.Palette.accent : DS.Palette.lime, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                }
                .contentShape(Rectangle())
                .position(x: size.width / 2, y: size.height * CGFloat(captionY))
                // Ahead of the scroll view, or a vertical drag on the caption scrolls the page.
                .highPriorityGesture(captionDrag(height: size.height).simultaneously(with: captionPinch))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("studio.preview.caption", bundle: .module))
                .accessibilityValue(Text(verbatim: "\(Int((captionY * 100).rounded()))%"))
                .accessibilityAdjustableAction { direction in
                    var y = style.position.y
                    y += direction == .increment ? 0.05 : -0.05
                    model.definition.style.placeCaption(y: y)
                }
            if captionIsHidden, !dragging {
                Label {
                    Text("studio.preview.hidden", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .dsFont(.sans, .semibold, 10)
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Capsule().fill(DS.Palette.accent))
                .position(x: size.width / 2, y: size.height * CGFloat(captionY > 0.5 ? captionY - 0.09 : captionY + 0.09))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func captionDrag(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = style.position.y
                var y = WorkflowStyle.clampedY(start + Double(value.translation.height / height))
                if let guide = Self.guides.first(where: { abs($0 - y) < 0.025 }) {
                    y = guide
                    if snapped != guide { snapped = guide }
                } else if snapped != nil {
                    snapped = nil
                }
                liveCaptionY = y
            }
            .onEnded { _ in
                if let y = liveCaptionY { model.definition.style.placeCaption(y: y) }
                liveCaptionY = nil
                snapped = nil
            }
    }

    private var captionPinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                liveCaptionScale = WorkflowStyle.clampedScale(style.captionFontScale * Double(value.magnification))
            }
            .onEnded { _ in
                if let scale = liveCaptionScale {
                    model.definition.style.captionScale = abs(scale - 1) < 0.04 ? nil : scale
                }
                liveCaptionScale = nil
            }
    }

    private var sampleWords: [String] {
        AppLocalization.string("studio.preview.sample", bundle: .module)
            .split(separator: " ").map(String.init)
    }

    // MARK: - Title, logo, sections

    private func title(_ id: WorkflowStep.ID, options: TitleStepOptions, size: CGSize) -> some View {
        let y = liveTitleY ?? options.y
        let text = options.text.isEmpty ? model.definition.name : options.text
        return Text(verbatim: text)
            .font(.custom("Archivo-ExtraBold", size: max(12, size.height * 0.03 * CGFloat(options.scale))))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .shadow(color: .black.opacity(0.55), radius: 6, y: 2)
            .frame(maxWidth: size.width * 0.84)
            .padding(6)
            .overlay {
                if liveTitleY != nil {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(DS.Palette.lime, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .contentShape(Rectangle())
            .position(x: size.width / 2, y: size.height * CGFloat(y))
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        liveTitleY = min(0.9, max(0.08, options.y + Double(value.translation.height / size.height)))
                    }
                    .onEnded { _ in
                        if let y = liveTitleY {
                            var changed = options
                            changed.y = y
                            model.updateStep(id, kind: .addTitle(changed))
                        }
                        liveTitleY = nil
                    }
            )
            .accessibilityLabel(Text("tool.addTitle", bundle: .module))
    }

    private func logo(size: CGSize) -> some View {
        Circle()
            .fill(DS.Palette.ink(0.9))
            .overlay {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Palette.inkInverse)
            }
            .frame(width: 26, height: 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(12)
            .allowsHitTesting(false)
    }

    /// The section on screen now, as the sample plays through the structure.
    private func sectionChip(at date: Date) -> some View {
        Group {
            if let section = currentSection(at: date).section {
                Text(verbatim: StudioCatalog.roleLabel(section.role))
                    .dsFont(.mono, .semibold, 9, letterSpacing: 0.1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Capsule().fill(StudioCatalog.roleTint(section.role).opacity(0.85)))
                    .contentTransition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    /// The structure as a bar, a light running along it.
    private func timeline(at date: Date) -> some View {
        let sections = model.definition.sections
        let now = currentSection(at: date).progress
        return GeometryReader { geometry in
            let total = max(1, sections.reduce(0) { $0 + max(1, $1.seconds) })
            HStack(spacing: 2) {
                ForEach(sections) { section in
                    Capsule()
                        .fill(StudioCatalog.roleTint(section.role).opacity(0.75))
                        .frame(width: max(4, (geometry.size.width - CGFloat(sections.count) * 2) * CGFloat(max(1, section.seconds) / total)))
                }
            }
            .overlay(alignment: .leading) {
                Capsule().fill(.white)
                    .frame(width: 3, height: 9)
                    .offset(x: geometry.size.width * CGFloat(now) - 1.5)
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .opacity(sections.isEmpty ? 0 : 1)
        .allowsHitTesting(false)
    }

    private func currentSection(at date: Date) -> (section: WorkflowSection?, progress: Double) {
        let sections = model.definition.sections
        guard !sections.isEmpty else { return (nil, 0) }
        let lengths = sections.map { max(1, $0.seconds) }
        let total = lengths.reduce(0, +)
        // The sample runs the structure in a loop, faster than real time: a 40-second outline
        // goes round in about ten.
        let t = reduceMotion ? 0 : (date.timeIntervalSinceReferenceDate * total / 10).truncatingRemainder(dividingBy: total)
        var start = 0.0
        for (index, length) in lengths.enumerated() {
            if t < start + length { return (sections[index], t / total) }
            start += length
        }
        return (sections.last, 1)
    }

    // MARK: - Look

    private var activeLook: String? {
        guard let step = step(of: "filter"), step.isEnabled, case .filter(let options) = step.kind else { return nil }
        return options.look
    }

    private var activeLookIntensity: Double {
        guard let step = step(of: "filter"), case .filter(let options) = step.kind else { return 0 }
        return options.intensity
    }

    /// A zoom step pushes in and out on the sample's rhythm.
    private func zoomAmount(at date: Date) -> CGFloat {
        guard !reduceMotion, let step = step(of: "autoZoom"), step.isEnabled, case .autoZoom(let options) = step.kind else { return 0 }
        let beat = Int(date.timeIntervalSinceReferenceDate / 2.2) % 2
        return beat == 0 ? 0 : CGFloat(options.amount)
    }

    // MARK: - Tools under the frame

    private struct QuickTool {
        var type: String
        var title: String.LocalizationValue
    }

    /// The look tools that show on the frame, switched from under it.
    private static let quickTools = [
        QuickTool(type: "filter", title: "tool.filter"),
        QuickTool(type: "addTitle", title: "tool.addTitle"),
        QuickTool(type: "autoZoom", title: "tool.autoZoom"),
        QuickTool(type: "brandKit", title: "tool.brandKit"),
    ]

    private var toolRow: some View {
        HStack(spacing: 6) {
            captionToggle
            ForEach(Self.quickTools, id: \.type) { tool in
                let current = step(of: tool.type)
                let isOn = current?.isEnabled == true
                Button {
                    if let current { model.toggleStep(current.id) } else { model.addStep(type: tool.type) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: StudioCatalog.tool(for: tool.type).symbol)
                            .font(.system(size: 14, weight: .semibold))
                        Text(AppLocalization.string(tool.title, bundle: .module))
                            .dsFont(.sans, .medium, 10)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.7))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isOn ? DS.Palette.lime : DS.Palette.hairline(0.06))
                    )
                }
                .buttonStyle(.dsPress(radius: 12))
                .disabled(model.isRunning)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private var captionToggle: some View {
        let isOn = style.captions
        return Button {
            model.definition.style.captions.toggle()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 14, weight: .semibold))
                Text("studio.style.captions", bundle: .module)
                    .dsFont(.sans, .medium, 10)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.7))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? DS.Palette.lime : DS.Palette.hairline(0.06))
            )
        }
        .buttonStyle(.dsPress(radius: 12))
        .disabled(model.isRunning)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func lookRow(_ id: WorkflowStep.ID, options: FilterStepOptions) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(FilterSettings.Look.allCases.filter { $0 != .natural }, id: \.self) { look in
                    let isOn = options.look == look.rawValue
                    Button {
                        var changed = options
                        changed.look = look.rawValue
                        model.updateStep(id, kind: .filter(changed))
                    } label: {
                        Text(AppLocalization.string(String.LocalizationValue(stringLiteral: "studio.look." + look.rawValue), bundle: .module))
                            .dsFont(.mono, .medium, 11)
                            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.65))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.06)))
                    }
                    .buttonStyle(.dsPress(radius: 17))
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    /// The first step of a type, on or off.
    private func step(of type: String) -> WorkflowStep? {
        model.definition.steps.first { $0.kind.typeName == type }
    }
}

/// One cue of the sample sentence in a preset's own face, size, colours and plate, the word being
/// said lit the way the preset lights it.
private struct CaptionSample: View {
    let style: CaptionStyle
    let words: [String]
    let spokenIndex: Int
    let fontSize: CGFloat

    var body: some View {
        let locale = AppLocalization.locale
        let plated = style.backgroundColor != nil
        var line = AttributedString()
        for (index, word) in words.enumerated() {
            var part = AttributedString(style.textCase.apply(to: word, locale: locale) + (index < words.count - 1 ? " " : ""))
            let isNumber = word.contains { $0.isNumber }
            if index == spokenIndex, let highlight = style.highlightColor {
                part.foregroundColor = highlight.swiftUI
            } else if isNumber, let keyword = style.keywordColor {
                part.foregroundColor = keyword.swiftUI
            } else {
                part.foregroundColor = style.textColor.swiftUI
            }
            line += part
        }
        return Text(line)
            .font(font)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.6)
            .shadow(color: plated ? .clear : (style.strokeColor?.swiftUI ?? .black).opacity(0.95), radius: 0, x: 1.2, y: 1.2)
            .shadow(color: plated ? .clear : (style.strokeColor?.swiftUI ?? .black).opacity(0.95), radius: 0, x: -1, y: -1)
            .shadow(color: style.shadow == true ? .black.opacity(0.5) : .clear, radius: 6, y: 3)
            .padding(.horizontal, plated ? fontSize * 0.45 : 0)
            .padding(.vertical, plated ? fontSize * 0.22 : 0)
            .background {
                if let plate = style.backgroundColor {
                    RoundedRectangle(cornerRadius: fontSize * 0.28, style: .continuous).fill(plate.swiftUI)
                }
            }
    }

    private var font: Font {
        if let name = style.fontName { return .custom(name, size: fontSize) }
        return .system(size: fontSize, weight: .bold)
    }
}

/// A filter's look, roughly, on the preview: enough to tell cinematic from noir at a glance.
private struct LookModifier: ViewModifier {
    let look: String?
    let intensity: Double

    func body(content: Content) -> some View {
        let k = min(1, max(0, intensity))
        switch FilterSettings.Look(rawValue: look ?? "") {
        case .mono, .noir:
            content.saturation(1 - k).contrast(look == "noir" ? 1 + 0.35 * k : 1)
        case .warm, .instant:
            content.colorMultiply(Color(red: 1, green: 1 - 0.08 * k, blue: 1 - 0.22 * k))
        case .cool, .chrome:
            content.colorMultiply(Color(red: 1 - 0.18 * k, green: 1 - 0.04 * k, blue: 1))
        case .cinematic:
            content.contrast(1 + 0.15 * k).saturation(1 - 0.15 * k)
                .colorMultiply(Color(red: 1, green: 1 - 0.05 * k, blue: 1 - 0.12 * k))
        case .vintage, .fade:
            content.saturation(1 - 0.35 * k).contrast(1 - 0.18 * k)
                .colorMultiply(Color(red: 1, green: 0.96, blue: 1 - 0.18 * k))
        case .vivid:
            content.saturation(1 + 0.45 * k)
        case .dramatic:
            content.contrast(1 + 0.3 * k).saturation(1 - 0.2 * k)
        case .natural, .none:
            content
        }
    }
}

private extension RGBAColor {
    var swiftUI: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }
}
