import DesignSystem
import Domain
import SwiftUI

// Pieces the suflör's screens share.

extension SuflorCue.Role {
    var color: Color {
        switch self {
        case .opening, .bridge: DS.Palette.accentWarm
        case .topic, .closing: DS.Palette.lime
        case .ad, .cta: DS.Palette.accent
        case .rescue: DS.Palette.ink(0.6)
        }
    }
}

extension DS.Palette {
    /// The wait before the ad: warm gold, apart from the accent that marks the ad itself.
    static let amber = Color(hex: 0xFFB840)
}

/// A tick that draws itself.
struct DrawnCheck: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.midY + rect.height * 0.02))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.22))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.minY + rect.height * 0.24))
        return path.trimmedPath(from: 0, to: progress)
    }
}

/// A ring that fills with a share.
struct ProgressRing: View {
    var share: Double
    var color: Color
    var width: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(DS.Palette.hairline(0.12), lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, share)))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// The red dot of a live stream, with a ring breathing out of it.
struct LiveDot: View {
    var size: CGFloat = 8
    var color: Color = DS.Palette.accent
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 1.5)
                .frame(width: size, height: size)
                .scaleEffect(breathing ? 2.6 : 1)
                .opacity(breathing ? 0 : 0.8)
            Circle().fill(color).frame(width: size, height: size)
        }
        .frame(width: size * 2.6, height: size * 2.6)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { breathing = true }
        }
        .accessibilityHidden(true)
    }
}

/// A chip that can be picked.
struct SuflorChip: View {
    let title: String
    let isOn: Bool
    var tint: Color = DS.Palette.lime
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .dsFont(.sans, .semibold, 14)
                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.82))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Capsule().fill(isOn ? tint : DS.Palette.hairline(0.07)))
                .overlay(Capsule().stroke(isOn ? .clear : DS.Palette.hairline(0.1), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.dsPress)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The prompter drawn exactly as it will be, rolling on its own at the chosen pace: what the
/// speaker sees while setting speed and size.
struct SuflorLivePreview: View {
    let layout: SuflorLayout
    let wordsPerMinute: Double
    let fonts: SuflorFonts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let text = SuflorModel.chromeText
        TimelineView(.animation(paused: reduceMotion)) { context in
            Canvas { graphics, size in
                let scale = size.width / SuflorLayout.width
                let speed = layout.speed(wordsPerMinute: wordsPerMinute)
                let loop = max(1, Double(layout.end) + 80)
                var clock = SuflorClock(end: Double(layout.end))
                clock.elapsed = SuflorClock.countdown + 1
                clock.offset = min(Double(layout.end), (context.date.timeIntervalSinceReferenceDate * speed).truncatingRemainder(dividingBy: loop) - 40)
                clock.offset = max(0, clock.offset)
                let frame = SuflorFrame(clock: clock, layout: layout, kind: .live, text: text, fonts: fonts)
                graphics.withCGContext { cg in
                    cg.scaleBy(x: scale, y: scale)
                    SuflorPainter.drawText(cg, frame: frame, size: CGSize(width: SuflorLayout.width, height: size.height / scale))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The idea in one moving picture: a phone live on another app, the suflör floating in its corner
/// with the words rolling up in it.
struct FloatingWindowDemo: View {
    @State private var lifted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // The other app's camera: a warm, soft stand-in for a face in a room.
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x3A2A24), Color(hex: 0x1A1416), DS.Palette.camera],
                        center: UnitPoint(x: 0.42, y: 0.46),
                        startRadius: 10,
                        endRadius: 220
                    )
                )
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        LiveDot(size: 6)
                        Text("suflor.demo.live", bundle: .module)
                            .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
                            .foregroundStyle(DS.Palette.ink)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(DS.Palette.accent(0.9)))
                    .padding(16)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(DS.Palette.hairline(0.14))
                                .frame(width: [110, 150, 90][index], height: 7)
                        }
                    }
                    .padding(18)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(DS.Palette.hairline(0.14), lineWidth: 1.5)
                }

            window
                .padding(14)
                .offset(y: lifted ? -4 : 4)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { lifted = true }
        }
        .accessibilityHidden(true)
    }

    private var window: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.screen)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(0..<9, id: \.self) { index in
                        Capsule()
                            .fill(index % 4 == 2 ? DS.Palette.lime : DS.Palette.ink(0.85))
                            .frame(width: [58, 70, 44, 66, 52, 72, 40, 62, 56][index], height: 5)
                    }
                }
                .padding(.leading, 12)
                .offset(y: 54 - CGFloat((t * 9).truncatingRemainder(dividingBy: 48)))
                Triangle()
                    .fill(DS.Palette.lime)
                    .frame(width: 5, height: 8)
                    .offset(x: 3, y: 34)
            }
            .frame(width: 92, height: 122)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Palette.hairline(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A stepper for the stage and the flow: minus, the value, plus.
struct SuflorStepper: View {
    let value: String
    let caption: String
    let minusLabel: String
    let plusLabel: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            button("minus", label: minusLabel, action: onMinus)
            VStack(spacing: 1) {
                Text(value)
                    .dsFont(.archivo, .bold, 17)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText())
                    .monospacedDigit()
                Text(caption)
                    .dsFont(.mono, .medium, 10, letterSpacing: 0.1)
                    .foregroundStyle(DS.Palette.ink(0.56))
            }
            .frame(minWidth: 58)
            .accessibilityElement(children: .combine)
            button("plus", label: plusLabel, action: onPlus)
        }
        .padding(.horizontal, 2)
        .background(Capsule().fill(DS.Palette.hairline(0.07)))
    }

    private func button(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.Palette.ink(0.86))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dsPressIcon)
        .accessibilityLabel(Text(label))
    }
}
