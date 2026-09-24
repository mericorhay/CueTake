import DesignSystem
import SwiftUI

/// What Settings shows about the iCloud backup, filled in by the app.
public struct CloudBackupRow {
    public var isOn: Binding<Bool>
    /// "Last backup today 14:02", "Backing up 3 of 12", or why it failed.
    public var status: String
    public var isBusy: Bool
    /// The plan does not include it; the switch opens CueTake+.
    public var locked: Bool
    public var onBackup: () -> Void
    public var onRestore: () -> Void

    public init(isOn: Binding<Bool>, status: String, isBusy: Bool, locked: Bool, onBackup: @escaping () -> Void, onRestore: @escaping () -> Void) {
        self.isOn = isOn
        self.status = status
        self.isBusy = isBusy
        self.locked = locked
        self.onBackup = onBackup
        self.onRestore = onRestore
    }
}

/// The creator's projects in their own iCloud: the switch, where it stands, and the two actions.
struct CloudBackupCard: View {
    let row: CloudBackupRow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: row.isOn) {
                HStack(spacing: 12) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DS.Palette.accent)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("settings.icloud", bundle: .module)
                                .font(DS.sans(.semibold, 15)).foregroundStyle(DS.Palette.ink)
                            if row.locked {
                                Label { Text(verbatim: "CueTake+") } icon: { Image(systemName: "lock.fill") }
                                    .font(DS.mono(10))
                                    .foregroundStyle(DS.Palette.lime)
                            }
                        }
                        Text("settings.icloud.detail", bundle: .module)
                            .font(DS.sans(.regular, 12)).foregroundStyle(DS.Palette.ink(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(DS.Palette.accent)

            HStack(spacing: 8) {
                if row.isBusy { ProgressView().controlSize(.small) }
                Text(verbatim: row.status)
                    .font(DS.mono(11))
                    .foregroundStyle(DS.Palette.ink(0.6))
                    .contentTransition(.numericText())
            }

            HStack(spacing: 8) {
                button("settings.icloud.backup", symbol: "arrow.up.circle", action: row.onBackup)
                    .disabled(row.isBusy || !row.isOn.wrappedValue)
                button("settings.icloud.restore", symbol: "arrow.down.circle", action: row.onRestore)
                    .disabled(row.isBusy)
            }
        }
        .padding(18)
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private func button(_ key: String.LocalizationValue, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(settingsText(key), systemImage: symbol)
                .font(DS.sans(.medium, 13))
                .foregroundStyle(DS.Palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Capsule().fill(DS.Palette.ink.opacity(0.07)))
        }
        .buttonStyle(.dsPress(radius: 21))
    }
}
