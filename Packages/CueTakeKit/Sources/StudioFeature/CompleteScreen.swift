import DesignSystem
import Domain
import SwiftUI

/// Shown over the camera the moment the take finishes.
public struct CompleteScreen: View {
    private let project: Project
    private let onRetake: (Segment.ID) -> Void
    @State private var showsRetakePicker = false
    private let onEdit: () -> Void
    private let onDone: () -> Void

    public init(
        project: Project,
        onRetake: @escaping (Segment.ID) -> Void,
        onEdit: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.project = project
        self.onRetake = onRetake
        self.onEdit = onEdit
        self.onDone = onDone
    }

    public var body: some View {
        ZStack {
            CameraBackdrop()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                DSKicker(
                    String(localized: "complete.ready", bundle: .module),
                    color: DS.Palette.lime
                )

                DSHeadline(
                    String(localized: "complete.recorded \(project.segments.filter { $0.selectedTake != nil }.count)", bundle: .module),
                    size: 32
                )
                .padding(.top, 10)
                .padding(.bottom, 22)

                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        ForEach(project.segments) { segment in
                            segmentChip(segment)
                                .frame(minWidth: 90)
                        }
                    }
                }
                .frame(height: 56)
                .padding(.bottom, 16)

                DSPrimaryButton(
                    String(localized: "complete.review", bundle: .module),
                    glow: false,
                    action: onEdit
                )
                .padding(.bottom, 10)

                HStack(spacing: 10) {
                    DSSecondaryButton(
                        String(localized: "complete.retake", bundle: .module),
                        action: { showsRetakePicker = true }
                    )
                    DSSecondaryButton(
                        String(localized: "complete.export", bundle: .module),
                        action: onDone
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .dsScreenLayout(scrolls: true)
        }
        .dsEnter(.screen(duration: 0.5))
        .confirmationDialog(String(localized: "complete.chooseSegment", bundle: .module), isPresented: $showsRetakePicker, titleVisibility: .visible) {
            ForEach(Array(project.segments.enumerated()), id: \.element.id) { index, segment in
                Button("\(index + 1) · \(segment.role.displayLabel)") { onRetake(segment.id) }
            }
        }
    }

    private func segmentChip(_ segment: Segment) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(segment.role.displayLabel)
                .dsFont(.mono, .medium, 9)
                .foregroundStyle(DS.Palette.segment(at: segment.role.paletteIndex))
            Text(segment.selectedTake.map { $0.sourceRange.duration.preciseTimecode }
                ?? String(localized: "complete.notRecorded", bundle: .module))
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 52)
        .dsGlass(
            tint: DS.Palette.glass(0.6),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous),
            border: DS.Palette.hairline(0.1)
        )
    }
}
