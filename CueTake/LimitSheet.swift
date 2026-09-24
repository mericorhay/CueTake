import DesignSystem
import Domain
import SwiftUI
import UIKit
import UserNotifications

/// The card that opens when something paid is refused: a month's allowance used up, or a
/// CueTake+ tool on the free plan.
///
/// Ported from the design file one to one. Every animation there is a CSS keyframe with its own
/// delay and curve, so here everything is a function of the seconds since the card opened, read
/// through the same cubic-bézier curves: the sheet springs up, the meter fills segment by segment
/// and shakes when it hits the top, a coral flash and a scan line cross it, the CLIP light blinks,
/// the title rises line by line, the countdown ticks in frames beside a turning reel, the free
/// tools pop in and a sheen crosses the button.
struct LimitSheet: View {
    let request: AccessRequest
    let plan: Plan
    /// When this month's allowance starts again.
    let resetsAt: Date
    let onUpgrade: () -> Void
    let onClose: () -> Void

    @State private var opened = Date.now
    @State private var closing: Date?
    @State private var drag: CGFloat = 0
    @State private var toast: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLimit: Bool {
        if case .limitReached = request.decision { true } else { false }
    }

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date
            // Reduced motion: everything already where it ends.
            let t = reduceMotion ? 60 : now.timeIntervalSince(opened)
            let leaving = closing.map { min(1, now.timeIntervalSince($0) / 0.32) } ?? 0

            ZStack(alignment: .bottom) {
                scrim(t: t, leaving: leaving)
                sheet(t: t, now: now)
                    .padding(8)
                    .offset(y: sheetOffset(t: t, leaving: leaving))
                    .gesture(
                        DragGesture()
                            .onChanged { drag = max(0, $0.translation.height) }
                            .onEnded { value in
                                if value.translation.height > 110 || value.predictedEndTranslation.height > 260 { close() } else {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { drag = 0 }
                                }
                            }
                    )
                if let toast {
                    toastView(since: now.timeIntervalSince(toast))
                }
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onAppear { opened = .now }
    }

    // MARK: - Pieces

    private func scrim(t: Double, leaving: Double) -> some View {
        Rectangle()
            .fill(Color(red: 5 / 255, green: 5 / 255, blue: 7 / 255).opacity(0.5))
            .background(.ultraThinMaterial.opacity(0.35))
            .opacity(LimitCurve.ease(Self.clamp(t / 0.6)) * (1 - leaving))
            .contentShape(Rectangle())
            .onTapGesture { close() }
            .accessibilityLabel(Text("limit.close"))
    }

    private func sheetOffset(t: Double, leaving: Double) -> CGFloat {
        let rise = LimitCurve.sheetIn(Self.clamp(t / 0.85))
        let height: CGFloat = 900
        return height * (1 - rise) + drag + height * leaving * leaving
    }

    private func sheet(t: Double, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(LimitColors.ink.opacity(0.18))
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)

            meterBlock(t: t)
                .modifier(Rise(t: t, delay: 0.2))
                .padding(.top, 8)

            title(t: t)

            Text(verbatim: message)
                .font(DS.sans(.regular, 14.5))
                .lineSpacing(3)
                .foregroundStyle(LimitColors.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -4)
                .modifier(Rise(t: t, delay: 0.7))

            if isLimit {
                countdown(now: now, t: t)
                    .modifier(Rise(t: t, delay: 0.82))
            }

            freeTools(t: t)

