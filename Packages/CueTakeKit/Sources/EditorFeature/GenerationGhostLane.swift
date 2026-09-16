import DesignSystem
import Domain
import SwiftUI

/// Where videos being made will land, drawn on the timeline before they exist.
///
/// A generation takes minutes. Without a mark on the timeline the request is out of sight and out
/// of mind; with one, the user keeps editing around a visible "something is coming here".
struct GenerationGhostLane: View {
    @Bindable var model: EditorModel
    let scale: Double

    static let height: CGFloat = 34

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(model.generationJobs) { job in
                ghost(job)
                    .frame(width: max(CGFloat(job.seconds * scale) - 2, 30), height: 28)
                    .offset(x: CGFloat(job.at * scale))
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6, anchor: .leading).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 1.08))
                    ))
            }
        }
        .frame(width: max(CGFloat(model.timelineDuration * scale), 1), height: Self.height, alignment: .leading)
        .animation(DS.Motion.settle, value: model.generationJobs.map(\.id))
    }

    @ViewBuilder
    private func ghost(_ job: ClipGenerationJob) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        ZStack(alignment: .leading) {
            switch job.phase {
            case .working:
                DSDevelopingFilm(started: job.started, progress: nil, showsClock: false)
            case .done:
                if let thumbnail = job.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .transition(.blurReplace)
                } else {
                    DS.Palette.lime.opacity(0.3)
                }
            case .failed:
                DS.Palette.accentWarm.opacity(0.2)
            }

            HStack(spacing: 4) {
                Image(systemName: symbol(job))
                    .font(.system(size: 9, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                if job.seconds * scale > 70 {
                    Text(verbatim: job.prompt)
                        .dsFont(.sans, .semibold, 9)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(DS.Palette.ink)
            .shadow(color: .black.opacity(0.5), radius: 2)
            .padding(.horizontal, 7)
        }
        .clipShape(shape)
        .overlay {
            shape.stroke(
                job.phase == .failed ? DS.Palette.accentWarm : DS.Palette.lime.opacity(0.7),
                style: StrokeStyle(lineWidth: 1.2, dash: job.phase == .working ? [4, 3] : [])
            )
        }
        .contentShape(shape)
        .onTapGesture {
            model.pause()
            model.seek(to: job.at + 0.01)
            if job.phase == .failed { model.retryGeneration(job.id) }
        }
        .animation(DS.Motion.settle, value: job.phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: job.prompt))
    }

    private func symbol(_ job: ClipGenerationJob) -> String {
        switch job.phase {
        case .working: job.placement == .broll ? "square.2.layers.3d" : "film"
        case .done: "checkmark"
        case .failed: "arrow.clockwise"
        }
    }
}
