import DesignSystem
import Domain
import SwiftUI

/// Shown over the camera the moment the take finishes.
public struct CompleteScreen: View {
    private let project: Project
    private let onRetake: () -> Void
    private let onEdit: () -> Void
    private let onDone: () -> Void

    public init(
        project: Project,
        onRetake: @escaping () -> Void,
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
                    String(localized: "complete.kicker \(project.estimatedTotalLabel)", bundle: .module),
                    color: DS.Palette.lime
                )

                DSHeadline(
                    String(localized: "complete.title \(project.segments.count)", bundle: .module),
                    size: 32
                )
                .padding(.top, 10)
                .padding(.bottom, 22)

                HStack(spacing: 9) {
                    ForEach(project.segments) { segment in
                        segmentChip(segment)
                    }
                }
                .padding(.bottom, 16)

                HStack(spacing: 10) {
                    DSSecondaryButton(
                        String(localized: "complete.retake", bundle: .module),
                        action: onRetake
                    )
                    DSSecondaryButton(
                        String(localized: "complete.edit", bundle: .module),
                        action: onEdit
                    )
                    DSPrimaryButton(
                        String(localized: "complete.done", bundle: .module),
                        glow: false,
                        action: onDone
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .dsEnter(.screen(duration: 0.5))
    }

    private func segmentChip(_ segment: Segment) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(segment.role.displayLabel)
                .dsFont(.mono, .medium, 9)
                .foregroundStyle(DS.Palette.segment(at: segment.role.paletteIndex))
            Text("\(Int(segment.barWeight))s")
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
