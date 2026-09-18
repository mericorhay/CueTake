import DesignSystem
import Domain
import SwiftUI

/// The floating prompter over the camera: draggable, resizable, with per-word highlighting.
///
/// Geometry comes from `TeleprompterModel.frame`, in percent of `frameSize`, exactly as the design
/// positions it with `left/top/width/height` percentages.
public struct TeleprompterPanel: View {
    private let model: TeleprompterModel
    private let frameSize: CGSize
    private let segmentColor: Color

    @State private var dragOrigin: TeleprompterModel.Frame?
    @State private var resizeOrigin: TeleprompterModel.Frame?
    @State private var textSizeOrigin: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the reader is changing right now, so the panel can say so.
    @State private var adjustment: Adjustment?

    private enum Adjustment { case move, resize, text }

    public init(model: TeleprompterModel, frameSize: CGSize, segmentColor: Color = DS.Palette.accent) {
        self.model = model
        self.frameSize = frameSize
        self.segmentColor = segmentColor
    }

    public var body: some View {
        let rect = CGRect(
            x: frameSize.width * model.frame.x / 100,
            y: frameSize.height * model.frame.y / 100,
            width: frameSize.width * model.frame.width / 100,
            height: frameSize.height * model.frame.height / 100
        )

        VStack(alignment: .leading, spacing: 0) {
            header
            script
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .background {
            if model.showsBackdrop {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(DS.Palette.screen.opacity(model.panelFillOpacity))
                    )
            } else if model.isDragging {
                // Nothing behind the words, except while it is held: then its edge, so the reader
                // can see what they are moving.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.black.opacity(0.18))
            }
        }
        .overlay {
            if model.showsBackdrop || model.isDragging {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(DS.Palette.hairline(model.isDragging ? 0.34 : 0.12), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        // The hit area is the panel itself. The gestures used to sit outside `.position`, which
        // wraps the panel in a view the size of the whole screen — so what the reader was actually
        // dragging was never the rectangle they could see.
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .gesture(moveGesture)
        .simultaneousGesture(textSizeGesture)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { model.cyclePreset() }
        )
        // Added after the gestures so the corner wins the touch it is under.
        .overlay(alignment: .bottomTrailing) { resizeHandle }
        .overlay(alignment: .top) { progressLine.padding(.top, 1) }
        .overlay(alignment: .top) { readout }
        .shadow(
            color: .black.opacity(model.showsBackdrop ? 0.5 : 0),
            radius: model.isDragging ? 35 : 20,
            y: model.isDragging ? 30 : 16
        )
        // Picked up rather than merely followed: a hair of scale is what separates dragging an
        // object from scrubbing a value, and it is the whole difference in how the panel reads.
        .scaleEffect(model.isDragging && !reduceMotion ? 1.02 : 1)
        .dsMotion(DS.Motion.settle, reduced: reduceMotion, value: model.isDragging)
        .position(x: rect.midX, y: rect.midY)
        .animation(model.isDragging ? nil : DS.Easing.standard(0.5), value: model.frame)
        // Kept for the next take and the next launch, once a drag has let go.
        .onChange(of: model.preferences) { _, _ in model.save() }
        .onChange(of: model.isDragging) { _, dragging in
            if !dragging { model.save() }
        }
    }

    /// Says what is happening while it happens, then gets out of the way. Direct manipulation on a
    /// surface with no rulers needs a number, or the reader is guessing.
    @ViewBuilder
    private var readout: some View {
        if let adjustment {
            Text(readoutText(adjustment))
                .dsFont(.mono, .medium, 10, letterSpacing: 0.08)
                .foregroundStyle(DS.Palette.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(DS.Palette.inkInverse(0.72)))
                .offset(y: -13)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
        }
    }

    private func readoutText(_ adjustment: Adjustment) -> String {
        switch adjustment {
        case .text: "\(Int(model.textSize.rounded()))pt"
        case .move: "\(Int(model.frame.x.rounded()))% · \(Int(model.frame.y.rounded()))%"
        case .resize: "\(Int(model.frame.width.rounded()))% × \(Int(model.frame.height.rounded()))%"
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(DS.Palette.ink(0.35))
                .frame(width: 22, height: 3)

            DSKicker(
                model.currentSegment?.role.displayLabel ?? "",
                size: 9,
                color: segmentColor
            )

            status

            Spacer(minLength: 0)

            // Speed and size within reach during the take: the voice sets the pace, the reader
            // can still hurry it or hold it back, and make the words bigger without a sheet.
            // A narrow panel leaves them to the sheet and the pinch rather than overflow.
            if frameSize.width * model.frame.width / 100 >= 280 {
                stepper(
                    label: model.speedLabel,
                    less: String(localized: "teleprompter.speed.slower", bundle: .module),
                    more: String(localized: "teleprompter.speed.faster", bundle: .module)
                ) { model.nudgeSpeed($0) }

                stepper(
                    label: "A",
                    less: String(localized: "teleprompter.size.smaller", bundle: .module),
                    more: String(localized: "teleprompter.size.bigger", bundle: .module)
                ) { model.nudgeTextSize($0) }
            }

            // Holding a line while you ad-lib, then picking it up again, is the single most
            // common thing a reader needs mid-take and the one no competitor puts within reach.
            Button {
                model.togglePause()
            } label: {
                Text(model.isPaused ? "▶" : "❚❚")
                    .dsFont(.sans, .semibold, 10)
                    .foregroundStyle(model.isPaused ? DS.Palette.inkInverse : DS.Palette.ink)
                    .contentTransition(.opacity)
                    .animation(DS.Motion.snap, value: model.isPaused)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(model.isPaused ? DS.Palette.lime : DS.Palette.hairline(0.1))
                    )
            }
            .buttonStyle(.dsPress)

            Button {
                model.isSettingsOpen.toggle()
            } label: {
                Text("Aa")
                    .dsFont(.archivo, .semibold, 11)
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.Palette.hairline(0.1)))
            }
            .buttonStyle(.dsPress)
        }
        .padding(.bottom, 8)
    }

    /// A value with a step down and a step up, compact enough for the header.
    private func stepper(label: String, less: String, more: String, step: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 0) {
            Button { step(-1) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonRepeatBehavior(.enabled)
            .accessibilityLabel(Text(verbatim: less))
            Text(verbatim: label)
                .dsFont(.mono, .medium, 10)
                .contentTransition(.numericText())
                .frame(minWidth: 24)
            Button { step(1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonRepeatBehavior(.enabled)
            .accessibilityLabel(Text(verbatim: more))
        }
        .foregroundStyle(DS.Palette.ink)
        .buttonStyle(.dsPress)
        .background(Capsule().fill(.black.opacity(model.showsBackdrop ? 0 : 0.35)))
        .background(Capsule().fill(DS.Palette.hairline(0.1)))
        .sensoryFeedback(.selection, trigger: label)
    }

    // MARK: - Script

    private var script: some View {
        PrompterScript(
            words: model.wordStyles(
                accent: DS.Palette.accent,
                ink: DS.Palette.ink,
                inkInverse: DS.Palette.inkInverse,
                lime: DS.Palette.lime
            ),
            activeIndex: model.activeWordIndex,
            textSize: model.textSize,
            isCentered: model.alignment == .center,
            readingLine: model.readingLine,
            isMirrored: model.isMirrored,
            notes: model.currentSegment?.teleprompter.speakerNotes,
            upNext: model.nextSegment?.script,
            lineColor: segmentColor
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        // Floating over the picture, the words carry their own shade: a tight dark edge and a
        // soft one, so white text reads on a white wall.
        .shadow(color: .black.opacity(model.showsBackdrop ? 0 : 0.9), radius: 1.5)
        .shadow(color: .black.opacity(model.showsBackdrop ? 0 : 0.55), radius: 6)
    }

    /// How far through the script, and how the reading is going: time left and the pace, coloured
    /// only when it is worth a glance.
    @ViewBuilder
    private var status: some View {
        if model.remaining != nil || model.paceVerdict != nil {
            HStack(spacing: 6) {
                if let remaining = model.remaining {
                    Text(ScriptTiming.label(remaining))
                        .dsFont(.mono, .medium, 10, letterSpacing: 0.04)
                        .foregroundStyle(DS.Palette.ink(0.55))
                        .contentTransition(.numericText())
                }
                if let verdict = model.paceVerdict, let pace = model.pace {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Self.paceColor(verdict))
                            .frame(width: 5, height: 5)
                        Text(Self.paceText(verdict, pace: pace))
                            .dsFont(.mono, .medium, 10, letterSpacing: 0.04)
                    }
                    .foregroundStyle(verdict == .good ? DS.Palette.ink(0.55) : Self.paceColor(verdict))
                    .transition(.opacity)
                }
            }
            .lineLimit(1)
            .layoutPriority(-1)
        }
    }

    static func paceColor(_ verdict: PaceMeter.Verdict) -> Color {
        switch verdict {
        case .good: DS.Palette.lime
        case .fast: DS.Palette.accent
        case .slow: DS.Palette.accentWarm
        }
    }

    static func paceText(_ verdict: PaceMeter.Verdict, pace: Double) -> String {
        let words = Int(pace.rounded())
        switch verdict {
        case .good: return String(localized: "teleprompter.pace.good \(words)", bundle: .module)
        case .fast: return String(localized: "teleprompter.pace.fast \(words)", bundle: .module)
        case .slow: return String(localized: "teleprompter.pace.slow \(words)", bundle: .module)
        }
    }

    /// A hairline along the top edge that fills as the script is read.
    private var progressLine: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(segmentColor.opacity(0.9))
                .frame(width: proxy.size.width * min(1, max(0, model.progress)), height: 2)
                .animation(DS.Easing.ease(0.4), value: model.progress)
        }
        .frame(height: 2)
        .padding(.horizontal, 18)
        .opacity(model.progress > 0 ? 1 : 0)
    }

    // MARK: - Handles

    private var resizeHandle: some View {
        let isActive = adjustment == .resize
        return ResizeChevron()
            .stroke(isActive ? DS.Palette.accent : DS.Palette.ink(0.5), lineWidth: 2)
            .frame(width: isActive ? 15 : 12, height: isActive ? 15 : 12)
            .padding(5)
            .frame(width: 26, height: 26, alignment: .bottomTrailing)
            .contentShape(Rectangle())
            .dsMotion(DS.Motion.snap, reduced: reduceMotion, value: isActive)
            .gesture(resizeGesture)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                let origin = dragOrigin ?? model.frame
                if dragOrigin == nil {
                    dragOrigin = origin
                    model.isDragging = true
                    adjustment = .move
                }
                model.move(
                    byX: gesture.translation.width / frameSize.width * 100,
                    y: gesture.translation.height / frameSize.height * 100,
                    from: origin
                )
            }
            .onEnded { _ in
                dragOrigin = nil
                model.isDragging = false
                adjustment = nil
            }
    }

    /// Pinch anywhere on the panel to size the script. The competitors that offer this at all bury
    /// it in a settings sheet; it belongs under the fingers that are already holding the phone.
    private var textSizeGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { gesture in
                let origin = textSizeOrigin ?? model.textSize
                if textSizeOrigin == nil {
                    textSizeOrigin = origin
                    adjustment = .text
                }
                model.setTextSize(origin * gesture.magnification)
            }
            .onEnded { _ in
                textSizeOrigin = nil
                adjustment = nil
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                let origin = resizeOrigin ?? model.frame
                if resizeOrigin == nil {
                    resizeOrigin = origin
                    model.isDragging = true
                    adjustment = .resize
                }
                model.resize(
                    byX: gesture.translation.width / frameSize.width * 100,
                    y: gesture.translation.height / frameSize.height * 100,
                    from: origin
                )
            }
            .onEnded { _ in
                resizeOrigin = nil
                model.isDragging = false
                adjustment = nil
            }
    }
}

/// The corner glyph: a right and bottom edge with a small rounded join.
private struct ResizeChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 3))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 3, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}
