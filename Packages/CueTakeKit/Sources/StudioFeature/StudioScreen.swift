import CaptureEngine
import DesignSystem
import Domain
import SwiftUI
import Teleprompter
import UIKit

/// Camera, teleprompter overlay and the shutter. Also hosts recording, since the design keeps the
/// same frame and only swaps the controls.
public struct StudioScreen: View {
    @Bindable private var model: StudioModel

    /// Which camera the preview opens on, from Settings.
    private let camera: CameraPosition
    private let onBack: () -> Void
    private let onOpenEditor: () -> Void
    private let onFinished: () -> Void
    /// Asks for somewhere to write. Only the layer that owns the project knows where that is.
    private let onBeginCapture: () async -> Void
    /// Opens the script screen, for a project with nothing to read. Nil hides the offer.
    private let onWriteScript: (() -> Void)?

    public init(
        model: StudioModel,
        camera: CameraPosition = .front,
        onBack: @escaping () -> Void,
        onOpenEditor: @escaping () -> Void,
        onFinished: @escaping () -> Void,
        onBeginCapture: @escaping () async -> Void = {},
        onWriteScript: (() -> Void)? = nil
    ) {
        self.model = model
        self.camera = camera
        self.onBack = onBack
        self.onOpenEditor = onOpenEditor
        self.onFinished = onFinished
        self.onBeginCapture = onBeginCapture
        self.onWriteScript = onWriteScript
    }

    /// Bumped on every shutter press, so the bloom ring fires once per commit.
    @State private var shutterPresses = 0
    @State private var countdownSweep = false
    @State private var zoomOrigin: Double?

    private var zoomGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { gesture in
                let origin = zoomOrigin ?? model.zoom
                if zoomOrigin == nil { zoomOrigin = origin }
                model.setZoom(origin * gesture.magnification)
            }
            .onEnded { _ in zoomOrigin = nil }
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRequestingCapture = false

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                CameraBackdrop(
                    session: model.cameraAuthorization == .authorized ? model.camera.session : nil
                )
                // The backdrop is behind the prompter, which keeps its own pinch for text size, so
                // the two gestures never meet: pinch the picture to zoom, pinch the panel to size.
                .contentShape(Rectangle())
                .gesture(zoomGesture)
                // When the text is scrolling by itself, a tap moves it on a word — the way to keep
                // up with a reader who is faster than the pace without opening settings mid-take.
                .onTapGesture {
                    if model.phase == .recording, model.prompterMode == .autoScroll {
                        model.nudgeForward()
                    }
                }

                if model.showsGrid {
                    FramingGrid()
                        .transition(.opacity)
                }

                if !model.hasScript, let onWriteScript, model.phase == .idle, model.countdown == nil {
                    emptyPrompter(onWriteScript)
                }

                if model.hasScript {
                    TeleprompterPanel(
                    model: model.teleprompter,
                    frameSize: proxy.size,
                    segmentColor: DS.Palette.segment(
                        at: model.currentSegment?.role.paletteIndex ?? 0
                    )
                )
                }

                topBar
                    .studioTopBarInsets(isLandscape: model.isLandscape)

                controls

                if model.cameraAuthorization == .denied {
                    permissionCard
                }

                if model.teleprompter.isSettingsOpen {
                    settingsSheet(in: proxy.size)
                }

