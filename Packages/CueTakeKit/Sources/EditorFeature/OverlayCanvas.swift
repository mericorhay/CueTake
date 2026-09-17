import DesignSystem
import Domain
import SwiftUI
import UIKit

/// Pictures and text drawn over the preview, and moved with the fingers.
///
/// Laid out inside the video's own rectangle, not the preview box: the player letterboxes, and an
/// overlay placed against the box would land somewhere else in the exported frame. The selected
/// overlay takes three gestures at once — drag to move, pinch to size, twist to turn — which is
/// the whole vocabulary people already have for pictures on a phone. It clicks to the centre lines
/// with a tick, because "straight and centred" is what most placements are aiming for.
struct OverlayCanvas: View {
    @Bindable var model: EditorModel

    @State private var gestureOrigin: OverlayTransform?
    @State private var snapTick = 0
    /// How far the size handle was from the picture's centre when the finger landed.
    @State private var handleReach: CGFloat?
    @State private var guides: (vertical: Bool, horizontal: Bool) = (false, false)

    var body: some View {
        GeometryReader { proxy in
            let rect = Self.videoRect(in: proxy.size, render: model.project.format.renderSize)
            ZStack(alignment: .topLeading) {
                // A tap on the picture away from any overlay puts the selection down.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if model.selectedOverlay != nil {
                            withAnimation(DS.Motion.snap) { model.select(overlay: nil) }
                        }
                    }
                    .allowsHitTesting(model.selectedOverlay != nil)

                ForEach(model.project.overlays) { overlay in
                    let visible = overlay.isVisible(at: model.playhead)
                    let selected = model.selectedOverlay == overlay.id
                    if visible || selected {
                        item(overlay, in: rect, selected: selected, visible: visible)
                            .transition(Self.transition(for: overlay.animation))
                    }
                }

                // One finger sizes a picture, like the added videos: a pinch needs two fingers on
                // something that may be a thumbnail in the corner of the frame.
                if let selected = model.selectedOverlayValue, case .image(_, let aspect) = selected.content {
                    handle(selected, aspect: aspect, in: rect)
                }

                if guides.vertical {
                    Rectangle().fill(DS.Palette.lime.opacity(0.8))
                        .frame(width: 1, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
                if guides.horizontal {
                    Rectangle().fill(DS.Palette.lime.opacity(0.8))
                        .frame(width: rect.width, height: 1)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .sensoryFeedback(.selection, trigger: snapTick)
        .animation(DS.Motion.snap, value: model.overlaysVisible(at: model.playhead).map(\.id))
    }

    @ViewBuilder
    private func item(_ overlay: Overlay, in rect: CGRect, selected: Bool, visible: Bool) -> some View {
        let t = overlay.transform
        content(overlay, in: rect)
            // Before the turn, so the light turns with the overlay instead of framing its old box.
            .aiGlow(model.glowToken(.overlay(overlay.id)), in: RoundedRectangle(cornerRadius: 6, style: .continuous), inset: 6)
            .scaleEffect(x: t.flipX ? -1 : 1, y: t.flipY ? -1 : 1)
            .rotationEffect(.degrees(t.rotation))
            .opacity(t.opacity * (visible ? 1 : 0.35))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(DS.Palette.lime, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .rotationEffect(.degrees(t.rotation))
                        .padding(-4)
                        .allowsHitTesting(false)
                }
            }
            .position(x: rect.minX + rect.width * t.x, y: rect.minY + rect.height * t.y)
            .onTapGesture {
                withAnimation(DS.Motion.snap) { model.select(overlay: overlay.id) }
            }
            .gesture(selected ? transformGesture(for: overlay, in: rect) : nil)
    }

    /// The size handle, on the picture's lower corner wherever the picture has been turned to.
    private func handle(_ overlay: Overlay, aspect: Double, in rect: CGRect) -> some View {
        let t = overlay.transform
        let width = rect.width * t.imageWidthFraction
        let height = width / max(aspect, 0.01)
        let centre = CGPoint(x: rect.minX + rect.width * t.x, y: rect.minY + rect.height * t.y)
        let angle = t.rotation * .pi / 180
        let dx = width / 2
        let dy = height / 2
        let corner = CGPoint(
            x: centre.x + dx * cos(angle) - dy * sin(angle),
            y: centre.y + dx * sin(angle) + dy * cos(angle)
        )
        return Circle()
            .fill(DS.Palette.lime)
            .overlay(Circle().stroke(DS.Palette.inkInverse, lineWidth: 2))
            .frame(width: 16, height: 16)
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
            .position(corner)
            .gesture(cornerDrag(overlay, centre: centre, reach: hypot(dx, dy)))
    }

    private func cornerDrag(_ overlay: Overlay, centre: CGPoint, reach: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if gestureOrigin == nil {
                    gestureOrigin = overlay.transform
                    // The reach is taken once: the picture grows as it is dragged, and measuring
                    // against the grown picture would make it run away from the finger.
                    handleReach = reach
                    model.pause()
                }
                guard let origin = gestureOrigin, let from = handleReach, from > 1 else { return }
                let now = hypot(value.location.x - centre.x, value.location.y - centre.y)
                let scale = origin.scale * Double(now / from)
                model.updateOverlay(overlay.id, coalescing: "overlay-gesture") {
                    $0.transform.scale = min(
                        max(scale, OverlayTransform.scaleRange.lowerBound),
                        OverlayTransform.scaleRange.upperBound
                    )
                }
            }
            .onEnded { _ in
                gestureOrigin = nil
                handleReach = nil
                snapTick += 1
            }
    }

    @ViewBuilder
    private func content(_ overlay: Overlay, in rect: CGRect) -> some View {
        let t = overlay.transform
        switch overlay.content {
        case .image(_, let aspect):
            let width = rect.width * t.imageWidthFraction
            if let image = model.overlayImages[overlay.id] {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: width, height: width / max(aspect, 0.01))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(DS.Palette.hairline(0.2))
                    .frame(width: width, height: width / max(aspect, 0.01))
                    .onAppear { model.loadOverlayImages() }
            }
        case .text(let text):
            let size = max(8, rect.height * t.textSizeFraction)
            OverlayTextView(text: text, size: size, maxWidth: rect.width * 0.92)
        }
    }

