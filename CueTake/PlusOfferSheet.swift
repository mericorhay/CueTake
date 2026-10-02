import DesignSystem
import Domain
import SwiftUI

/// The moments CueTake+ is offered without anything having been refused.
enum PlusOffer: String, Identifiable, Hashable {
    /// Right after the introduction: what is free for good, and what CueTake+ adds.
    case welcome
    /// Right after the first export: the creator has just seen what the app does.
    case firstExport

    var id: String { rawValue }

    /// Each offer is made once per install.
    var shownKey: String { "cuetake.offer.\(rawValue).shown" }
    var analyticsName: String { self == .welcome ? "offer_welcome" : "offer_first_export" }
}

/// The card that offers CueTake+ at a good moment: after the introduction and after the first
/// export. Nothing is locked behind it; "Start free" or "Not now" closes it and it does not return.
///
/// It speaks the limit card's language (the same sheet, type and curves, see `LimitSheet`) in the
/// opposite mood: lime where that one is coral. The month's AI edits count up from the free
/// allowance to CueTake+'s, the CueTake+ tools arrive locked and open one after another, and a
/// lime line sweeps the top edge. As there, everything is a function of the seconds since the card
/// opened, so Reduce Motion simply shows it finished.
struct PlusOfferSheet: View {
    let offer: PlusOffer
    /// "7,49 $", once the App Store has answered.
    var price: String? = nil
    /// "7 days free", when the App Store has a trial this account can take.
    var trial: String? = nil
    let onUpgrade: () -> Void
    let onClose: () -> Void

    @State private var opened = Date.now
    @State private var closing: Date?
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date
            // Reduced motion: everything already where it ends.
            let t = reduceMotion ? 60 : now.timeIntervalSince(opened)
            let leaving = closing.map { min(1, now.timeIntervalSince($0) / 0.32) } ?? 0

            ZStack(alignment: .bottom) {
                scrim(t: t, leaving: leaving)
                sheet(t: t)
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
            .opacity(LimitCurve.ease(LimitSheet.clamp(t / 0.6)) * (1 - leaving))
            .contentShape(Rectangle())
            .onTapGesture { close() }
            .accessibilityLabel(Text(verbatim: AppLocalization.string("limit.close")))
    }

    private func sheetOffset(t: Double, leaving: Double) -> CGFloat {
        let rise = LimitCurve.sheetIn(LimitSheet.clamp(t / 0.85))
        let height: CGFloat = 900
        return height * (1 - rise) + drag + height * leaving * leaving
    }

