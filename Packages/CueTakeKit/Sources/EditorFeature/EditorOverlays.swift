import Domain
import Foundation
import UIKit

/// Pictures and text over the video: adding them, moving them in time and on the frame.
extension EditorModel {
    public var selectedOverlayValue: Overlay? {
        selectedOverlay.flatMap { id in project.overlays.first { $0.id == id } }
    }

    public func overlaysVisible(at seconds: Double) -> [Overlay] {
        project.overlays(at: seconds)
    }

    /// Adds a picture at the playhead, centred, three seconds long, and selects it.
    ///
    /// The file is redrawn upright before it is stored. Photos carry their rotation as a flag, and
    /// the exporter's image loader ignores it — a portrait photo would otherwise come out sideways.
    /// The long edge is capped at 2400 points: bigger than any overlay needs at 4K, and a 48 MP
    /// photo would otherwise sit in memory for the whole edit.
    @discardableResult
    public func addImageOverlay(from data: Data) -> Bool {
        guard let mediaDirectory, let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else {
            return false
        }
        let longest = max(source.size.width, source.size.height)
        let factor = min(1, 2400 / longest)
        let size = CGSize(width: (source.size.width * factor).rounded(), height: (source.size.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let png = upright.pngData() else { return false }

        let name = "overlay-\(UUID().uuidString).png"
        let url = mediaDirectory.appending(path: name, directoryHint: .notDirectory)
        guard (try? png.write(to: url, options: .atomic)) != nil else { return false }

        let overlay = Overlay(
            content: .image(relativePath: "media/\(name)", aspect: Double(size.width / size.height)),
            start: MediaTime(seconds: playhead)
        )
        record("editor.change.overlayAdd", symbol: "photo")
        project.overlays.append(overlay)
        overlayImages[overlay.id] = upright
        select(overlay: overlay.id)
        project.updatedAt = .now
        return true
    }

    /// Adds a line of text at the playhead and selects it.
    public func addTextOverlay(_ text: String? = nil) {
        let overlay = Overlay(
            content: .text(OverlayText(text: text ?? String(localized: "editor.overlay.defaultText", bundle: .module))),
            start: MediaTime(seconds: playhead),
            transform: OverlayTransform(y: 0.3)
        )
        record("editor.change.overlayAdd", symbol: "textformat")
        project.overlays.append(overlay)
        select(overlay: overlay.id)
        project.updatedAt = .now
    }

    public func select(overlay id: Overlay.ID?) {
        selectedOverlay = id
        if id != nil {
            selectedCameraMotion = nil
            selectedSubjectTrack = nil
            inspectedSegment = nil
            selectedAudio = nil
            selectedEffect = nil
        }
    }

    /// Every overlay edit passes through here: one place for history, limits and `updatedAt`.
    public func updateOverlay(_ id: Overlay.ID, coalescing key: String = "overlay", _ change: (inout Overlay) -> Void) {
        guard let index = project.overlays.firstIndex(where: { $0.id == id }) else { return }
        record("editor.change.overlayAdjust", symbol: "slider.horizontal.3", coalescing: "\(key)-\(id)")
        change(&project.overlays[index])
        var overlay = project.overlays[index]
        overlay.start = MediaTime(seconds: max(0, overlay.start.seconds))
        overlay.duration = MediaTime(seconds: max(Overlay.shortest, overlay.duration.seconds))
        overlay.transform.scale = min(max(overlay.transform.scale, OverlayTransform.scaleRange.lowerBound), OverlayTransform.scaleRange.upperBound)
        overlay.transform.opacity = min(max(overlay.transform.opacity, 0.05), 1)
        overlay.transform.x = min(max(overlay.transform.x, -0.2), 1.2)
        overlay.transform.y = min(max(overlay.transform.y, -0.2), 1.2)
        project.overlays[index] = overlay
        project.updatedAt = .now
    }

    /// Starts the overlay at the playhead, keeping where it ends when that still leaves it on screen.
    public func startOverlayAtPlayhead(_ id: Overlay.ID) {
        guard let overlay = project.overlays.first(where: { $0.id == id }) else { return }
        let end = overlay.start.seconds + overlay.duration.seconds
        updateOverlay(id, coalescing: "overlay-start") {
            $0.start = MediaTime(seconds: playhead)
            $0.duration = MediaTime(seconds: end > playhead + Overlay.shortest ? end - playhead : overlay.duration.seconds)
        }
    }

    /// Ends the overlay at the playhead.
    public func endOverlayAtPlayhead(_ id: Overlay.ID) {
        guard let overlay = project.overlays.first(where: { $0.id == id }),
              playhead > overlay.start.seconds + Overlay.shortest
        else { return }
        updateOverlay(id, coalescing: "overlay-end") {
            $0.duration = MediaTime(seconds: playhead - overlay.start.seconds)
        }
    }

    public func removeOverlay(_ id: Overlay.ID) {
        guard project.overlays.contains(where: { $0.id == id }) else { return }
        record("editor.change.overlayRemove", symbol: "trash")
        project.overlays.removeAll { $0.id == id }
        if selectedOverlay == id { selectedOverlay = nil }
        project.updatedAt = .now
    }

    public func duplicateOverlay(_ id: Overlay.ID) {
        guard let original = project.overlays.first(where: { $0.id == id }) else { return }
        record("editor.change.overlayAdd", symbol: "plus.square.on.square")
        var copy = original
        copy.id = UUID()
        // Nudged so the copy is visibly a second one, not a stack of two.
        copy.transform.x = min(0.95, copy.transform.x + 0.06)
        copy.transform.y = min(0.95, copy.transform.y + 0.06)
        project.overlays.append(copy)
        if let image = overlayImages[original.id] { overlayImages[copy.id] = image }
        select(overlay: copy.id)
        project.updatedAt = .now
    }

    public func bringOverlayToFront(_ id: Overlay.ID) {
        guard let index = project.overlays.firstIndex(where: { $0.id == id }), index < project.overlays.count - 1 else { return }
        record("editor.change.overlayAdjust", symbol: "square.3.layers.3d.top.filled")
        let overlay = project.overlays.remove(at: index)
        project.overlays.append(overlay)
        project.updatedAt = .now
    }

    /// Reads every overlay picture that is not in memory yet.
    func loadOverlayImages() {
        guard let mediaDirectory else { return }
        for overlay in project.overlays where overlayImages[overlay.id] == nil {
            guard case .image(let path, _) = overlay.content else { continue }
            let url = mediaDirectory.appending(path: (path as NSString).lastPathComponent, directoryHint: .notDirectory)
            if let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
                overlayImages[overlay.id] = image
            }
        }
    }
}
