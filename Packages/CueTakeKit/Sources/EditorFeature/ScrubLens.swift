import DesignSystem
import Domain
import SwiftUI

/// A bump of glass under the finger while scrubbing, with the exact time in it.
///
/// It used to magnify the ruler, and magnifying was the mistake: a lens over a strip that is
/// already drawn at the scale the user chose gives them a second, disagreeing view of the same
/// thing, and the eye has to reconcile them. What the finger is actually covering is not detail —
/// it is the *number*. So the glass carries the number and nothing else, to two decimal places,
/// which is finer than anyone can drag and exactly what they want to read.
///
/// Still glass, still swelling into place. A label that appears is a tooltip; something that
/// swells is a thing sitting on the surface, and this one sits on the timeline it belongs to.
struct ScrubLens: View {
    @Bindable var model: EditorModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    static let width: CGFloat = 96
    static let height: CGFloat = 46

    var body: some View {
        VStack(spacing: 1) {
            Text(Self.preciseLabel(model.playhead))
                .dsFont(.mono, .semibold, 17)
                .foregroundStyle(DS.Palette.ink)
                .contentTransition(.numericText())
                .monospacedDigit()

            Text(Self.frameLabel(for: model))
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.56))
        }
        .frame(width: Self.width, height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    // A highlight down the top edge and a shadow under it: without both it reads
                    // as a painted rectangle rather than something raised off the surface.
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [DS.Palette.ink(0.32), DS.Palette.hairline(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
        }
        .shadow(color: .black.opacity(0.4), radius: 14, y: 5)
        // Grows out of the timeline rather than in from nowhere: the anchor is the bottom edge,
        // which is where the finger is.
        .scaleEffect(grown ? 1 : 0.7, anchor: .bottom)
        .opacity(grown ? 1 : 0)
        .onAppear {
            guard !reduceMotion else {
                grown = true
                return
            }
            withAnimation(DS.Motion.bloom) { grown = true }
        }
    }

    /// Seconds to two decimals, which is finer than a finger can drag and is the point: the number
    /// is there to be *read*, not to be hit.
    static func preciseLabel(_ seconds: Double) -> String {
        if seconds >= 60 {
            let minutes = Int(seconds) / 60
            return String(format: "%d:%05.2f", minutes, seconds - Double(minutes * 60))
        }
        return String(format: "%.2f s", seconds)
    }

    /// The frame inside the current second. The reason anyone holds a finger this still is that
    /// they are looking for one particular frame.
    static func frameLabel(for model: EditorModel) -> String {
        let rate = max(1, model.project.format.frameRate)
        let frame = Int((model.playhead - model.playhead.rounded(.down)) * Double(rate))
        return "f\(min(frame, rate - 1) + 1)/\(rate)"
    }
}