    private func sheet(t: Double) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(LimitColors.ink.opacity(0.18))
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)

            kickerRow(t: t)
                .modifier(Rise(t: t, delay: 0.2))
                .padding(.top, 8)

            title(t: t)

            Text(verbatim: AppLocalization.string(offer == .welcome ? "offer.body.welcome" : "offer.body.export"))
                .font(DS.sans(.regular, 14.5))
                .lineSpacing(3)
                .foregroundStyle(LimitColors.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -4)
                .modifier(Rise(t: t, delay: 0.62))

            allowance(t: t)
                .modifier(Rise(t: t, delay: 0.74))

            tools(t: t)

            buttons(t: t)
                .modifier(Rise(t: t, delay: 1.5))
                .padding(.top, 2)
        }
        .padding(.top, 10)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                LimitColors.sheet
                glow(t: t)
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
            .accessibilityLabel(Text(verbatim: AppLocalization.string("limit.close")))
        }
        .shadow(color: .black.opacity(0.7), radius: 45, y: -20)
        .padding(.bottom, 12)
    }

    /// "FIRST VIDEO · EXPORTED" beside a lime light that breathes.
    private func kickerRow(t: Double) -> some View {
        let breath = 0.55 + 0.45 * (0.5 + 0.5 * sin(t * 2.4))
        return HStack(spacing: 8) {
            Circle()
                .fill(LimitColors.lime)
                .frame(width: 8, height: 8)
                .shadow(color: LimitColors.lime.opacity(0.8 * breath), radius: 6)
                .opacity(reduceMotion ? 1 : breath)
            Text(verbatim: AppLocalization.string(offer == .welcome ? "offer.kicker.welcome" : "offer.kicker.export"))
                .font(DS.mono(10.5)).tracking(1.5)
                .foregroundStyle(LimitColors.ink.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 44)
    }

    private func title(t: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LineUp(t: t, delay: 0.36) {
                Text(verbatim: AppLocalization.string(offer == .welcome ? "offer.title.welcome.1" : "offer.title.export.1"))
                    .font(DS.sans(.semibold, 34))
                    .tracking(-1)
                    .foregroundStyle(LimitColors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            LineUp(t: t, delay: 0.49) {
                Text(verbatim: AppLocalization.string(offer == .welcome ? "offer.title.welcome.2" : "offer.title.export.2"))
                    .font(.system(size: 48, weight: .regular, design: .serif).italic())
                    .tracking(-0.5)
                    .foregroundStyle(LimitColors.lime)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The month's AI edits, counting up from the free plan's number to CueTake+'s while a lime bar
    /// grows under it. The numbers are the ones in force (the server's, when it has sent any).
    private func allowance(t: Double) -> some View {
        let free = AccessPolicy.monthlyLimit(.aiEdit, plan: .free) ?? 0
        let plus = AccessPolicy.monthlyLimit(.aiEdit, plan: .pro) ?? free
        let p = LimitCurve.rise(LimitSheet.clamp((t - 0.95) / 1.1))
        let shown = Int((Double(free) + Double(plus - free) * p).rounded())
        let start = plus > 0 ? Double(free) / Double(plus) : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: AppLocalization.string("offer.ai"))
                    .font(DS.mono(10.5)).tracking(1.5)
                    .foregroundStyle(LimitColors.ink.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\(free)")
                        .font(DS.mono(15))
                        .strikethrough(p > 0.05, color: LimitColors.ink.opacity(0.4))
                        .foregroundStyle(LimitColors.ink.opacity(0.4))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LimitColors.ink.opacity(0.4))
                    Text(verbatim: "\(shown)")
                        .font(DS.mono(30))
                        .monospacedDigit()
                        .foregroundStyle(LimitColors.lime)
                        .shadow(color: LimitColors.lime.opacity(0.5 * (1 - p)), radius: 10)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(free) → \(plus)"))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(LimitColors.ink.opacity(0.08))
                    Capsule()
                        .fill(LimitColors.lime)
                        .frame(width: max(6, proxy.size.width * (start + (1 - start) * p)))
                        .shadow(color: LimitColors.lime.opacity(0.6 * (1 - p)), radius: 8)
                }
            }
            .frame(height: 6)
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

    private func tools(t: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: AppLocalization.string("offer.tools"))
                .font(DS.mono(10.5)).tracking(1.5)
                .foregroundStyle(LimitColors.ink.opacity(0.62))
                .modifier(Rise(t: t, delay: 0.86))
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Array(Self.plusTools.enumerated()), id: \.offset) { index, tool in
                    chip(tool.point.title, symbol: tool.symbol, t: t, delay: 0.98 + Double(index) * 0.09)
                }
            }
        }
    }

    /// A CueTake+ tool: pops in locked, then the lock gives way to the tool's own mark as the
    /// outline turns lime and glows once.
    private func chip(_ name: String, symbol: String, t: Double, delay: Double) -> some View {
        let p = LimitCurve.chipIn(LimitSheet.clamp((t - delay) / 0.55))
        let open = LimitCurve.ease(LimitSheet.clamp((t - delay - 0.5) / 0.4))
        let pulse = sin(open * .pi)
        return HStack(spacing: 6) {
            ZStack {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LimitColors.ink.opacity(0.45))
                    .opacity(1 - open)
                    .scaleEffect(1 - 0.4 * open)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LimitColors.lime)
                    .opacity(open)
                    .scaleEffect(0.6 + 0.4 * open)
            }
            .frame(width: 16, height: 16)
            Text(verbatim: name)
                .font(DS.sans(.regular, 13))
                .foregroundStyle(LimitColors.ink.opacity(0.6 + 0.4 * open))
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 32)
        .background(
            Capsule()
                .fill(LimitColors.card)
                .overlay(Capsule().strokeBorder(LimitColors.ink.opacity(0.07)))
                .overlay(Capsule().strokeBorder(LimitColors.lime.opacity(0.45 * open)))
        )
        .shadow(color: LimitColors.lime.opacity(0.45 * pulse), radius: 8)
        .opacity(LimitSheet.clamp(p))
        .scaleEffect((0.7 + 0.3 * p) * (1 + 0.06 * pulse))
        .offset(y: 8 * (1 - p))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
    }

    @ViewBuilder
    private func buttons(t: Double) -> some View {
        VStack(spacing: 8) {
            Button(action: {
                onUpgrade()
                close()
            }) {
                HStack(spacing: 10) {
                    Text(verbatim: AppLocalization.string(trial == nil ? "limit.upgrade" : "offer.cta.trial"))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .font(DS.sans(.semibold, 16))
                .foregroundStyle(LimitColors.background)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background { sheen(t: t) }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.dsPress(radius: 16))

            Text(verbatim: priceLine)
                .font(DS.mono(11))
                .foregroundStyle(LimitColors.ink.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            // What App Review asks every subscription screen to say before the purchase.
            Text(verbatim: AppLocalization.string("plus.autoRenew"))
                .font(DS.sans(.regular, 10))
                .foregroundStyle(LimitColors.ink.opacity(0.45))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            HStack(spacing: 14) {
                Link(destination: PlusStore.termsURL) { Text(verbatim: AppLocalization.string("plus.terms")) }
                Link(destination: PlusStore.privacyURL) { Text(verbatim: AppLocalization.string("plus.privacy")) }
            }
            .font(DS.sans(.regular, 11))
            .foregroundStyle(LimitColors.ink.opacity(0.5))
            .frame(maxWidth: .infinity)

            Button(action: close) {
                Text(verbatim: AppLocalization.string(offer == .welcome ? "offer.startFree" : "limit.notNow"))
                    .font(DS.sans(.medium, 15))
                    .foregroundStyle(LimitColors.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(LimitColors.ink.opacity(0.14)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.dsPress(radius: 16))
        }
    }

    /// The lime button's fill, with a sheen crossing it every few seconds.
    private func sheen(t: Double) -> some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let cycle = t < 2.4 ? -1 : (t - 2.4).truncatingRemainder(dividingBy: 3.6) / 3.6
            let travel = cycle < 0 ? 0 : LimitCurve.ease(LimitSheet.clamp(cycle / 0.3))
            ZStack(alignment: .leading) {
                LimitColors.lime
                LinearGradient(colors: [.clear, .white.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: w * 0.45)
                    .rotationEffect(.degrees(10))
                    .offset(x: w * (-0.7 + 2.0 * travel))
                    .opacity(cycle < 0 || cycle > 0.3 ? 0 : 1)
            }
        }
    }

    /// A lime glow over the top of the card as the count lands.
    private func glow(t: Double) -> some View {
        let p = LimitSheet.clamp((t - 0.95) / 2.0)
        let opacity = p <= 0 ? 0 : (p < 0.3 ? p / 0.3 : 1 - (p - 0.3) / 0.7 * 0.7)
        return RadialGradient(colors: [LimitColors.lime.opacity(0.22), LimitColors.lime.opacity(0)], center: .center, startRadius: 0, endRadius: 220)
            .frame(height: 280)
            .offset(y: -160)
            .opacity(opacity)
            .allowsHitTesting(false)
    }

    /// A one-pixel lime line sweeping across the top edge.
    private func scan(t: Double) -> some View {
        let p = LimitCurve.scan(LimitSheet.clamp((t - 0.95) / 1.0))
        return GeometryReader { proxy in
            LinearGradient(colors: [.clear, LimitColors.lime, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: proxy.size.width, height: 1)
                .offset(x: proxy.size.width * (-1 + 2 * p))
                .opacity(t < 0.95 ? 0 : 1 - p)
        }
        .frame(height: 1)
        .allowsHitTesting(false)
    }

    // MARK: - Words

    /// "7 days free, then 7,49 $ / month · cancel anytime", or less when the store has said less.
    private var priceLine: String {
        if let trial, let price { return AppLocalization.string("limit.trialThen \(trial) \(price)") }
        if let price { return AppLocalization.string("limit.pricePerMonth \(price)") }
        return AppLocalization.string("limit.cancelAnytime")
    }

    /// The CueTake+ tools shown opening, each with its mark.
    private static let plusTools: [(point: AccessPoint, symbol: String)] = [
        (.highResolutionExport, "4k.tv"),
        (.videoStyle(.energetic), "paintpalette"),
        (.soundDesign, "waveform"),
        (.stockBroll, "film.stack"),
        (.beatSync, "metronome"),
        (.multiPlatformExport, "square.and.arrow.up.on.square"),
    ]

    // MARK: - Actions

    private func close() {
        guard closing == nil else { return }
        closing = .now
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { onClose() }
    }
}