            buttons(t: t)
                .modifier(Rise(t: t, delay: 1.15))
                .padding(.top, 2)
        }
        .padding(.top, 10)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                LimitColors.sheet
                flash(t: t)
                scan(t: t)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LimitColors.ink.opacity(0.7))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel(Text("limit.close"))
        }
        .shadow(color: .black.opacity(0.7), radius: 45, y: -20)
        .padding(.bottom, 12)
    }

    /// The 30-segment meter: 24 lime, the last 6 coral, filled one after another, then a shake.
    private func meterBlock(t: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: kicker)
                    .font(DS.mono(10.5)).tracking(1.5)
                    .foregroundStyle(LimitColors.ink.opacity(0.62))
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    Text(verbatim: "CLIP")
                        .font(DS.mono(10.5)).tracking(1.5)
                        .foregroundStyle(Self.blinkOn(t: t) ? LimitColors.coral : LimitColors.ink.opacity(0.32))
                    Circle()
                        .fill(Self.blinkOn(t: t) ? LimitColors.coral : Color(red: 0.35, green: 0.12, blue: 0.1))
                        .frame(width: 9, height: 9)
                        .shadow(color: LimitColors.coral.opacity(Self.blinkOn(t: t) ? 0.8 : 0), radius: 6)
                }
            }
            .padding(.trailing, 44)

            HStack(spacing: 3) {
                ForEach(0..<30, id: \.self) { index in
                    segment(index, t: t)
                }
            }
            .offset(x: Self.shake(t: t))

            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    Text(verbatim: "0").position(x: 4, y: 6)
                    Text(verbatim: Self.percent(0.5)).position(x: w * 0.5, y: 6)
                    Text(verbatim: Self.percent(0.8)).foregroundStyle(LimitColors.coral).position(x: w * 0.8, y: 6)
                    Text(verbatim: Self.percent(1)).foregroundStyle(LimitColors.coral).position(x: w - 14, y: 6)
                }
                .font(DS.mono(10))
                .foregroundStyle(LimitColors.ink.opacity(0.5))
            }
            .frame(height: 12)
        }
    }

    private func segment(_ index: Int, t: Double) -> some View {
        let coral = index >= 24
        let p = Self.clamp((t - (0.32 + Double(index) * 0.027)) / 0.26)
        let base = LimitRGB(0x24242B)
        let peak = coral ? LimitRGB(0xFFD2CE) : LimitRGB(0xFBFFD6)
        let end = coral ? LimitRGB(0xFF5A4F) : LimitRGB(0xE8FF4F)
        let fill = p < 0.55 ? base.mix(peak, p / 0.55) : peak.mix(end, (p - 0.55) / 0.45)
        let glow = p <= 0 ? 0 : (p < 0.55 ? p / 0.55 : 1 - (p - 0.55) / 0.45 * (coral ? 0.55 : 0.75))
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill.color)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .shadow(color: (coral ? LimitColors.coral : LimitColors.lime).opacity(0.9 * glow), radius: coral ? 9 : 8)
    }

    private func title(t: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LineUp(t: t, delay: 0.45) {
                Text(verbatim: titleFirst)
                    .font(DS.sans(.semibold, 34))
                    .tracking(-1)
                    .foregroundStyle(LimitColors.ink)
            }
            LineUp(t: t, delay: 0.58) {
                Text(verbatim: titleSecond)
                    .font(.system(size: 48, weight: .regular, design: .serif).italic())
                    .tracking(-0.5)
                    .foregroundStyle(LimitColors.coral)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Time to the next month's allowance as a timecode, frames at 24 a second, beside a reel.
    private func countdown(now: Date, t: Double) -> some View {
        let left = max(0, resetsAt.timeIntervalSince(now))
        let hours = Int(left / 3600)
        let minutes = Int(left / 60) % 60
        let seconds = Int(left) % 60
        let frames = Int(left.truncatingRemainder(dividingBy: 1) * 24)
        let colonLit = t.truncatingRemainder(dividingBy: 1) >= 0.5
        let colon = Text(verbatim: ":").foregroundStyle(colonLit ? LimitColors.lime.opacity(0.9) : LimitColors.ink.opacity(0.3))

        return HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("limit.reset")
                    .font(DS.mono(10.5)).tracking(1.5)
                    .foregroundStyle(LimitColors.ink.opacity(0.62))
                (Text(verbatim: String(format: "%02d", hours)) + colon
                    + Text(verbatim: String(format: "%02d", minutes)) + colon
                    + Text(verbatim: String(format: "%02d", seconds)) + colon
                    + Text(verbatim: String(format: "%02d", frames)).foregroundStyle(LimitColors.lime))
                    .font(DS.mono(30))
                    .monospacedDigit()
                    .foregroundStyle(LimitColors.ink)
                Text("limit.units")
                    .font(DS.mono(9.5)).tracking(1.5)
                    .foregroundStyle(LimitColors.ink.opacity(0.45))
            }
            Spacer(minLength: 0)
            Reel()
                .frame(width: 46, height: 46)
                .rotationEffect(.degrees(reduceMotion ? 0 : t / 5 * 360))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LimitColors.card)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(LimitColors.ink.opacity(0.05)))
        )
    }

    private func freeTools(t: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("limit.free.tools")
                .font(DS.mono(10.5)).tracking(1.5)
                .foregroundStyle(LimitColors.ink.opacity(0.62))
                .modifier(Rise(t: t, delay: 0.92))
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Array(Self.freeToolKeys.enumerated()), id: \.offset) { index, key in
                    chip(key, t: t, delay: 1 + Double(index) * 0.06)
                }
            }
        }
    }

    private func chip(_ key: String, t: Double, delay: Double) -> some View {
        let p = LimitCurve.chipIn(Self.clamp((t - delay) / 0.55))
        return HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LimitColors.lime)
            Text(LocalizedStringKey(key))
                .font(DS.sans(.regular, 13))
                .foregroundStyle(LimitColors.ink)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 32)
        .background(Capsule().fill(LimitColors.card).overlay(Capsule().strokeBorder(LimitColors.ink.opacity(0.07))))
        .opacity(Self.clamp(p))
        .scaleEffect(0.7 + 0.3 * p)
        .offset(y: 8 * (1 - p))
    }

    @ViewBuilder
    private func buttons(t: Double) -> some View {
        VStack(spacing: 8) {
            if plan == .pro && isLimit {
                primary(t: t, action: notify) {
                    Image(systemName: "bell")
                        .font(.system(size: 16, weight: .semibold))
                    Text("limit.notify")
                }
                ghost("limit.done", action: close)
            } else {
                primary(t: t, action: {
                    onUpgrade()
                    close()
                }) {
                    Text("limit.upgrade")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text("limit.cancelAnytime")
                    .font(DS.mono(11))
                    .foregroundStyle(LimitColors.ink.opacity(0.55))
                    .frame(maxWidth: .infinity)
                ghost(isLimit ? "limit.wait" : "limit.notNow", action: close)
            }
        }
    }

    /// The coral button, with a sheen crossing it every few seconds.
    private func primary<Label: View>(t: Double, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            HStack(spacing: 10) { label() }
                .font(DS.sans(.semibold, 16))
                .foregroundStyle(LimitColors.background)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    GeometryReader { proxy in
                        let w = proxy.size.width
                        let cycle = t < 2 ? -1 : (t - 2).truncatingRemainder(dividingBy: 3.6) / 3.6
                        let travel = cycle < 0 ? 0 : LimitCurve.ease(Self.clamp(cycle / 0.3))
                        ZStack(alignment: .leading) {
                            LimitColors.coral
                            LinearGradient(colors: [.clear, .white.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: w * 0.45)
                                .rotationEffect(.degrees(10))
                                .offset(x: w * (-0.7 + 2.0 * travel))
                                .opacity(cycle < 0 || cycle > 0.3 ? 0 : 1)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 16))
    }

    private func ghost(_ key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(key))
                .font(DS.sans(.medium, 15))
                .foregroundStyle(LimitColors.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(LimitColors.ink.opacity(0.14)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.dsPress(radius: 16))
    }

    /// A coral glow over the top of the card when the meter hits the top.
    private func flash(t: Double) -> some View {
        let p = Self.clamp((t - 1.2) / 1.6)
        let opacity = p <= 0 ? 0 : (p < 0.12 ? p / 0.12 : 1 - (p - 0.12) / 0.88 * 0.82)
        return RadialGradient(colors: [LimitColors.coral.opacity(0.35), LimitColors.coral.opacity(0)], center: .center, startRadius: 0, endRadius: 220)
            .frame(height: 280)
            .offset(y: -160)
            .opacity(opacity)
            .allowsHitTesting(false)
    }

    /// A one-pixel coral line sweeping across the top edge.
    private func scan(t: Double) -> some View {
        let p = LimitCurve.scan(Self.clamp((t - 1.2) / 1.0))
        return GeometryReader { proxy in
            LinearGradient(colors: [.clear, LimitColors.coral, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: proxy.size.width, height: 1)
                .offset(x: proxy.size.width * (-1 + 2 * p))
                .opacity(t < 1.2 ? 0 : 1 - p)
        }
        .frame(height: 1)
        .allowsHitTesting(false)
    }

    private func toastView(since: Double) -> some View {
        let p = Self.clamp(since / 2.8)
        let opacity = p < 0.12 ? p / 0.12 : (p < 0.82 ? 1 : 1 - (p - 0.82) / 0.18)
        let y: CGFloat = p < 0.12 ? -24 * (1 - p / 0.12) : (p < 0.82 ? 0 : -12 * (p - 0.82) / 0.18)
        return VStack {
            HStack(spacing: 10) {
                Circle().fill(LimitColors.lime).frame(width: 7, height: 7).shadow(color: LimitColors.lime.opacity(0.8), radius: 5)
                Text("limit.notify.toast").font(DS.sans(.regular, 13)).foregroundStyle(LimitColors.ink)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Capsule().fill(LimitColors.card).overlay(Capsule().strokeBorder(LimitColors.ink.opacity(0.1))))
            .shadow(color: .black.opacity(0.5), radius: 15, y: 12)
            .scaleEffect(p < 0.12 ? 0.9 + 0.1 * p / 0.12 : 1)
            .offset(y: y)
            .opacity(opacity)
            .padding(.top, 68)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: - Actions

    private func close() {
        guard closing == nil else { return }
        closing = .now
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { onClose() }
    }

    /// A reminder on the day the allowance comes back; the card closes under the confirmation.
    private func notify() {
        let reset = resetsAt
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = AppLocalization.string("limit.notify.title")
            content.body = AppLocalization.string("limit.notify.body")
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reset.addingTimeInterval(60))
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "cuetake.quota.reset", content: content, trigger: trigger))
        }
        toast = .now
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.9) { close() }
    }

    // MARK: - Words

    private var kicker: String {
        isLimit
            ? AppLocalization.string("limit.kicker \(request.point.title.uppercased(with: AppLocalization.locale))")
            : AppLocalization.string("limit.kicker.plus \(request.point.title.uppercased(with: AppLocalization.locale))")
    }

    private var titleFirst: String {
        AppLocalization.string(isLimit ? "limit.title.limit.1" : "limit.title.plus.1")
    }

    private var titleSecond: String {
        AppLocalization.string(isLimit ? "limit.title.limit.2" : "limit.title.plus.2")
    }

    private var message: String {
        if !isLimit { return AppLocalization.string("limit.body.plus \(request.point.title)") }
        return plan == .pro ? AppLocalization.string("limit.body.pro") : AppLocalization.string("limit.body.free")
    }

    static let freeToolKeys = ["limit.tool.cut", "limit.tool.captions", "limit.tool.color", "limit.tool.sound", "limit.tool.text", "limit.tool.transitions"]

    // MARK: - Timing

    static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    /// "%50" in Turkish, "50 %" in Spanish, "50%" in English.
    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)).locale(AppLocalization.locale))
    }

    /// The LED and the CLIP label: on for the first 45% of each 1.4 s, from 1.22 s.
    static func blinkOn(t: Double) -> Bool {
        guard t >= 1.22 else { return false }
        return (t - 1.22).truncatingRemainder(dividingBy: 1.4) / 1.4 < 0.5
    }

    /// The meter's shake when it fills: -3, 3, -1.5, 1 points over half a second from 1.2 s.
    static func shake(t: Double) -> CGFloat {
        let p = (t - 1.2) / 0.5
        guard p > 0, p < 1 else { return 0 }
        let keys: [(Double, Double)] = [(0, 0), (0.2, -3), (0.4, 3), (0.6, -1.5), (0.8, 1), (1, 0)]
        for i in 1..<keys.count where p <= keys[i].0 {
            let (a, va) = keys[i - 1], (b, vb) = keys[i]
            let q = LimitCurve.ease((p - a) / (b - a))
            return CGFloat(va + (vb - va) * q)
        }
        return 0
    }
}

