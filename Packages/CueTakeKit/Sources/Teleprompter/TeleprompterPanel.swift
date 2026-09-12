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
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(DS.Palette.screen.opacity(model.panelFillOpacity))
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Palette.hairline(model.isDragging ? 0.34 : 0.12), lineWidth: 1)
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
        .overlay(alignment: .top) { readout }
        .shadow(
            color: .black.opacity(0.5),
            radius: model.isDragging ? 35 : 20,
            y: model.isDragging ? 30 : 16
        )
        // Picked up rather than merely followed: a hair of scale is what separates dragging an
        // object from scrubbing a value, and it is the whole difference in how the panel reads.
        .scaleEffect(model.isDragging && !reduceMotion ? 1.02 : 1)
        .studioMotion(StudioMotion.settle, reduced: reduceMotion, value: model.isDragging)
        .position(x: rect.midX, y: rect.midY)
        .animation(model.isDragging ? nil : DS.Easing.standard(0.5), value: model.frame)
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

            Spacer(minLength: 0)

            // Holding a line while you ad-lib, then picking it up again, is the single most
            // common thing a reader needs mid-take and the one no competitor puts within reach.
            Button {
                model.togglePause()
            } label: {
                Text(model.isPaused ? "▶" : "❚❚")
                    .dsFont(.sans, .semibold, 9)
                    .foregroundStyle(model.isPaused ? DS.Palette.inkInverse : DS.Palette.ink)
                    .contentTransition(.opacity)
                    .animation(StudioMotion.snap, value: model.isPaused)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(model.isPaused ? DS.Palette.lime : DS.Palette.hairline(0.1))
                    )
            }
            .buttonStyle(.dsPress)

            Button {
                model.cyclePreset()
            } label: {
                Text(model.preset.uppercasedLabel(locale: .current))
                    .dsFont(.mono, .medium, 9, letterSpacing: 0.08)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.opacity)
                    .animation(StudioMotion.snap, value: model.preset)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.Palette.hairline(0.1)))
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

    // MARK: - Script

    private var script: some View {
        VStack(alignment: model.alignment == .center ? .center : .leading, spacing: 8) {
            FlowLayout(
                horizontalSpacing: 0,
                verticalSpacing: 0,
                alignment: model.alignment == .center ? .center : .leading
            ) {
                ForEach(model.wordStyles(
                    accent: DS.Palette.accent,
                    ink: DS.Palette.ink,
                    inkInverse: DS.Palette.inkInverse,
                    lime: DS.Palette.lime
                )) { word in
                    Text(word.text + " ")
                        .dsFont(.sans, .medium, model.textSize, lineHeight: 1.45)
                        .foregroundStyle(word.color)
                        .padding(.horizontal, 2)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(word.background))
                        .opacity(word.opacity)
                        // The word under the voice is the one thing the eye tracks continuously,
                        // so it is the one thing allowed to move. Scale rather than colour: the
                        // highlight already carries colour, and a second colour cue would fight it.
                        .scaleEffect(word.isActive && !reduceMotion ? 1.07 : 1)
                        .animation(DS.Easing.ease(0.22), value: word.color)
                        .animation(DS.Easing.ease(0.22), value: word.opacity)
                        .animation(StudioMotion.bloom, value: word.isActive)
                }
            }
            .frame(maxWidth: .infinity, alignment: model.alignment == .center ? .center : .leading)

            if let next = model.nextSegment {
                Text(next.script)
                    .dsFont(.sans, .regular, max(11, model.textSize - 6), lineHeight: 1.4)
                    .foregroundStyle(DS.Palette.ink(0.26))
                    .multilineTextAlignment(model.alignment == .center ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: model.alignment == .center ? .center : .leading)
            }

            Spacer(minLength: 0)
        }
        .scaleEffect(x: model.isMirrored ? -1 : 1, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        // mask-image: linear-gradient(180deg, #000 78%, transparent)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.78),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
            .studioMotion(StudioMotion.snap, reduced: reduceMotion, value: isActive)
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