                if model.zoom > 1.01 {
                    zoomReadout
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
        .task { await model.startCamera(position: camera) }
        .onDisappear {
            model.stopTimers()
            model.stopCamera()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.stopTimers() }
            if phase == .active, model.cameraAuthorization == .denied {
                Task { await model.startCamera(position: camera) }
            }
        }
        .alert(String(localized: "studio.capture.error", bundle: .module), isPresented: Binding(
            get: { model.captureError != nil },
            set: { if !$0 { model.captureError = nil } }
        )) {
            Button(String(localized: "studio.dismiss", bundle: .module), role: .cancel) { model.captureError = nil }
            if model.needsCapturePermissions {
                Button(String(localized: "studio.settings.open", bundle: .module)) { openSettings() }
            }
        } message: {
            Text(model.captureError ?? "")
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .complete { onFinished() }
        }
    }

    /// Nothing to read: the prompter is the reason to be here, so its absence is said out loud
    /// rather than leaving the camera looking broken.
    private func emptyPrompter(_ onWriteScript: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.lime)
                Text("studio.noScript.title", bundle: .module)
                    .dsFont(.sans, .semibold, 15)
                    .foregroundStyle(DS.Palette.ink)
            }
            Text("studio.noScript.hint", bundle: .module)
                .dsFont(.sans, .regular, 12, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.6))

            Button(action: onWriteScript) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Text("studio.noScript.write", bundle: .module)
                        .dsFont(.sans, .semibold, 14)
                }
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DS.Palette.lime)
                )
            }
            .buttonStyle(.dsPress(radius: 16))
        }
        .padding(16)
        .frame(maxWidth: 360)
        .dsGlass(
            tint: DS.Palette.glassSheet(0.9),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous),
            border: DS.Palette.hairline(0.14)
        )
        .padding(.horizontal, 22)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Top bar

    @ViewBuilder
    private var topBar: some View {
        if model.phase == .recording || model.phase == .finishing || model.phase == .complete {
            HStack {
                Spacer(minLength: 0)
                if model.phase == .recording { recordingStatus }
                Spacer(minLength: 0)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                DSBackButton(style: .glass, action: onBack)

                Spacer(minLength: 0)

                if model.hasScript { segmentPips }

                cameraControl("arrow.triangle.2.circlepath.camera", label: "studio.camera.flip") {
                    model.flipCamera()
                }

                cameraControl("grid", label: "studio.camera.grid", selected: model.showsGrid) {
                    model.showsGrid.toggle()
                }
                .dsMotion(DS.Motion.snap, reduced: reduceMotion, value: model.showsGrid)
            }
            .disabled(model.phase == .preparing || isRequestingCapture)
        }
    }

    private var segmentPips: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.project.segments.prefix(5).enumerated()), id: \.element.id) { index, segment in
                let isCurrent = index == model.segmentIndex
                Capsule()
                    .fill(
                        isCurrent
                            ? DS.Palette.segment(at: segment.role.paletteIndex)
                            : DS.Palette.hairline(0.28)
                    )
                    // The current one widens rather than brightens: length survives a glance at
                    // arm's length, a colour shift on a 3pt bar does not.
                    .frame(width: isCurrent ? 22 : 16, height: 3)
                    .dsMotion(DS.Motion.settle, reduced: reduceMotion, value: model.segmentIndex)
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

            if model.hasScript {
                progressPips
                prompterBadge
            }
        }
    }

    /// Says how the text is moving, so a prompter that is waiting for a voice is not mistaken for
    /// one that is stuck, and one scrolling by itself is not mistaken for one that is listening.
    private var prompterBadge: some View {
        let mode = model.prompterMode
        return HStack(spacing: 6) {
            Image(systemName: mode == .autoScroll ? "text.line.first.and.arrowtriangle.forward" : "waveform")
                .font(.system(size: 10, weight: .semibold))
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: mode != .autoScroll)
            Text(Self.badgeText(for: mode))
                .dsFont(.mono, .medium, 10, letterSpacing: 0.1)
        }
        .foregroundStyle(mode == .followingVoice ? DS.Palette.lime : DS.Palette.ink(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .dsGlass(tint: DS.Palette.glass(0.5), in: Capsule())
        .contentTransition(.opacity)
        .animation(DS.Motion.settle, value: mode)
    }

    private static func badgeText(for mode: PrompterMode) -> String {
        switch mode {
        case .listening: String(localized: "studio.prompter.listening", bundle: .module)
        case .followingVoice: String(localized: "studio.prompter.following", bundle: .module)
        case .autoScroll: String(localized: "studio.prompter.auto", bundle: .module)
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
                    .overlay(alignment: .top) {
                        if model.reachedEnd {
                            // The script is done; the take is not. Said once, near the button
                            // that ends it, instead of the recording ending by itself mid-sentence.
                            Text("studio.end.hint", bundle: .module)
                                .dsFont(.sans, .semibold, 13)
                                .foregroundStyle(DS.Palette.ink)
                                .fixedSize()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .dsGlass(tint: DS.Palette.glass(0.7), in: Capsule())
                                .offset(y: -58)
                                .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(DS.Motion.bloom, value: model.reachedEnd)
            } trailing: {
                EmptyView()
            }
        } else if model.phase == .finishing || model.phase == .preparing || model.phase == .complete {
            StudioControlCluster(isLandscape: model.isLandscape) {
                EmptyView()
            } center: {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(DS.Palette.ink)
                    Text(String(localized: model.phase == .preparing ? "studio.capture.preparing" : "studio.saving", bundle: .module))
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.ink)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .dsGlass(tint: DS.Palette.glass(0.7), in: Capsule())
                .transition(.scale.combined(with: .opacity))
            } trailing: {
                EmptyView()
            }
        } else {
            StudioControlCluster(isLandscape: model.isLandscape) {
                if model.hasScript {
                    labeledControl("textformat", label: "studio.prompter.settings") {
                        model.teleprompter.isSettingsOpen.toggle()
                    }
                } else {
                    Color.clear.frame(width: 72, height: 68)
                }
            } center: {
                VStack(spacing: 6) {
                    shutter
                    Text("studio.record", bundle: .module)
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.ink)
                }
            } trailing: {
                if model.hasFootage {
                    labeledControl("slider.horizontal.3", label: "studio.editor", action: onOpenEditor)
                } else {
                    Color.clear.frame(width: 72, height: 68)
                }
            }
            .disabled(isRequestingCapture || model.cameraAuthorization != .authorized)
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
        .buttonStyle(StopButtonStyle())
        .accessibilityLabel(Text("studio.stop", bundle: .module))
    }

    private var shutter: some View {
        Button {
            guard !isRequestingCapture else { return }
            isRequestingCapture = true
            shutterPresses += 1
            Task {
                await onBeginCapture()
                isRequestingCapture = false
            }
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
            // Fired outside the pressed state so it plays on the way out, reading as the
            // consequence of the press rather than part of it.
            .overlay {
                if !reduceMotion {
                    BloomRing(trigger: shutterPresses)
                        .frame(width: 94, height: 94)
                }
            }
        }
        .buttonStyle(ShutterButtonStyle())
        .accessibilityLabel(Text("studio.record", bundle: .module))
        .sensoryFeedback(.impact(weight: .medium), trigger: shutterPresses)
    }

    private func cameraControl(_ symbol: String, label: String.LocalizationValue, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(selected ? DS.Palette.lime : DS.Palette.ink)
                .frame(width: 44, height: 44)
                .dsGlass(in: Circle())
        }
        .buttonStyle(.dsPressIcon)
        .accessibilityLabel(Text(String(localized: label, bundle: .module)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func labeledControl(_ symbol: String, label: String.LocalizationValue, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 48, height: 48)
                    .dsGlass(in: Circle())
                Text(String(localized: label, bundle: .module))
                    .dsFont(.sans, .medium, 11)
                    .lineLimit(1)
            }
            .foregroundStyle(DS.Palette.ink)
            .frame(width: 72)
        }
        .buttonStyle(.dsPressIcon)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var permissionCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28))
            Text("studio.camera.permission", bundle: .module)
                .dsFont(.archivo, .bold, 20)
            Text("studio.camera.permission.detail", bundle: .module)
                .dsFont(.sans, .regular, 14)
                .multilineTextAlignment(.center)
            Button(action: openSettings) {
                Text("studio.settings.open", bundle: .module)
                    .dsFont(.sans, .semibold, 14)
                    .padding(14)
                    .background(Capsule().fill(DS.Palette.lime))
                    .foregroundStyle(DS.Palette.inkInverse)
            }
            .buttonStyle(.dsPress)
        }
        .foregroundStyle(DS.Palette.ink)
        .padding(24)
        .frame(maxWidth: 340)
        .dsGlass(in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 24)
    }

    /// Only while it is not 1x. A zoom indicator that is always on screen is one more thing to
    /// read; one that appears when you have changed something is information.
    private var zoomReadout: some View {
        Text(String(format: "%.1f×", model.zoom))
            .dsFont(.mono, .medium, 11)
            .foregroundStyle(DS.Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .dsGlass(in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, model.isLandscape ? 24 : 150)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    /// Covers the frame while the count runs. Tapping anywhere cancels, because the moment you
    /// need that is the moment you have just realised the phone is pointing at the ceiling.
    private func countdownOverlay(_ value: Int) -> some View {
        ZStack {
            Rectangle()
                .fill(DS.Palette.inkInverse(0.45))

            ZStack {
                // Empties once per second. The count is the only place in the studio where the
                // reader is waiting rather than doing, so it is the one place that owes them a
                // sense of how long is left.
                Circle()
                    .stroke(DS.Palette.ink(0.15), lineWidth: 3)
                    .frame(width: 168, height: 168)

                Circle()
                    .trim(from: 0, to: countdownSweep ? 0 : 1)
                    .stroke(DS.Palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 168, height: 168)
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: countdownSweep)

                Text("\(value)")
                    .dsFont(.archivo, .extrabold, 96)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText(countsDown: true))
                    .shadow(color: .black.opacity(0.5), radius: 30)
                    .id(value)
                    .transition(
                        .scale(scale: 1.35).combined(with: .opacity)
                    )
            }
            .onAppear { countdownSweep = true }
            .onDisappear { countdownSweep = false }

            Text("studio.countdown.cancel", bundle: .module)
                .dsFont(.sans, .medium, 12)
                .foregroundStyle(DS.Palette.ink(0.6))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 60)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { model.cancelCountdown() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("studio.countdown.cancel", bundle: .module))
        .accessibilityValue(Text("\(value)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.cancelCountdown() }
        .dsMotion(DS.Motion.bloom, reduced: reduceMotion, value: value)
        .transition(.opacity)
    }

    /// Portrait docks the sheet above the controls; landscape pins it beside the right-hand column.
    ///
    /// Two things were wrong here and both came from the same assumption — that the sheet is
    /// small. It is not: it carries presets, two tabs, sliders and two segmented rows, and on a
    /// short phone it ran straight through the prompter panel behind it and under the shutter
    /// below it. So it scrolls, it is capped at a fraction of the window, and it sits on a scrim.
    ///
    /// The scrim is the important part. It separates the sheet from the picture behind it, and it
    /// gives the sheet the one gesture every panel of this kind needs: tap anywhere else to put it
    /// away. Without it the only way out was the same small button that opened it.
    @ViewBuilder
    private func settingsSheet(in frame: CGSize) -> some View {
        ZStack {
            Rectangle()
                .fill(DS.Palette.inkInverse(0.42))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(DS.Motion.settle) { model.teleprompter.isSettingsOpen = false }
                }
                .transition(.opacity)

            sheetBody(in: frame)
        }
    }

    @ViewBuilder
    private func sheetBody(in frame: CGSize) -> some View {
        if model.isLandscape {
            scrollingSheet(maxHeight: frame.height - 28)
                .frame(width: 290)
                .padding(.vertical, 14)
                .padding(.trailing, 124)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        } else {
            // 116pt clears the control cluster; the cap keeps the top of the sheet clear of the
            // top bar on the shortest phone we support.
            scrollingSheet(maxHeight: frame.height - 116 - 96)
                .padding(.horizontal, 14)
                .padding(.bottom, 116)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func scrollingSheet(maxHeight: CGFloat) -> some View {
        ScrollView {
            TeleprompterSettingsSheet(model: model.teleprompter)
        }
        .scrollIndicators(.hidden)
        // Only scrolls when it has to, so a sheet that fits keeps its own height instead of
        // stretching to fill the allowance.
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: max(220, maxHeight))
    }
}