// MARK: - Motion pieces

/// Fades up from 16 points below and out of a blur, like the design's `.rise`.
private struct Rise: ViewModifier {
    let t: Double
    let delay: Double

    func body(content: Content) -> some View {
        let p = LimitCurve.rise(LimitSheet.clamp((t - delay) / 0.8))
        content
            .opacity(p)
            .offset(y: 16 * (1 - p))
            .blur(radius: 6 * (1 - p))
    }
}

/// A title line sliding up out of its own mask with a slight tilt.
private struct LineUp<Content: View>: View {
    let t: Double
    let delay: Double
    @ViewBuilder let content: Content

    var body: some View {
        let p = LimitCurve.lineUp(LimitSheet.clamp((t - delay) / 0.9))
        content
            .padding(.bottom, 2)
            .modifier(LineShift(progress: p))
            .clipped()
    }
}

private struct LineShift: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(3 * (1 - progress)), anchor: .bottomLeading)
            .visualEffect { view, proxy in
                view.offset(y: proxy.size.height * 1.15 * (1 - progress))
            }
    }
}

/// A film reel: an outer ring, five holes and a lime hub.
private struct Reel: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 48
            func circle(_ x: Double, _ y: Double, _ r: Double) -> Path {
                Path(ellipseIn: CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s))
            }
            context.stroke(circle(24, 24, 21), with: .color(Color(red: 0.96, green: 0.96, blue: 0.97).opacity(0.3)), lineWidth: 1.5)
            for (x, y) in [(24.0, 12.0), (35.4, 20.3), (31, 33.7), (17, 33.7), (12.6, 20.3)] {
                context.stroke(circle(x, y, 5), with: .color(Color(red: 0.96, green: 0.96, blue: 0.97).opacity(0.55)), lineWidth: 1.5)
            }
            context.fill(circle(24, 24, 3), with: .color(Color(red: 232 / 255, green: 1, blue: 79 / 255)))
        }
    }
}

