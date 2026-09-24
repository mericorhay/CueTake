import DesignSystem
import SwiftUI

/// Over a report on the free plan: the report is kept, and CueTake+ opens it. The page shows
/// through, blurred, so it is plain that it exists and is waiting.
struct ReportLock: View {
    let onUnlock: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(DS.Palette.lime)
                .frame(width: 64, height: 64)
                .background(Circle().fill(DS.Palette.ink.opacity(0.08)))
            VStack(spacing: 8) {
                Text("suflor.report.locked.title", bundle: .module)
                    .font(DS.archivo(.bold, 26)).tracking(-0.6)
                    .foregroundStyle(DS.Palette.ink)
                    .multilineTextAlignment(.center)
                Text("suflor.report.locked.detail", bundle: .module)
                    .font(DS.sans(.regular, 14))
                    .foregroundStyle(DS.Palette.ink(0.65))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 30)
            VStack(spacing: 8) {
                Button(action: onUnlock) {
                    HStack(spacing: 10) {
                        Text("suflor.report.locked.open", bundle: .module)
                        Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                    }
                    .font(DS.sans(.semibold, 16))
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.Palette.accent))
                }
                .buttonStyle(.dsPress(radius: 16))
                Button(action: onClose) {
                    Text("suflor.report.locked.later", bundle: .module)
                        .font(DS.sans(.medium, 15))
                        .foregroundStyle(DS.Palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DS.Palette.ink.opacity(0.14)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPress(radius: 16))
            }
            .padding(.horizontal, 22)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Palette.screen.opacity(0.35))
    }
}
