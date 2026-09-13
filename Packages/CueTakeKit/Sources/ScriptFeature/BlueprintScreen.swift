import DesignSystem
import Domain
import SwiftUI

/// The generated blueprint: one 3D slab per segment, tap to reveal its edit actions.
public struct BlueprintScreen: View {
    @Binding private var project: Project
    @State private var openSegment: Segment.ID?

    private let onBack: () -> Void
    private let onOpenScript: () -> Void
    private let onOpenStudio: () -> Void

    public init(
        project: Binding<Project>,
        onBack: @escaping () -> Void,
        onOpenScript: @escaping () -> Void,
        onOpenStudio: @escaping () -> Void
    ) {
        self._project = project
        self.onBack = onBack
        self.onOpenScript = onOpenScript
        self.onOpenStudio = onOpenStudio
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            titleBlock
            segmentList
            footer
        }
        .dsScreenLayout()
        .background(DS.Palette.screen)
        .dsEnter(.screen())
    }

    private var header: some View {
        HStack {
            DSBackButton(action: onBack)
            Spacer(minLength: 0)
            DSKicker(String(localized: "blueprint.kicker \(project.estimatedTotalLabel)", bundle: .module))
            Spacer(minLength: 0)
            DSCircleButton("↻", fontSize: 14) { openSegment = nil }
        }
        .padding(.horizontal, 22)
        .padding(.top, 62)
        .padding(.bottom, 12)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSHeadline(String(localized: "blueprint.title", bundle: .module), size: 30)

            // Proportional bar: each segment takes its share of the running time.
            GeometryReader { proxy in
                let durations = project.segments.map(\.barWeight)
                let total = max(1, durations.reduce(0, +))
                let gaps = CGFloat(max(0, durations.count - 1)) * 3
                HStack(spacing: 3) {
                    ForEach(Array(project.segments.enumerated()), id: \.element.id) { index, segment in
                        Capsule()
                            .fill(DS.Palette.segment(at: segment.role.paletteIndex))
                            .frame(width: (proxy.size.width - gaps) * (durations[index] / total))
                    }
                }
            }
            .frame(height: 6)
            .padding(.top, 16)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    private var segmentList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(project.segments.enumerated()), id: \.element.id) { index, segment in
                    VStack(spacing: 0) {
                        slab(for: segment, at: index)
                        connector
                    }
                    .dsEnter(.slab(delay: Double(index) * 0.08))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func slab(for segment: Segment, at index: Int) -> some View {
        let isOpen = openSegment == segment.id
        let ink = DS.Palette.inkInverse

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(segment.role.displayLabel)
                    .dsFont(.archivo, .extrabold, 22, letterSpacing: -0.02)
                    .foregroundStyle(ink)
                Spacer(minLength: 0)
                Text(rangeLabel(at: index))
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.inkInverse(0.5))
            }

            Text(segment.previewText)
                .dsFont(.sans, .regular, 13, lineHeight: 1.45)
                .foregroundStyle(DS.Palette.inkInverse(0.72))
                .multilineTextAlignment(.leading)
                .padding(.top, 9)

            if isOpen {
                FlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
                    action("blueprint.action.moveUp") { move(index, by: -1) }
                    action("blueprint.action.moveDown") { move(index, by: 1) }
                    action("blueprint.action.duplicate") { duplicate(index) }
                    action("blueprint.action.regenerate") {}
                    action("blueprint.action.delete") { delete(index) }
                }
                .padding(.top, 15)
                .dsEnter(.rise(duration: 0.3))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.segment(at: segment.role.paletteIndex))
        )
        .scaleEffect(isOpen ? 1.02 : 1)
        .rotation3DEffect(
            .degrees(isOpen ? 0 : 4),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.4
        )
        .shadow(color: .black.opacity(0.55), radius: isOpen ? 27 : 16, y: isOpen ? 26 : 14)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(DS.Easing.standard(0.35)) {
                openSegment = isOpen ? nil : segment.id
            }
        }
    }

    private func action(_ key: String.LocalizationValue, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(String(localized: key, bundle: .module))
                .dsFont(.sans, .medium, 11)
                .foregroundStyle(DS.Palette.inkInverse)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(DS.Palette.inkInverse(0.12))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(DS.Palette.inkInverse(0.2), lineWidth: 1)
                }
        }
        .buttonStyle(.dsPress)
    }

    private var connector: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [DS.Palette.hairline(0.22), DS.Palette.hairline(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: 18)
    }

    private var footer: some View {
        FlexRow(spacing: 10, weights: [1, 1.4]) {
            DSSecondaryButton(
                String(localized: "blueprint.script", bundle: .module),
                action: onOpenScript
            )
            DSPrimaryButton(
                String(localized: "blueprint.studio", bundle: .module),
                action: onOpenStudio
            )
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 30)
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: DS.Palette.screen, location: 0.4),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Helpers

    private func rangeLabel(at index: Int) -> String {
        var start = 0.0
        for segment in project.segments.prefix(index) {
            start += segment.barWeight
        }
        let end = start + project.segments[index].barWeight
        return "\(MediaTime(seconds: start).timecode) – \(MediaTime(seconds: end).timecode)"
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard project.segments.indices.contains(target) else { return }
        withAnimation(DS.Easing.standard(0.35)) {
            project.segments.swapAt(index, target)
            openSegment = project.segments[target].id
        }
    }

    private func duplicate(_ index: Int) {
        var copy = project.segments[index]
        copy = Segment(
            role: copy.role,
            title: copy.title,
            script: copy.script,
            estimatedDuration: copy.estimatedDuration
        )
        withAnimation(DS.Easing.standard(0.35)) {
            project.segments.insert(copy, at: index + 1)
            openSegment = nil
        }
    }

    private func delete(_ index: Int) {
        withAnimation(DS.Easing.standard(0.35)) {
            project.segments.remove(at: index)
            openSegment = nil
        }
    }
}

extension Segment {
    /// The design truncates the blueprint preview at 74 characters.
    var previewText: String {
        script.count > 74 ? String(script.prefix(74)) + "…" : script
    }
}
