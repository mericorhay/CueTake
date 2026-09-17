import Domain
import Foundation

/// A picture on the stage. Until now only added videos had a rectangle and the shot video was
/// always the whole frame, which made a split screen something you could ask for but never build:
/// you could shrink the guest and never the host. Both are pictures here.
public enum StagePiece: Hashable, Sendable {
    case main
    case layer(VideoLayer.ID)
}

extension EditorModel {
    /// The picture the canvas is placing, if any.
    public var placedPiece: StagePiece? {
        if isPlacingMainVideo { return .main }
        if let id = selectedVideoLayer { return .layer(id) }
        return nil
    }

    public func placement(of piece: StagePiece) -> VideoPlacement {
        switch piece {
        case .main:
            return project.mainVideoPlacement.bounded
        case .layer(let id):
            guard let layer = project.videoLayers.first(where: { $0.id == id }) else { return .full }
            return layer.placement(at: playhead).bounded
        }
    }

    public func setPlacement(_ placement: VideoPlacement, of piece: StagePiece) {
        switch piece {
        case .main: setMainVideoPlacement(placement)
        case .layer(let id): setVideoLayerPlacement(id, placement)
        }
    }

    /// Moves or resizes the shot video itself.
    public func setMainVideoPlacement(_ placement: VideoPlacement, coalescing key: String = "main-video-placement") {
        record("editor.change.mainPlacement", symbol: "rectangle.inset.filled", coalescing: key)
        var next = placement.bounded
        // A picture given half the frame is cropped to that half, not letterboxed inside it:
        // a face with black bars either side of it is not a split screen.
        if next.width < 0.999 || next.height < 0.999 { next.fillsFrame = true }
        project.mainVideoPlacement = next
        project.updatedAt = .now
    }

    /// Chooses the shot video as the picture being placed, or lets go of it.
    public func placeMainVideo(_ on: Bool) {
        isPlacingMainVideo = on
        guard on else { return }
        select(videoLayer: nil)
        isPlacingMainVideo = true
    }

    public var isMainVideoWholeFrame: Bool {
        let placement = project.mainVideoPlacement
        return placement.width > 0.999 && placement.height > 0.999
    }

    /// Gives the whole frame back to the shot video.
    public func fillFrameWithMainVideo() {
        guard !isMainVideoWholeFrame else { return }
        record("editor.change.mainPlacement", symbol: "rectangle")
        var next = project.mainVideoPlacement
        next.x = 0; next.y = 0; next.width = 1; next.height = 1
        project.mainVideoPlacement = next.bounded
        project.updatedAt = .now
    }

    /// Exchanges two pictures' rectangles: whoever was small is now the big one. Keyframes on the
    /// layer would pull it straight back to where it was, so a swap drops them.
    public func swapStage(with id: VideoLayer.ID) {
        guard let index = project.videoLayers.firstIndex(where: { $0.id == id }) else { return }
        record("editor.change.stageSwap", symbol: "arrow.left.arrow.right")
        let theirs = project.videoLayers[index].placement.bounded
        var mine = project.mainVideoPlacement.bounded
        if mine.width > 0.999 && mine.height > 0.999 { mine.fillsFrame = true }
        project.videoLayers[index].placement = mine
        project.videoLayers[index].keyframes = []
        var next = theirs
        if next.width < 0.999 || next.height < 0.999 { next.fillsFrame = true }
        project.mainVideoPlacement = next
        project.updatedAt = .now
    }

    /// Both pictures fill the frame together, the shot video first. The layer is stretched to
    /// cover the whole of the video it is beside so a split screen has no dead half.
    public func splitScreen(_ layout: VideoLayout, with id: VideoLayer.ID) {
        guard let index = project.videoLayers.firstIndex(where: { $0.id == id }) else { return }
        record("editor.change.videoLayout", symbol: "rectangle.split.2x1")
        let places = layout.placements(count: 2)
        project.mainVideoPlacement = places[0]
        project.videoLayers[index].placement = places[1]
        project.videoLayers[index].keyframes = []
        project.updatedAt = .now
    }
}
