import DesignSystem
import Domain
import SwiftUI

/// Additional movies get a dedicated lane so their timing is visible beside the main cut.
struct VideoLayerLane: View {
    @Bindable var model: EditorModel
    let scale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "rectangle.split.2x1")
                Text("editor.videoLayers", bundle: .module)
            }
            .dsFont(.mono, .medium, 9)
            .foregroundStyle(DS.Palette.ink(0.45))
            ForEach(model.project.videoLayers) { layer in
                Button {
                    withAnimation(DS.Motion.snap) { model.select(videoLayer: model.selectedVideoLayer == layer.id ? nil : layer.id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: layer.isMuted ? "speaker.slash.fill" : "video.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text(layer.title)
                            .dsFont(.sans, .semibold, 10)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(.horizontal, 8)
                    .frame(width: max(38, CGFloat(layer.duration * scale)), height: 25, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(DS.Palette.lime.opacity(model.selectedVideoLayer == layer.id ? 1 : 0.65)))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(DS.Palette.ink, lineWidth: model.selectedVideoLayer == layer.id ? 2 : 0))
                }
                .buttonStyle(.dsPress(radius: 7))
                .offset(x: CGFloat(layer.start.seconds * scale))
            }
        }
        .frame(minHeight: CGFloat(model.project.videoLayers.count) * 29 + 18, alignment: .topLeading)
    }
}