    /// Move, pinch and twist together, from where the overlay was when the fingers landed.
    private func transformGesture(for overlay: Overlay, in rect: CGRect) -> some Gesture {
        let drag = DragGesture(minimumDistance: 1)
        let pinch = MagnifyGesture()
        let twist = RotateGesture()

        return drag.simultaneously(with: pinch.simultaneously(with: twist))
            .onChanged { value in
                let origin = gestureOrigin ?? overlay.transform
                if gestureOrigin == nil { gestureOrigin = origin }

                model.updateOverlay(overlay.id, coalescing: "overlay-gesture") { current in
                    if let translation = value.first?.translation {
                        var x = origin.x + translation.width / max(rect.width, 1)
                        var y = origin.y + translation.height / max(rect.height, 1)
                        let snapX = abs(x - 0.5) < 0.02
                        let snapY = abs(y - 0.5) < 0.02
                        if snapX { x = 0.5 }
                        if snapY { y = 0.5 }
                        if snapX != guides.vertical || snapY != guides.horizontal {
                            if snapX || snapY { snapTick += 1 }
                            guides = (snapX, snapY)
                        }
                        current.transform.x = x
                        current.transform.y = y
                    }
                    if let magnification = value.second?.first?.magnification {
                        current.transform.scale = origin.scale * magnification
                    }
                    if let rotation = value.second?.second?.rotation {
                        var degrees = origin.rotation + rotation.degrees
                        // Straight is sticky: within three degrees of a right angle it clicks to it.
                        let nearest = (degrees / 90).rounded() * 90
                        if abs(degrees - nearest) < 3 { degrees = nearest }
                        current.transform.rotation = degrees
                    }
                }
            }
            .onEnded { _ in
                gestureOrigin = nil
                guides = (false, false)
            }
    }

    static func videoRect(in container: CGSize, render: PixelSize) -> CGRect {
        let aspect = CGFloat(render.width) / CGFloat(max(1, render.height))
        guard container.width > 0, container.height > 0 else { return .zero }
        if container.width / container.height > aspect {
            let width = container.height * aspect
            return CGRect(x: (container.width - width) / 2, y: 0, width: width, height: container.height)
        } else {
            let height = container.width / aspect
            return CGRect(x: 0, y: (container.height - height) / 2, width: container.width, height: height)
        }
    }

    static func transition(for animation: OverlayAnimation) -> AnyTransition {
        switch animation {
        case .none: .identity
        case .fade: .opacity
        case .pop: .scale(scale: 0.6).combined(with: .opacity)
        case .slideUp: .move(edge: .bottom).combined(with: .opacity)
        }
    }
}

/// A text overlay as it will be burned in: the face, the colour, an outline or a plate.
struct OverlayTextView: View {
    let text: OverlayText
    let size: CGFloat
    let maxWidth: CGFloat

    var body: some View {
        Text(text.text.isEmpty ? " " : text.text)
            .font(.custom(text.fontName, fixedSize: size))
            .foregroundStyle(CaptionOverlay.color(text.color))
            .multilineTextAlignment(.center)
            .shadow(color: text.background == nil ? .black.opacity(0.9) : .clear, radius: 0.5, x: size * 0.04, y: size * 0.04)
            .shadow(color: text.background == nil ? .black.opacity(0.9) : .clear, radius: 0.5, x: -size * 0.04, y: -size * 0.04)
            .padding(.horizontal, text.background == nil ? 0 : size * 0.45)
            .padding(.vertical, text.background == nil ? 0 : size * 0.22)
            .background {
                if let background = text.background {
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .fill(CaptionOverlay.color(background))
                }
            }
            .frame(maxWidth: maxWidth)
            .fixedSize()
    }
}
