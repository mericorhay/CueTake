import DesignSystem
import Domain
import SwiftUI
import Teleprompter

/// Camera, teleprompter overlay and the shutter. Also hosts recording, since the design keeps the
/// same frame and only swaps the controls.
public struct StudioScreen: View {
    @Bindable private var model: StudioModel

    private let onBack: () -> Void
    private let onOpenEditor: () -> Void
    private let onFinished: () -> Void

    public init(
        model: StudioModel,
        onBack: @escaping () -> Void,
        onOpenEditor: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.model = model
        self.onBack = onBack
        self.onOpenEditor = onOpenEditor
        self.onFinished = onFinished
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                CameraBackdrop()

                TeleprompterPanel(
                    model: model.teleprompter,
                    frameSize: proxy.size,
                    segmentColor: DS.Palette.segment(
                        at: model.currentSegment?.role.paletteIndex ?? 0
                    )
                )

                topBar
                    .frame(maxHeight: .infinity, alignment: .top)

                controls
                    .frame(maxHeight: .infinity, alignment: .bottom)

                if model.teleprompter.isSettingsOpen {
                    TeleprompterSettingsSheet(model: model.teleprompter)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 116)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .background(DS.Palette.screen)
        .dsEnter(.screen(duration: 0.5))
        .onChange(of: model.phase) { _, phase in
            if phase == .complete { onFinished() }
        }
    }

    // MARK: - Top bar

    @ViewBuilder
    private var topBar: some View {
        if model.phase == .recording {
            recordingStatus
                .padding(.horizontal, 18)
                .padding(.top, 56)
        } else {
            HStack(alignment: .top, spacing: 10) {
                DSCircleButton("←", style: .glass, action: onBack)

                Spacer(minLength: 0)

                segmentPips

                DSCircleButton("⟲", fontSize: 14, style: .glass) {
                    model.isLandscape.toggle()
                    model.teleprompter.setLandscape(model.isLandscape)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 56)
        }
    }

    private var segmentPips: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.project.segments.enumerated()), id: \.element.id) { index, segment in
                Capsule()
                    .fill(
                        index == 0
                            ? DS.Palette.segment(at: segment.role.paletteIndex)
                            : DS.Palette.hairline(0.28)
                    )
                    .frame(width: 16, height: 3)
            }

            Text(model.project.estimatedTotalLabel)
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.7))
                .padding(.leading, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .dsGlass(in: Capsule())
    }

    private var recordingStatus: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                Circle()
                    .fill(DS.Palette.accent)
                    .frame(width: 8, height: 8)
                    .dsBlink()

                Text(model.elapsedLabel)
                    .dsFont(.mono, .medium, 13)
                    .foregroundStyle(DS.Palette.ink)

                Text(model.currentSegment?.role.displayLabel ?? "")
                    .dsFont(.mono, .medium, 10, letterSpacing: 0.1)
                    .foregroundStyle(DS.Palette.ink(0.55))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(DS.Palette.accent(0.16)))
            .overlay(Capsule().stroke(DS.Palette.accent(0.45), lineWidth: 1))

            progressPips
        }
    }

    private var progressPips: some View {
        GeometryReader { proxy in
            let weights = model.project.segments.map(\.barWeight)
            let total = max(1, weights.reduce(0, +))
            let gaps = CGFloat(max(0, weights.count - 1)) * 4

            HStack(spacing: 4) {
                ForEach(Array(model.project.segments.enumerated()), id: \.element.id) { index, segment in
                    let width = (proxy.size.width - gaps) * (weights[index] / total)
                    Capsule()
                        .fill(DS.Palette.hairline(0.16))
                        .frame(width: width, height: 3)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(DS.Palette.segment(at: segment.role.paletteIndex))
                                .frame(width: width * model.progress(forSegmentAt: index))
                                .animation(.linear(duration: 0.12), value: model.wordIndex)
                        }
                }
            }
        }
        .frame(width: model.isLandscape ? 380 : 250, height: 3)
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        if model.phase == .recording {
            Button {
                model.stopRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(DS.Palette.hairline(0.1))
                        .overlay(Circle().stroke(DS.Palette.hairline(0.6), lineWidth: 3))
                        .frame(width: 76, height: 76)

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DS.Palette.accent)
                        .frame(width: 28, height: 28)
                        .dsPulse(duration: 1.6)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 30)
        } else {
            HStack {
                DSCircleButton("Aa", size: 48, fontSize: 15, style: .glass) {
                    model.teleprompter.isSettingsOpen.toggle()
                }

                Spacer(minLength: 0)

                shutter

                Spacer(minLength: 0)

                DSCircleButton("⤢", size: 48, fontSize: 17, style: .glass, action: onOpenEditor)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 30)
        }
    }

    private var shutter: some View {
        Button {
            model.startRecording()
        } label: {
            ZStack {
                RecordRing()
                    .frame(width: 94, height: 94)

                Circle()
                    .fill(DS.Palette.hairline(0.1))
                    .overlay(Circle().stroke(DS.Palette.hairline(0.55), lineWidth: 3))
                    .frame(width: 82, height: 82)

                Circle()
                    .fill(DS.Palette.accent)
                    .frame(width: 60, height: 60)
                    .shadow(color: DS.Palette.accent(0.6), radius: 16)
            }
        }
        .buttonStyle(.plain)
    }
}
