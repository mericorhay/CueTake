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

                if model.showsGrid {
                    FramingGrid()
                        .transition(.opacity)
                }

                TeleprompterPanel(
                    model: model.teleprompter,
                    frameSize: proxy.size,
                    segmentColor: DS.Palette.segment(
                        at: model.currentSegment?.role.paletteIndex ?? 0
                    )
                )

                topBar
                    .studioTopBarInsets(isLandscape: model.isLandscape)

                controls

                if model.teleprompter.isSettingsOpen {
                    settingsSheet
                }

                if let countdown = model.countdown {
                    countdownOverlay(countdown)
                }
            }
            // The window's shape is the orientation. `onChange` alone misses the case where the
            // studio is opened with the phone already on its side.
            .onAppear { model.setLandscape(proxy.size.width > proxy.size.height) }
            .onChange(of: proxy.size) { _, size in
                model.setLandscape(size.width > size.height)
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
            HStack {
                Spacer(minLength: 0)
                recordingStatus
                Spacer(minLength: 0)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                DSCircleButton("←", style: .glass, action: onBack)

                Spacer(minLength: 0)

                segmentPips

                DSCircleButton("⊞", fontSize: 15, style: .glass) {
                    withAnimation(DS.Easing.ease(0.25)) { model.showsGrid.toggle() }
                }

                DSCircleButton("⟲", fontSize: 14, style: .glass) {
                    model.setLandscape(!model.isLandscape)
                }
            }
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
            StudioControlCluster(isLandscape: model.isLandscape) {
                EmptyView()
            } center: {
                stopButton
            } trailing: {
                EmptyView()
            }
        } else {
            StudioControlCluster(isLandscape: model.isLandscape) {
                DSCircleButton("Aa", size: 48, font: DS.archivo(.semibold, 15), style: .glass) {
                    model.teleprompter.isSettingsOpen.toggle()
                }
            } center: {
                shutter
            } trailing: {
                DSCircleButton("⤢", size: 48, fontSize: 17, style: .glass, action: onOpenEditor)
            }
        }
    }

    private var stopButton: some View {
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
        .buttonStyle(.dsPressIcon)
    }

    private var shutter: some View {
        Button {
            model.beginCountdown()
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
        .buttonStyle(.dsPressIcon)
    }

    /// Covers the frame while the count runs. Tapping anywhere cancels, because the moment you
    /// need that is the moment you have just realised the phone is pointing at the ceiling.
    private func countdownOverlay(_ value: Int) -> some View {
        ZStack {
            Rectangle()
                .fill(DS.Palette.inkInverse(0.45))

            Text("\(value)")
                .dsFont(.archivo, .extrabold, 96)
                .foregroundStyle(DS.Palette.ink)
                .contentTransition(.numericText(countsDown: true))
                .shadow(color: .black.opacity(0.5), radius: 30)

            Text("studio.countdown.cancel", bundle: .module)
                .dsFont(.sans, .medium, 12)
                .foregroundStyle(DS.Palette.ink(0.6))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 60)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { model.cancelCountdown() }
        .animation(DS.Easing.standard(0.3), value: value)
        .transition(.opacity)
    }

    /// Portrait docks the sheet above the controls; landscape pins it beside the right-hand column.
    @ViewBuilder
    private var settingsSheet: some View {
        if model.isLandscape {
            TeleprompterSettingsSheet(model: model.teleprompter)
                .frame(width: 290)
                .padding(.vertical, 14)
                .padding(.trailing, 124)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        } else {
            TeleprompterSettingsSheet(model: model.teleprompter)
                .padding(.horizontal, 14)
                .padding(.bottom, 116)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}
