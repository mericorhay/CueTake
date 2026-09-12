import SwiftUI

/// Floating tab bar: 62pt tall, inset 14pt, glass at rgba(19,19,23,.82).
/// The selected tab is marked by a 16×2 accent bar that grows from zero.
public struct DSTabBar<Tab: Hashable>: View {
    public struct Item: Identifiable {
        public let id: Tab
        public let title: String

        public init(id: Tab, title: String) {
            self.id = id
            self.title = title
        }
    }

    private let items: [Item]
    private let selection: Tab
    private let onSelect: (Tab) -> Void

    public init(items: [Item], selection: Tab, onSelect: @escaping (Tab) -> Void) {
        self.items = items
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isOn = item.id == selection
                Button {
                    onSelect(item.id)
                } label: {
                    VStack(spacing: 6) {
                        Text(item.title)
                            .dsFont(.sans, .semibold, 11)
                        Capsule()
                            .fill(DS.Palette.accent)
                            .frame(width: isOn ? 16 : 0, height: 2)
                    }
                    .foregroundStyle(isOn ? DS.Palette.ink : DS.Palette.ink(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(DS.Easing.ease(0.3), value: isOn)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 62)
        .dsGlass(
            tint: DS.Palette.glassSheet(0.82),
            in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous),
            border: DS.Palette.hairline(0.1)
        )
        .padding(.horizontal, 14)
    }
}
