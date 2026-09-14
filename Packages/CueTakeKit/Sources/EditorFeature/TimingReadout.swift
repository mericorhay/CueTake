import DesignSystem
import Domain
import SwiftUI

/// When a selected thing plays, read out — the changing is done on the timeline above.
///
/// Panels used to set times with plus and minus buttons, a tenth of a second a tap, while covering
/// the timeline the times belong to. The numbers stay here to be read; the bar is dragged.
struct TimingReadout: View {
    let start: Double
    let end: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                value("editor.overlay.start", start)
                Spacer(minLength: 8)
                value("editor.timing.length", end - start, isLength: true)
                Spacer(minLength: 8)
                value("editor.overlay.end", end)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.hairline(0.06)))

            Label {
                Text("editor.timing.dragHint", bundle: .module)
            } icon: {
                Image(systemName: "hand.point.up.left")
            }
            .dsFont(.sans, .regular, 10)
            .foregroundStyle(DS.Palette.ink(0.45))
        }
    }

    private func value(_ key: String.LocalizationValue, _ seconds: Double, isLength: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(String(localized: key, bundle: .module))
                .dsFont(.mono, .medium, 8)
                .foregroundStyle(DS.Palette.ink(0.45))
            Text(verbatim: isLength ? String(format: "%.2f s", max(0, seconds)) : MediaTime(seconds: seconds).preciseTimecode)
                .dsFont(.mono, .medium, 13)
                .foregroundStyle(DS.Palette.ink)
                .contentTransition(.numericText(value: seconds))
        }
    }
}
