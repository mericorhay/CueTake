import DesignSystem
import Domain
import SwiftUI

/// The cutting tools, under the timeline where the hands already are.
///
/// Four of them, and no more. The split is the one that matters — everything a phone editor is for
/// comes down to putting a cut in the right place — and the other three are what you need once you
/// have made one. A toolbar with twelve buttons is a desktop app on a phone; these are the ones
/// that earn their width.
///
/// Each is disabled when it cannot apply rather than hidden, so the row never changes shape under
/// the thumb and nothing moves out from under a tap in flight.
struct EditorToolbar: View {
    @Bindable var model: EditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var index: Int? {
        if let inspected = model.inspectedSegment {
            return model.project.segments.firstIndex { $0.id == inspected }
        }
        return model.segmentAtPlayhead?.index
    }

    var body: some View {
        HStack(spacing: 8) {
            tool("scissors", "editor.tool.split", enabled: model.segmentAtPlayhead != nil) {
                model.splitAtPlayhead()
            }

            tool(
                "arrow.trianglehead.merge",
                "editor.tool.merge",
                enabled: index.map { model.canMerge(at: $0) } ?? false
            ) {
                if let index { model.mergeWithNext(at: index) }
            }

            tool("plus.square.on.square", "editor.tool.duplicate", enabled: index != nil) {
                if let index { model.duplicateSegment(at: index) }
            }

            tool(
                "trash",
                "editor.tool.delete",
                enabled: index != nil && model.project.segments.count > 1,
                isDestructive: true
            ) {
                if let index { model.deleteSegment(at: index) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .animation(DS.Motion.snap, value: model.inspectedSegment)
    }

    private func tool(
        _ symbol: String,
        _ titleKey: String.LocalizationValue,
        enabled: Bool,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DS.Motion.settle) { action() }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                Text(String(localized: titleKey, bundle: .module))
                    .dsFont(.sans, .medium, 10)
            }
            .foregroundStyle(
                enabled
                    ? (isDestructive ? DS.Palette.accent : DS.Palette.ink(0.85))
                    : DS.Palette.ink(0.22)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Palette.hairline(enabled ? 0.07 : 0.03))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 14))
        .disabled(!enabled)
        .animation(DS.Motion.snap, value: enabled)
    }
}
