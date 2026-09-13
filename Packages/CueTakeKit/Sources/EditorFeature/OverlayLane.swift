import DesignSystem
import Domain
import SwiftUI

/// Pictures and text on the timeline, above the clips they sit over.
///
/// Same rules as the audio lanes: to scale, stacked into as many rows as overlaps need. Tap one to
/// select it; a selected one moves along the timeline with a drag and gets a handle at its end.
struct OverlayLane: View {
    @Bindable var model: EditorModel
    let scale: Double

    @State private var origin: (id: Overlay.ID, start: Double, duration: Double)?

    static let rowHeight: CGFloat = 24
    static let rowSpacing: CGFloat = 3

    static func rows(for overlays: [Overlay]) -> [Overlay.ID: Int] {
        var ends: [Double] = []
        var result: [Overlay.ID: Int] = [:]
        for overlay in overlays.sorted(by: { $0.start < $1.start }) {
            let start = overlay.start.seconds
            let end = start + overlay.duration.seconds
            if let row = ends.firstIndex(where: { $0 <= start + 0.01 }) {
                ends[row] = end
                result[overlay.id] = row
            } else {
                ends.append(end)
                result[overlay.id] = ends.count - 1
            }
        }
        return result
    }

    static func height(for overlays: [Overlay]) -> CGFloat {
        guard !overlays.isEmpty else { return 0 }
        let count = (rows(for: overlays).values.max() ?? 0) + 1
        return CGFloat(count) * rowHeight + CGFloat(count - 1) * rowSpacing
    }

    var body: some View {
        let placement = Self.rows(for: model.project.overlays)
        ZStack(alignment: .topLeading) {
            ForEach(model.project.overlays) { overlay in
                bar(overlay)
                    .frame(width: max(CGFloat(overlay.duration.seconds * scale) - 2, 16), height: Self.rowHeight)
                    .offset(
                        x: CGFloat(overlay.start.seconds * scale),
                        y: CGFloat(placement[overlay.id] ?? 0) * (Self.rowHeight + Self.rowSpacing)
                    )
                    .zIndex(model.selectedOverlay == overlay.id ? 1 : 0)
            }
        }
        .frame(height: Self.height(for: model.project.overlays), alignment: .topLeading)
        .animation(DS.Motion.settle, value: model.project.overlays.count)
    }

    private func bar(_ overlay: Overlay) -> some View {
        let selected = model.selectedOverlay == overlay.id
        let tint = overlay.isText ? DS.Palette.lime : DS.Palette.accentWarm

        return HStack(spacing: 5) {
            Image(systemName: overlay.isText ? "textformat" : "photo")
                .font(.system(size: 9, weight: .bold))
            Text(Self.label(for: overlay))
                .dsFont(.sans, .semibold, 10)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(DS.Palette.inkInverse)
        .padding(.horizontal, 7)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(selected ? 1 : 0.75)))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DS.Palette.ink, lineWidth: selected ? 2 : 0)
        }
        .overlay(alignment: .trailing) {
            if selected {
                Capsule()
                    .fill(DS.Palette.inkInverse)
                    .frame(width: 4, height: 14)
                    .padding(.trailing, 4)
                    .frame(width: 26, height: Self.rowHeight, alignment: .trailing)
                    .contentShape(Rectangle())
                    .gesture(endDrag(overlay))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture {
            withAnimation(DS.Motion.snap) {
                model.select(overlay: selected ? nil : overlay.id)
            }
        }
        .gesture(moveDrag(overlay), including: selected ? .all : .subviews)
    }

    private func moveDrag(_ overlay: Overlay) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let start = origin?.id == overlay.id ? origin!.start : overlay.start.seconds
                if origin?.id != overlay.id { origin = (overlay.id, overlay.start.seconds, overlay.duration.seconds) }
                model.updateOverlay(overlay.id, coalescing: "overlay-move") {
                    $0.start = MediaTime(seconds: max(0, start + Double(value.translation.width) / scale))
                }
            }
            .onEnded { _ in origin = nil }
    }

    private func endDrag(_ overlay: Overlay) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let duration = origin?.id == overlay.id ? origin!.duration : overlay.duration.seconds
                if origin?.id != overlay.id { origin = (overlay.id, overlay.start.seconds, overlay.duration.seconds) }
                model.updateOverlay(overlay.id, coalescing: "overlay-end") {
                    $0.duration = MediaTime(seconds: duration + Double(value.translation.width) / scale)
                }
            }
            .onEnded { _ in origin = nil }
    }

    static func label(for overlay: Overlay) -> String {
        switch overlay.content {
        case .text(let text): text.text
        case .image: String(localized: "editor.overlay.image", bundle: .module)
        }
    }
}