/// The design's cubic-bézier curves, evaluated the way CSS does.
enum LimitCurve {
    static let ease = Bezier(0.25, 0.1, 0.25, 1)
    static let sheetIn = Bezier(0.16, 1.12, 0.3, 1)
    static let rise = Bezier(0.2, 0.8, 0.2, 1)
    static let lineUp = Bezier(0.2, 0.9, 0.1, 1)
    static let chipIn = Bezier(0.3, 1.4, 0.4, 1)
    static let scan = Bezier(0.6, 0, 0.3, 1)

    struct Bezier {
        let x1, y1, x2, y2: Double

        init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
        }

        func callAsFunction(_ x: Double) -> Double {
            if x <= 0 { return 0 }
            if x >= 1 { return 1 }
            // Find the curve parameter whose x is `x`: Newton first, bisection when it stalls.
            var u = x
            for _ in 0..<8 {
                let error = Self.point(u, x1, x2) - x
                if abs(error) < 1e-6 { return Self.point(u, y1, y2) }
                let slope = Self.slope(u, x1, x2)
                if abs(slope) < 1e-6 { break }
                u -= error / slope
            }
            var low = 0.0, high = 1.0
            u = x
            for _ in 0..<30 {
                let value = Self.point(u, x1, x2)
                if abs(value - x) < 1e-6 { break }
                if value < x { low = u } else { high = u }
                u = (low + high) / 2
            }
            return Self.point(u, y1, y2)
        }

