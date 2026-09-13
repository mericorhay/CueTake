import DesignSystem
import SwiftUI

/// The editing gestures, named.
public enum ToolKind: String, Sendable, Equatable {
    case split
    case merge
    case duplicate
    case delete
    case mute
    case speed
    case undo
    case redo
}

/// One tool firing, so the timeline can answer it.
public struct ToolPulse: Equatable, Sendable {
    public var id: Int
    public var kind: ToolKind
    /// Where on the timeline it happened, 0…1.
    public var position: Double

    public init(id: Int, kind: ToolKind, position: Double) {
        self.id = id
        self.kind = kind
        self.position = position
    }
}

/// What a tool looks like when it works.
///
/// Every tool gets its own, and that is the whole point: a single generic flash would tell the
/// user *something happened* when what they need to know is *which thing happened*, at a glance,
/// without reading. The blade travels down the cut. Two halves slide together to join. A copy
/// peels off its original. A deleted clip falls out of the timeline. Four gestures, four
/// different pieces of motion, each one describing the edit it belongs to.
///
/// None of it is decorative in the sense of being optional: this is the confirmation. It replaces
/// the toast nobody reads and the undo nobody finds, by making the edit legible while it happens.
struct ToolFlourish: View {
    let pulse: ToolPulse

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0

    private var duration: Double {
        switch pulse.kind {
        case .split: 0.42
        case .merge: 0.46
        case .duplicate: 0.5
        case .delete: 0.44
        case .mute, .speed: 0.36
        case .undo, .redo: 0.52
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let x = max(6, min(width - 6, width * pulse.position))

            ZStack(alignment: .topLeading) {
                switch pulse.kind {
                case .split: split(x: x, height: height)
                case .merge: merge(x: x, height: height)
                case .duplicate: duplicate(x: x, height: height)
                case .delete: delete(x: x, height: height)
                case .mute: level(x: x, height: height, symbol: "speaker.slash.fill")
                case .speed: level(x: x, height: height, symbol: "gauge.with.dots.needle.67percent")
                case .undo: wash(width: width, height: height, reversed: true)
                case .redo: wash(width: width, height: height, reversed: false)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else {
                phase = 1
                return
            }
            withAnimation(.easeOut(duration: duration)) { phase = 1 }
        }
    }

    // MARK: - Split

    /// The blade runs down the cut and the two edges part. The parting is the information: it says
    /// there are two clips now, at that exact x, without a word.
    private func split(x: CGFloat, height: CGFloat) -> some View {
        let part = CGFloat(phase) * 7

        return ZStack(alignment: .topLeading) {
            ForEach([-1.0, 1.0], id: \.self) { side in
                Rectangle()
                    .fill(DS.Palette.lime.opacity(1 - phase * 0.85))
                    .frame(width: 1.5, height: height)
                    .offset(x: x + part * CGFloat(side) - 0.75)
            }

            Image(systemName: "scissors")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.Palette.lime)
                .rotationEffect(.degrees(-90))
                .offset(x: x - 7, y: -10 + CGFloat(phase) * (height + 6))
                .opacity(1 - phase * 0.7)
        }
    }

    // MARK: - Merge

    /// Two arrows close on the seam and it flashes once. Nothing moves outward, because nothing
    /// about joining is expansive — the whole gesture is two things becoming one.
    private func merge(x: CGFloat, height: CGFloat) -> some View {
        let gap = (1 - CGFloat(phase)) * 26

        return ZStack(alignment: .topLeading) {
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.lime)
                .offset(x: x - 14 - gap, y: height / 2 - 8)

            Image(systemName: "arrowtriangle.left.fill")
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.lime)
                .offset(x: x + 4 + gap, y: height / 2 - 8)

            // The seam lights up only at the end, when the two have actually met.
            Rectangle()
                .fill(DS.Palette.lime)
                .frame(width: 2, height: height)
                .offset(x: x - 1)
                .opacity(phase > 0.75 ? (1 - phase) * 4 : 0)
        }
    }

    // MARK: - Duplicate

    /// A copy peels off the original, down and to the right — the direction the new clip is
    /// actually going to land in the timeline.
    private func duplicate(x: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(DS.Palette.lime.opacity(1 - phase), lineWidth: 1.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DS.Palette.lime.opacity(0.16 * (1 - phase)))
            )
            .frame(width: 54, height: height * 0.6)
            .offset(x: x + CGFloat(phase) * 22, y: height * 0.2 + CGFloat(phase) * 10)
            .scaleEffect(1 - CGFloat(phase) * 0.08)
    }

    // MARK: - Delete

    /// The clip falls out of the timeline. Downward and accelerating, because that is what gone
    /// looks like; a fade in place reads as "loading".
    private func delete(x: CGFloat, height: CGFloat) -> some View {
        let fall = CGFloat(phase * phase) * 46

        return ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(DS.Palette.accent.opacity(0.85 * (1 - phase)))
                    .frame(width: 16, height: 10)
                    .rotationEffect(.degrees(Double(index - 1) * 22 * phase))
                    .offset(
                        x: x - 24 + CGFloat(index) * 18 + CGFloat(index - 1) * CGFloat(phase) * 12,
                        y: height * 0.35 + fall
                    )
            }
        }
    }

    // MARK: - Undo

    /// Undo washes across the whole surface rather than marking a spot, because undo does not
    /// happen at a place — it happens to everything. Right to left, against the direction time
    /// runs, which is the only thing about it that has to be legible at a glance.
    private func wash(width: CGFloat, height: CGFloat, reversed: Bool) -> some View {
        let travel = CGFloat(phase) * (width + 120)

        return ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [DS.Palette.lime.opacity(0), DS.Palette.lime.opacity(0.22), DS.Palette.lime.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 120, height: height)
            .offset(x: reversed ? width - travel : travel - 120)

            Image(systemName: reversed ? "arrow.uturn.backward" : "arrow.uturn.forward")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.Palette.lime.opacity(1 - phase))
                .offset(
                    x: (reversed ? width - travel : travel - 120) + 52,
                    y: height / 2 - 8
                )
        }
    }

    // MARK: - Level

    /// For the audio tools, which act on a clip rather than on a boundary: the symbol lifts out of
    /// the lane and dissolves, which is a smaller gesture because it is a smaller edit.
    private func level(x: CGFloat, height: CGFloat, symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(DS.Palette.lime.opacity(1 - phase))
            .offset(x: x - 8, y: height / 2 - 8 - CGFloat(phase) * 20)
            .scaleEffect(1 + CGFloat(phase) * 0.3)
    }
}
