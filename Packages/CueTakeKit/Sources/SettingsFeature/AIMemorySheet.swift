import DesignSystem
import Domain
import SwiftUI

/// What the AI editor remembers about the creator's videos, each line deletable.
struct AIMemorySheet: View {
    let close: () -> Void
    @State private var facts = AIMemory.facts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsSheetHeader(
                    icon: "brain.head.profile",
                    title: settingsText("settings.aiMemory"),
                    detail: settingsText("settings.aiMemory.detail"),
                    close: close
                )
                if facts.isEmpty {
                    Text("settings.aiMemory.empty", bundle: .module)
                        .font(DS.sans(.regular, 14)).foregroundStyle(DS.Palette.ink(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                } else {
                    VStack(spacing: 1) {
                        ForEach(facts, id: \.self) { fact in
                            HStack(alignment: .top, spacing: 12) {
                                Text(verbatim: fact)
                                    .font(DS.sans(.regular, 15)).foregroundStyle(DS.Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Button {
                                    AIMemory.forget(fact)
                                    withAnimation(reduceMotion ? nil : DS.Motion.snap) { facts = AIMemory.facts }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(DS.Palette.ink(0.35))
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("settings.aiMemory.forget", bundle: .module))
                            }
                            .padding(.leading, 18)
                            .padding(.vertical, 4)
                        }
                    }
                    .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 24))

                    Button(role: .destructive) {
                        AIMemory.forgetAll()
                        withAnimation(reduceMotion ? nil : DS.Motion.snap) { facts = [] }
                    } label: {
                        Text("settings.aiMemory.clear", bundle: .module)
                            .font(DS.sans(.semibold, 14))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .tint(DS.Palette.accent)
                }
            }
            .padding(22).padding(.top, 14).padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(DS.Palette.screen)
    }
}
