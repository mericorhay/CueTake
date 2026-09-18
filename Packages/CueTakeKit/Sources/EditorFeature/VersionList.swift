import DesignSystem
import Domain
import SwiftUI

/// Saved states of the project, and a way to keep this one.
///
/// Versions the person named come with a star and are theirs to delete; the app's own safety
/// copies are marked with a clock and clear themselves out.
struct VersionList: View {
    let tools: VersionTools
    @Binding var name: String
    let onRestore: (ProjectVersion) -> Void

    @FocusState private var naming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            saveRow
            ScrollView {
                VStack(spacing: 6) {
                    if tools.versions.isEmpty {
                        Text("editor.versions.empty", bundle: .module)
                            .dsFont(.sans, .regular, 12)
                            .foregroundStyle(DS.Palette.ink(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 20)
                    }
                    ForEach(tools.versions) { version in
                        row(version)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .animation(DS.Motion.settle, value: tools.versions.map(\.id))
            }
            .scrollIndicators(.hidden)
        }
    }

    private var saveRow: some View {
        HStack(spacing: 8) {
            TextField(String(localized: "editor.versions.namePlaceholder", bundle: .module), text: $name)
                .dsFont(.sans, .regular, 13)
                .foregroundStyle(DS.Palette.ink)
                .focused($naming)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.hairline(0.07)))
            Button(action: save) {
                Label(String(localized: "editor.versions.save", bundle: .module), systemImage: "star.fill")
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(Capsule().fill(DS.Palette.lime))
            }
            .buttonStyle(.dsPress(radius: 19))
        }
        .padding(.horizontal, 20)
    }

    private func save() {
        tools.save(name)
        name = ""
        naming = false
    }

    private func row(_ version: ProjectVersion) -> some View {
        let manual = version.kind == .manual
        return HStack(spacing: 10) {
            Image(systemName: manual ? "star.fill" : "clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(manual ? DS.Palette.lime : DS.Palette.ink(0.4))
                .frame(width: 26, height: 26)
                .background(Circle().fill(DS.Palette.hairline(manual ? 0.1 : 0.05)))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: version.name)
                    .dsFont(.sans, manual ? .semibold : .medium, 13)
                    .foregroundStyle(manual ? DS.Palette.ink : DS.Palette.ink(0.65))
                    .lineLimit(1)
                Text(verbatim: detail(version))
                    .dsFont(.mono, .medium, 9)
                    .foregroundStyle(DS.Palette.ink(0.35))
            }

            Spacer(minLength: 0)

            Button {
                onRestore(version)
            } label: {
                Text("editor.versions.restore", bundle: .module)
                    .dsFont(.sans, .semibold, 11)
                    .foregroundStyle(DS.Palette.ink(0.85))
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(Capsule().fill(DS.Palette.hairline(0.1)))
            }
            .buttonStyle(.dsPress(radius: 15))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(DS.Palette.hairline(manual ? 0.06 : 0.03))
        )
        .contextMenu {
            Button(role: .destructive) {
                tools.delete(version.id)
            } label: {
                Label(String(localized: "editor.versions.delete", bundle: .module), systemImage: "trash")
            }
        }
    }

    private func detail(_ version: ProjectVersion) -> String {
        let when = version.savedAt.formatted(date: .abbreviated, time: .shortened)
        let length = MediaTime(seconds: version.seconds).timecode
        return String(localized: "editor.versions.detail \(when) \(length) \(version.clips)", bundle: .module)
    }
}
