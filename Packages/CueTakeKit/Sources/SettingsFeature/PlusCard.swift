import DesignSystem
import Foundation
import SwiftUI

/// What Settings shows about CueTake+: the plan, and this month's use of everything counted.
public struct PlusUsage: Equatable, Sendable {
    public struct Row: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var used: Int
        /// Nil for no limit.
        public var limit: Int?
        /// A CueTake+ tool, on the free plan.
        public var locked: Bool

        public init(id: String, title: String, used: Int, limit: Int?, locked: Bool) {
            self.id = id
            self.title = title
            self.used = used
            self.limit = limit
            self.locked = locked
        }
    }

    public var isPlus: Bool
    public var rows: [Row]
    /// Names of the tools only CueTake+ has, shown on the free plan.
    public var plusTools: [String]
    public var resetsAt: Date
    /// The monthly price in the viewer's currency, once the App Store has answered.
    public var price: String?

    public init(isPlus: Bool, rows: [Row], plusTools: [String], resetsAt: Date, price: String? = nil) {
        self.isPlus = isPlus
        self.rows = rows
        self.plusTools = plusTools
        self.resetsAt = resetsAt
        self.price = price
    }
}

/// The CueTake+ card in Settings, in the limit card's look: dark, a lime meter per feature that
/// turns coral near the top, the plan's state and the way in or out of it.
struct PlusCard: View {
    let usage: PlusUsage
    let onUpgrade: (() -> Void)?
    let onManage: (() -> Void)?
    var onRestore: (() -> Void)? = nil

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let lime = Color(red: 232 / 255, green: 1, blue: 79 / 255)
    private let coral = Color(red: 1, green: 90 / 255, blue: 79 / 255)
    private let ink = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    private let card = Color(red: 26 / 255, green: 26 / 255, blue: 32 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 14) {
                Text("plus.kicker", bundle: .module)
                    .font(DS.mono(10.5)).tracking(1.5)
                    .foregroundStyle(ink.opacity(0.62))
                ForEach(Array(usage.rows.enumerated()), id: \.element.id) { index, row in
                    meterRow(row, index: index)
                }
            }

