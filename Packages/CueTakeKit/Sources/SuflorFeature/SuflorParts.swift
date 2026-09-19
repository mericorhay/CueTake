import DesignSystem
import Domain
import SwiftUI

// Pieces the ad screens share.

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
    /// Something still to do: warm gold, apart from the accent that marks the ad itself.
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

/// The red dot of a camera rolling, with a ring breathing out of it.
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

/// The idea in one moving picture: our camera, the brand's lines rolling on the prompter with the
/// ad section lit, and each thing the brand asked for ticked as it goes by — the report's proof.
struct AdShootDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let widths: [CGFloat] = [150, 178, 120, 164, 142, 186, 110, 170, 136, 158, 124, 176]
    /// Lines 4 to 8 are the ad: the bridge, the ad, the code.
    private let ad = 4...8
    private let chips = ["KOD20", "link", "%20"]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 2.4 : context.date.timeIntervalSinceReferenceDate
            let cycle = t.truncatingRemainder(dividingBy: 7.2)
            ZStack {
                camera
                VStack(spacing: 0) {
                    prompter(scroll: CGFloat(cycle) * 16)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        ForEach(chips.indices, id: \.self) { index in
                            chip(chips[index], done: cycle > 2.6 + Double(index) * 1.1)
                        }
                    }
                    .padding(.bottom, 16)
                }
                HStack(spacing: 5) {
                    LiveDot(size: 5)
                    Text(verbatim: SuflorSession.clock(cycle * 4 + 12))
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink)
                        .monospacedDigit()
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(DS.Palette.accent(0.22)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 14)
                .padding(.bottom, 58)
            }
        }
        .accessibilityHidden(true)
    }

    /// Our own camera: a warm, soft stand-in for a face in a room.
    private var camera: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [Color(hex: 0x3A2A24), Color(hex: 0x1A1416), DS.Palette.camera],
                    center: UnitPoint(x: 0.5, y: 0.62),
                    startRadius: 10,
                    endRadius: 230
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(DS.Palette.hairline(0.14), lineWidth: 1.5)
            }
    }

    private func prompter(scroll: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.Palette.screen.opacity(0.82))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(widths.indices, id: \.self) { index in
                    Capsule()
                        .fill(ad.contains(index) ? DS.Palette.accent : DS.Palette.ink(0.85))
                        .frame(width: widths[index], height: 6)
                }
            }
            .padding(.leading, 16)
            .offset(y: 30 - scroll)
            Text("suflor.demo.ad", bundle: .module)
                .dsFont(.mono, .medium, 9, letterSpacing: 0.14)
                .foregroundStyle(DS.Palette.inkInverse)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(DS.Palette.accent))
                .offset(x: 16, y: 30 - scroll + 4 * 14 - 16)
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DS.Palette.hairline(0.16), lineWidth: 1))
    }

    private func chip(_ title: String, done: Bool) -> some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().fill(done ? DS.Palette.lime : DS.Palette.hairline(0.16))
                DrawnCheck(progress: done ? 1 : 0)
                    .stroke(DS.Palette.inkInverse, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .padding(3)
            }
            .frame(width: 14, height: 14)
            Text(verbatim: title)
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(done ? 1 : 0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(DS.Palette.glass(0.7)))
        .animation(DS.Motion.bloom, value: done)
    }
}