        private static func point(_ u: Double, _ a: Double, _ b: Double) -> Double {
            let v = 1 - u
            return 3 * a * u * v * v + 3 * b * u * u * v + u * u * u
        }

        private static func slope(_ u: Double, _ a: Double, _ b: Double) -> Double {
            let v = 1 - u
            return 3 * a * v * v + 6 * (b - a) * u * v + 3 * (1 - b) * u * u
        }
    }
}

/// The card's own colours, from the design.
private enum LimitColors {
    static let background = Color(red: 11 / 255, green: 11 / 255, blue: 13 / 255)
    static let sheet = Color(red: 19 / 255, green: 19 / 255, blue: 23 / 255)
    static let card = Color(red: 26 / 255, green: 26 / 255, blue: 32 / 255)
    static let ink = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let lime = Color(red: 232 / 255, green: 1, blue: 79 / 255)
    static let coral = Color(red: 1, green: 90 / 255, blue: 79 / 255)
}

private struct LimitRGB {
    let r, g, b: Double

    init(_ hex: Int) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    private init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    func mix(_ other: LimitRGB, _ t: Double) -> LimitRGB {
        let t = LimitSheet.clamp(t)
        return LimitRGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

extension AccessPoint {
    /// The feature's name as the card says it.
    var title: String {
        switch self {
        case .aiEdit: AppLocalization.string("access.feature.aiEdit")
        case .assistantMessage: AppLocalization.string("access.feature.assistant")
        case .scriptWriting: AppLocalization.string("access.feature.script")
        case .captionTranslation: AppLocalization.string("access.feature.translation")
        case .workflowRun: AppLocalization.string("access.feature.workflow")
        case .stockBroll: AppLocalization.string("access.feature.broll")
        case .cloudListening: AppLocalization.string("access.feature.cloudCaptions")
        case .videoStyle: AppLocalization.string("access.feature.styles")
        case .soundDesign: AppLocalization.string("access.feature.soundDesign")
        case .beatSync: AppLocalization.string("access.feature.beatSync")
        case .brandTemplate: AppLocalization.string("access.feature.templates")
        case .multiPlatformExport: AppLocalization.string("access.feature.multiExport")
        case .highResolutionExport: AppLocalization.string("access.feature.export4K")
        case .highResolutionCapture: AppLocalization.string("access.feature.capture4K")
        case .suflorReport: AppLocalization.string("access.feature.suflorReport")
        }
    }
}

/// Shows the limit card in a window of its own, above every sheet and full-screen cover: a refusal
/// can come from inside the lyrics or the style picker, and a card under them would never be seen.
@MainActor
final class LimitPresenter {
    private var window: UIWindow?
    /// The app's own window, given the keyboard back when the card goes.
    private weak var previousKey: UIWindow?

    func show(_ card: some View) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        else { return }
        previousKey = scene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: AnyView(card))
        host.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert
        window.backgroundColor = .clear
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
    }

    func hide() {
        window?.isHidden = true
        window = nil
        previousKey?.makeKey()
    }
}
