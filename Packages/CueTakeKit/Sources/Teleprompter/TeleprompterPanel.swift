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
        .overlay(alignment: .bottomTrailing) { resizeHandle }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(
            color: .black.opacity(0.5),
            radius: model.isDragging ? 35 : 20,
            y: model.isDragging ? 30 : 16
        )
        .position(x: rect.midX, y: rect.midY)
        .animation(model.isDragging ? nil : DS.Easing.standard(0.5), value: model.frame)
        .gesture(moveGesture)
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

            Button {
                model.cyclePreset()
            } label: {
                Text(model.preset.uppercasedLabel(locale: .current))
                    .dsFont(.mono, .medium, 9, letterSpacing: 0.08)
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.Palette.hairline(0.1)))
            }
            .buttonStyle(.plain)

            Button {
                model.isSettingsOpen.toggle()
            } label: {
                Text("Aa")
                    .dsFont(.archivo, .semibold, 11)
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.Palette.hairline(0.1)))
            }
            .buttonStyle(.plain)
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
                        .animation(DS.Easing.ease(0.22), value: word.color)
                        .animation(DS.Easing.ease(0.22), value: word.opacity)
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
        ResizeChevron()
            .stroke(DS.Palette.ink(0.5), lineWidth: 2)
            .frame(width: 12, height: 12)
            .padding(5)
            .frame(width: 26, height: 26, alignment: .bottomTrailing)
            .contentShape(Rectangle())
            .gesture(resizeGesture)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                let origin = dragOrigin ?? model.frame
                if dragOrigin == nil {
                    dragOrigin = origin
                    model.isDragging = true
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
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                let origin = resizeOrigin ?? model.frame
                if resizeOrigin == nil {
                    resizeOrigin = origin
                    model.isDragging = true
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
