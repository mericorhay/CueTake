import DesignSystem
import SwiftUI

public struct SettingsScreen: View {
    public init() {}

    private struct Row {
        var key: String.LocalizationValue
        var value: String.LocalizationValue
    }

    private static let rows: [Row] = [
        Row(key: "settings.account", value: "settings.account.value"),
        Row(key: "settings.language", value: "settings.language.value"),
        Row(key: "settings.camera", value: "settings.camera.value"),
        Row(key: "settings.captions", value: "settings.captions.value"),
        Row(key: "settings.ai", value: "settings.ai.value"),
        Row(key: "settings.subscription", value: "settings.subscription.value"),
        Row(key: "settings.privacy", value: "settings.privacy.value"),
        Row(key: "settings.export", value: "settings.export.value"),
    ]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DSHeadline(String(localized: "settings.title", bundle: .module), size: 34)

                profile
                    .padding(.vertical, 22)

                VStack(spacing: 0) {
                    ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                        settingRow(row, isLast: index == Self.rows.count - 1)
                    }
                }
                .dsCard(radius: DS.Radius.card)
            }
            .padding(.horizontal, 22)
            .padding(.top, 64)
            .padding(.bottom, 108)
        }
        .scrollIndicators(.hidden)
        .background(DS.Palette.screen)
        .dsEnter(.screen())
    }

    private var profile: some View {
        HStack(spacing: 13) {
            Circle()
                .fill(DS.gradient(140, [DS.Palette.accentWarm, DS.Palette.accent]))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("settings.profile.name", bundle: .module)
                    .dsFont(.sans, .semibold, 15)
                    .foregroundStyle(DS.Palette.ink)
                Text("settings.profile.plan", bundle: .module)
                    .dsFont(.mono, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.4))
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .dsCard(radius: DS.Radius.card)
    }

    private func settingRow(_ row: Row, isLast: Bool) -> some View {
        HStack(spacing: 0) {
            Text(String(localized: row.key, bundle: .module))
                .dsFont(.sans, .medium, 14)
                .foregroundStyle(DS.Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(localized: row.value, bundle: .module))
                .dsFont(.sans, .regular, 13)
                .foregroundStyle(DS.Palette.ink(0.38))

            Text("›")
                .font(.system(size: 15))
                .foregroundStyle(DS.Palette.ink(0.25))
                .padding(.leading, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(DS.Palette.hairline(0.05))
                    .frame(height: 1)
            }
        }
    }
}
