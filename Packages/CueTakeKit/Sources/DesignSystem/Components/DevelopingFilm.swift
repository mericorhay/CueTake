import SwiftUI

/// Something being made by a model: light moving across unexposed film, grain, a slow breath, and
/// the time it has taken. The sweep says "working"; the clock says "not stuck".
///
/// Shared by every place a generated video is waited for — the workflow board, the editor's
/// generate panel and the timeline's placeholder — so waiting looks the same everywhere.
public struct DSDevelopingFilm: View {
    let started: Date?
    let progress: Double?
    let showsClock: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(started: Date?, progress: Double? = nil, showsClock: Bool = true) {
        self.started = started
        self.progress = progress
        self.showsClock = showsClock
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let sweep = reduceMotion ? 0.5 : time.truncatingRemainder(dividingBy: 2.2) / 2.2
            let breath = reduceMotion ? 0.5 : (sin(time * 2.4) + 1) / 2

            ZStack {
                LinearGradient(
                    colors: [DS.Palette.accent.opacity(0.35), DS.Palette.lime.opacity(0.22), DS.Palette.accentWarm.opacity(0.3)],
                    startPoint: UnitPoint(x: 0, y: breath),
                    endPoint: UnitPoint(x: 1, y: 1 - breath)
                )
                .saturation(0.7)

                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, DS.Palette.ink(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.6)
                        .rotationEffect(.degrees(18))
                        .offset(x: proxy.size.width * (sweep * 2.2 - 0.9))
                        .blendMode(.plusLighter)
                }

                if !reduceMotion {
                    Canvas { canvas, size in
                        var random = GrainRandom(seed: UInt64(time * 12))
                        for _ in 0..<Int(max(6, size.width * size.height / 260)) {
                            let x = random.next() * size.width
                            let y = random.next() * size.height
                            canvas.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(.white.opacity(0.25)))
                        }
                    }
                }

                if showsClock || progress != nil {
                    VStack(spacing: 4) {
                        if let progress {
                            ZStack {
                                Circle().stroke(DS.Palette.ink(0.15), lineWidth: 2.5)
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(DS.Palette.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 22, height: 22)
                            .animation(.easeOut(duration: 0.4), value: progress)
                        }
                        if showsClock {
                            Text(verbatim: Self.elapsed(since: started, now: context.date))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(DS.Palette.ink(0.85))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .scaleEffect(reduceMotion ? 1 : 1 + 0.015 * breath)
        }
    }

    public static func elapsed(since start: Date?, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start ?? now)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Cheap, repeatable randomness, so the grain moves with time instead of flickering on redraw.
private struct GrainRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}