            if !usage.isPlus, !usage.plusTools.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("plus.onlyPlus", bundle: .module)
                        .font(DS.mono(10.5)).tracking(1.5)
                        .foregroundStyle(ink.opacity(0.62))
                    FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(usage.plusTools, id: \.self) { tool in
                            HStack(spacing: 6) {
                                Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(lime)
                                Text(verbatim: tool).font(DS.sans(.regular, 13)).foregroundStyle(ink)
                            }
                            .padding(.leading, 10)
                            .padding(.trailing, 12)
                            .frame(height: 30)
                            .background(Capsule().fill(card).overlay(Capsule().strokeBorder(ink.opacity(0.07))))
                        }
                    }
                }
            }

            Text(verbatim: resetLine)
                .font(DS.mono(11))
                .foregroundStyle(ink.opacity(0.5))

            action

            HStack(spacing: 16) {
                if let onRestore, !usage.isPlus {
                    Button(action: onRestore) { Text("plus.restore", bundle: .module) }
                }
                Link(destination: URL(string: "https://mericorhay.github.io/CueTake/#terms")!) {
                    Text("plus.terms", bundle: .module)
                }
                Link(destination: URL(string: "https://mericorhay.github.io/CueTake/#privacy")!) {
                    Text("plus.privacy", bundle: .module)
                }
            }
            .font(DS.sans(.regular, 12))
            .foregroundStyle(ink.opacity(0.55))
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background {
            ZStack(alignment: .topTrailing) {
                Color(red: 19 / 255, green: 19 / 255, blue: 23 / 255)
                RadialGradient(colors: [(usage.isPlus ? lime : coral).opacity(0.22), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(ink.opacity(0.07)))
        .environment(\.colorScheme, .dark)
        .onAppear {
            if reduceMotion { appeared = true } else { withAnimation(.easeOut(duration: 0.9).delay(0.15)) { appeared = true } }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text(verbatim: "CueTake")
                        .font(DS.archivo(.bold, 26)).tracking(-0.8)
                        .foregroundStyle(ink)
                    Text(verbatim: "+")
                        .font(DS.archivo(.bold, 26))
                        .foregroundStyle(lime)
                }
                Group {
                    if usage.isPlus {
                        Text("plus.pitch.active", bundle: .module)
                    } else {
                        Text("plus.pitch", bundle: .module)
                    }
                }
                .font(DS.sans(.regular, 13))
                .foregroundStyle(ink.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Circle()
                    .fill(usage.isPlus ? lime : ink.opacity(0.4))
                    .frame(width: 7, height: 7)
                    .shadow(color: lime.opacity(usage.isPlus ? 0.8 : 0), radius: 5)
                Group {
                    if usage.isPlus {
                        Text("plus.active", bundle: .module)
                    } else {
                        Text("plus.free", bundle: .module)
                    }
                }
                .font(DS.mono(10.5)).tracking(1)
                .foregroundStyle(usage.isPlus ? lime : ink.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(card))
        }
    }

    /// One feature: its name, "3 / 5", and twenty segments filled to how much is used.
    private func meterRow(_ row: PlusUsage.Row, index: Int) -> some View {
        let fraction: Double = row.locked ? 0 : (row.limit.map { Double(row.used) / Double(max(1, $0)) } ?? 0)
        let lit = Int((min(1, fraction) * 20).rounded(.up))
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(verbatim: row.title)
                    .font(DS.sans(.medium, 14))
                    .foregroundStyle(ink.opacity(row.locked ? 0.5 : 1))
                Spacer(minLength: 8)
                Group {
                    if row.locked {
                        Label { Text(verbatim: "CueTake+") } icon: { Image(systemName: "lock.fill") }
                            .foregroundStyle(lime)
                    } else if let limit = row.limit {
                        Text(verbatim: "\(row.used) / \(limit)")
                            .foregroundStyle(fraction >= 0.8 ? coral : ink.opacity(0.7))
                    } else {
                        Text("plus.unlimited", bundle: .module)
                            .foregroundStyle(lime)
                    }
                }
                .font(DS.mono(11))
                .monospacedDigit()
            }
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { segment in
                    let on = appeared && segment < lit
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(on ? (segment >= 16 || fraction >= 1 ? coral : lime) : Color(red: 36 / 255, green: 36 / 255, blue: 43 / 255))
                        .frame(height: 8)
                        .frame(maxWidth: .infinity)
                        .animation(.easeOut(duration: 0.26).delay(0.1 + Double(index) * 0.06 + Double(segment) * 0.02), value: appeared)
                }
            }
            .opacity(row.locked ? 0.4 : 1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var action: some View {
        if usage.isPlus {
            if let onManage {
                Button(action: onManage) {
                    Text("plus.manage", bundle: .module)
                        .font(DS.sans(.medium, 15))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ink.opacity(0.14)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress(radius: 16))
            }
        } else if let onUpgrade {
            Button(action: onUpgrade) {
                HStack(spacing: 10) {
                    Text("plus.upgrade", bundle: .module)
                    if let price = usage.price {
                        Text(verbatim: "· " + AppLocalization.string("plus.perMonth \(price)", bundle: .module))
                    }
                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                }
                .font(DS.sans(.semibold, 16))
                .foregroundStyle(Color(red: 11 / 255, green: 11 / 255, blue: 13 / 255))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(coral))
            }
            .buttonStyle(.dsPress(radius: 16))
        }
    }

    private var resetLine: String {
        let date = usage.resetsAt.formatted(.dateTime.day().month(.wide).locale(AppLocalization.locale))
        return AppLocalization.string("plus.resets \(date)", bundle: .module)
    }
}
