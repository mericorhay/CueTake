import CaptureEngine
import AVKit
import AVFoundation
import AVFAudio
import Foundation
import DesignSystem
import Domain
import Observation
import SpeechEngine
import SwiftUI
import Teleprompter
import UIKit

/// Re-records exactly one segment. The rest of the cut is never touched — that is the whole point
/// of the Segment → Take model, and this screen is where the user sees it.
@MainActor
@Observable
public final class RetakeModel {
    public enum State: Sendable {
        case ready
        case rolling
        case compare
    }

    public enum Choice: String, Sendable {
        case old
        case new
    }

    public private(set) var state: State = .ready
    public private(set) var wordIndex = 0
    /// Seconds left before rolling, or nil when no countdown is running.
    public private(set) var countdown: Int?
    public var choice: Choice = .new

    public let segment: Segment
    /// The reader's prompter settings, the same ones the studio uses. Read, never changed here.
    public let prompter = TeleprompterModel()
    /// What the rest of the project was shot at, so a retake matches it.
    public var format: VideoFormat = .vertical1080
    private var task: Task<Void, Never>?

    public let camera = CameraSession()
    public private(set) var cameraAuthorization: CaptureAuthorization = .notDetermined
    /// The file this retake produced, for whoever owns the project to fold in.
    public private(set) var lastCapture: (url: URL, duration: Double)?
    private var recordingURL: URL?
    private var recordingStart: Date?

    public func startCamera(position: CameraPosition) async {
        let status = await CameraSession.requestAuthorization(includingMicrophone: false)
        cameraAuthorization = status.camera
        guard status.camera == .authorized else { return }
        camera.start(camera: position)
        camera.apply(format)
    }

    public func stopCamera() {
        camera.stop()
    }

    private let driver: PrompterDriver
    /// The file is being closed. "Keep" waits for it: keeping a take that has not been written yet
    /// keeps nothing.
    public private(set) var isSaving = false
    public private(set) var isStarting = false
    public var captureError: String?
    public private(set) var needsCapturePermissions = false
    public var originalRecordingURL: URL?

    public func prepareCapture() async -> Bool {
        guard !isStarting, !isSaving, state == .ready else { return false }
        isStarting = true
        captureError = nil
        needsCapturePermissions = false
        let status = await CameraSession.requestAuthorization(includingMicrophone: true)
        guard isStarting else { return false }
        cameraAuthorization = status.camera
        guard status.camera == .authorized, status.microphone == .authorized else {
            needsCapturePermissions = true
            failCapture("studio.capture.permissions")
            return false
        }
        return true
    }

    public func failCapture(_ key: String.LocalizationValue) {
        captureError = String(localized: key, bundle: .module)
        countdown = nil
        isStarting = false
        state = .ready
    }

    /// - Parameter localeIdentifier: the project's language, for listening to the reader.
    public init(segment: Segment, localeIdentifier: String = Locale.current.identifier, speech: any SpeechTranscribing = SystemSpeechTranscriber()) {
        self.segment = segment
        driver = PrompterDriver(scripts: [segment.script], localeIdentifier: localeIdentifier, speech: speech)
        driver.onMove = { [weak self] position in
            guard let self, state == .rolling else { return }
            wordIndex = position.word
        }
        let hint = min(max(segment.teleprompter.speedMultiplier, 0.25), 4)
        driver.speedMultiplier = { [weak self] in
            guard let self else { return 1 }
            return (0.6 + self.prompter.speed / 100) * hint
        }
        prompter.targetPace = SpeakingRate.wordsPerMinute(forLocaleIdentifier: localeIdentifier)
    }

    /// Terms the recogniser should expect beyond the script's own, such as the brand's name.
    public func setSpeechHints(_ hints: [String]) {
        driver.extraHints = hints
    }

    /// How fast the voice is reading, and what that means, while it is followed.
    public var paceVerdict: PaceMeter.Verdict? {
        guard prompter.coachesPace, let pace = driver.wordsPerMinute else { return nil }
        return PaceMeter.verdict(pace, target: prompter.targetPace)
    }

    public var wordsPerMinute: Double? { driver.wordsPerMinute }

    /// The script as it is read, without the writer's emphasis marks.
    public var readableScript: String {
        words.map { ScriptText.emphasis($0).text }.joined(separator: " ")
    }

    /// Roughly how long the line takes to say.
    public var estimatedSeconds: Double {
        ScriptTiming.remainingSeconds(scripts: [segment.script], segment: 0, word: -1, wordsPerMinute: prompter.targetPace)
    }

    /// The last word has been reached; the take rolls on until stop.
    public var reachedEnd: Bool { driver.reachedEnd }

    public var isFollowingVoice: Bool { driver.mode == .following }

    public var words: [String] {
        ScriptText.words(in: segment.script).map(String.init)
    }

    /// Rolls, with the text following the reader's voice — or a real speaking pace when the voice
    /// cannot be heard. It used to run a 130 ms timer and stop the take when the words ran out.
    public func start(writingTo url: URL? = nil) {
        guard isStarting, state == .ready else { return }
        guard let url else { failCapture("studio.capture.storage"); return }
        let seconds = prompter.countdown
        task?.cancel()
        task = Task { [weak self] in
            // The same countdown as the studio: time to get back into frame.
            for left in stride(from: seconds, to: 0, by: -1) {
                guard let model = self, model.isStarting else { return }
                model.countdown = left
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            guard let self else { return }
            countdown = nil
            guard isStarting else { return }
            let started = await camera.startRecording(to: url)
            guard isStarting else {
                if started { _ = await camera.stopRecording() }
                return
            }
            guard started else { failCapture("studio.capture.failed"); return }
            isStarting = false
            didStart(to: url)
        }
    }

    private func didStart(to url: URL) {
        state = .rolling
        choice = .new
        wordIndex = 0
        lastCapture = nil

        recordingURL = url
        recordingStart = .now
        driver.start(camera: camera)
    }

    public func stop() {
        finish()
    }

    /// Cancels the running timer without touching what is already on screen, the way the design
    /// clears its intervals on every navigation.
    public func stopTimers() {
        isStarting = false
        countdown = nil
        task?.cancel()
        task = nil
        if state == .rolling { finish() }
    }

    public func redo() {
        guard !isSaving, !isStarting else { return }
        task?.cancel()
        task = nil
        state = .ready
        wordIndex = 0
        lastCapture = nil
    }

    private func finish() {
        guard state == .rolling, !isSaving else { return }
        task?.cancel()
        task = nil
        driver.stop(camera: camera)

        let elapsed = recordingStart.map { Date.now.timeIntervalSince($0) } ?? 0
        let wasRecording = recordingURL != nil
        recordingURL = nil
        recordingStart = nil
        if wasRecording {
            isSaving = true
            Task { [weak self] in
                let url = await self?.camera.stopRecording()
                guard let self else { return }
                if let url {
                    lastCapture = (url, elapsed)
                } else {
                    failCapture("studio.capture.saveFailed")
                }
                isSaving = false
            }
        }
        state = .compare
    }
}

public struct RetakeScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var previewPlayer: AVPlayer?
    @Bindable private var model: RetakeModel
    private let camera: CameraPosition
    /// Same arrangement as the studio: the screen asks, the project's owner answers with a path.
    private let onBeginCapture: () async -> Void
    private let onBack: () -> Void
    private let onKeep: (RetakeModel.Choice) -> Void

    public init(
        model: RetakeModel,
        camera: CameraPosition = .front,
        onBeginCapture: @escaping () async -> Void = {},
        onBack: @escaping () -> Void,
        onKeep: @escaping (RetakeModel.Choice) -> Void
    ) {
        self.model = model
        self.camera = camera
        self.onBeginCapture = onBeginCapture
        self.onBack = onBack
        self.onKeep = onKeep
    }

    private var segmentColor: Color {
        DS.Palette.segment(at: model.segment.role.paletteIndex)
    }

    public var body: some View {
        ZStack {
            CameraBackdrop(
                session: model.cameraAuthorization == .authorized ? model.camera.session : nil
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    DSBackButton(size: 34, fontSize: 15, style: .glass, action: onBack)
                        .disabled(model.state == .rolling || model.isSaving || model.isStarting)
                    DSKicker(
                        String(localized: "retake.kicker \(model.segment.role.displayLabel)", bundle: .module),
                        color: DS.Palette.ink(0.55)
                    )
                }

                Spacer(minLength: 0)

                switch model.state {
                case .ready: readyState
                case .rolling: rollingState
                case .compare: compareState
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 58)
            .padding(.bottom, 36)
            .dsScreenLayout(scrolls: true)
        }
        .task { await model.startCamera(position: camera) }
        .onDisappear { previewPlayer?.pause(); model.stopTimers(); model.stopCamera() }
        .onChange(of: model.state) { _, state in
            if state == .compare {
                if !model.isSaving { model.stopCamera() }
                preparePreview()
            } else if state == .ready {
                previewPlayer?.pause()
                previewPlayer = nil
                Task { await model.startCamera(position: camera) }
            }
        }
        .onChange(of: model.choice) { _, _ in preparePreview() }
        .onChange(of: model.isSaving) { _, saving in
            if !saving, model.state == .compare { model.stopCamera(); preparePreview() }
        }
        .onChange(of: model.originalRecordingURL) { _, _ in preparePreview() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.stopTimers() }
            if phase == .active, model.state == .ready, model.cameraAuthorization == .denied {
                Task { await model.startCamera(position: camera) }
            }
        }
        .alert(String(localized: "studio.capture.error", bundle: .module), isPresented: Binding(
            get: { model.captureError != nil },
            set: { if !$0 { model.captureError = nil } }
        )) {
            Button(String(localized: "studio.dismiss", bundle: .module), role: .cancel) { model.captureError = nil }
            if model.needsCapturePermissions {
                Button(String(localized: "studio.settings.open", bundle: .module)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        } message: { Text(model.captureError ?? "") }
        .dsEnter(.screen())
    }

    // MARK: - Ready

    private var readyState: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                DSKicker(
                    "\(model.segment.role.displayLabel) · \(Int(model.segment.barWeight))s",
                    size: 9,
                    color: segmentColor
                )

                Text(model.readableScript)
                    .dsFont(.sans, .regular, 17, lineHeight: 1.45)
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.top, 10)

                Text("retake.note", bundle: .module)
                    .dsFont(.sans, .regular, 12)
                    .foregroundStyle(DS.Palette.ink(0.52))
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .dsGlass(
                tint: DS.Palette.glass(0.62),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous),
                border: DS.Palette.hairline(0.13)
            )
            .padding(.bottom, 20)

            Button {
                Task { await onBeginCapture() }
            } label: {
                ZStack {
                    RecordRing().frame(width: 92, height: 92)
                    Circle()
                        .fill(DS.Palette.hairline(0.1))
                        .overlay(Circle().stroke(DS.Palette.hairline(0.55), lineWidth: 3))
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(DS.Palette.accent)
                        .frame(width: 58, height: 58)
                        .shadow(color: DS.Palette.accent(0.6), radius: 15)
                }
            }
            .buttonStyle(.dsPress)
            .disabled(model.isStarting)
            .accessibilityLabel(Text("studio.record", bundle: .module))
            if let countdown = model.countdown {
                HStack(spacing: 10) {
                    Text(verbatim: "\(countdown)")
                        .dsFont(.archivo, .bold, 34)
                        .foregroundStyle(DS.Palette.ink)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(DS.Motion.snap, value: countdown)
                    Button {
                        model.stopTimers()
                    } label: {
                        Text("studio.countdown.cancel", bundle: .module)
                            .dsFont(.sans, .semibold, 13)
                            .foregroundStyle(DS.Palette.ink(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .dsGlass(tint: DS.Palette.glass(0.7), in: Capsule())
                    }
                    .buttonStyle(.dsPress)
                }
                .padding(.top, 12)
            } else if model.isStarting {
                ProgressView(String(localized: "studio.capture.preparing", bundle: .module))
                    .tint(DS.Palette.ink)
                    .padding(.top, 12)
            }
        }
        .dsEnter(.rise(duration: 0.4))
    }

    // MARK: - Rolling

    private var rollingState: some View {
        VStack(spacing: 0) {
            // The same prompter as the studio, with the reader's own settings, so a retake reads
            // exactly like the take it replaces.
            PrompterScript(
                words: TeleprompterModel.wordStyles(
                    script: model.segment.script,
                    active: model.wordIndex,
                    mode: model.prompter.mode,
                    lookAhead: model.prompter.lookAhead,
                    accent: DS.Palette.accent,
                    ink: DS.Palette.ink,
                    inkInverse: DS.Palette.inkInverse,
                    lime: DS.Palette.lime
                ),
                activeIndex: model.wordIndex,
                textSize: min(max(model.prompter.textSize, 17), 40),
                isCentered: model.prompter.alignment == .center,
                readingLine: model.prompter.readingLine,
                isMirrored: model.prompter.isMirrored,
                notes: model.segment.teleprompter.speakerNotes,
                lineColor: segmentColor
            )
            .frame(height: 220)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .dsGlass(
                tint: DS.Palette.glass(0.62),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous),
                border: DS.Palette.accent(0.4)
            )
            .padding(.bottom, model.reachedEnd ? 10 : 20)

            if let verdict = model.paceVerdict, verdict != .good {
                Group {
                    if verdict == .fast {
                        Text("retake.pace.fast", bundle: .module)
                    } else {
                        Text("retake.pace.slow", bundle: .module)
                    }
                }
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(verdict == .fast ? DS.Palette.accent : DS.Palette.accentWarm)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .dsGlass(tint: DS.Palette.glass(0.7), in: Capsule())
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }

            if model.reachedEnd {
                Text("studio.end.hint", bundle: .module)
                    .dsFont(.sans, .semibold, 13)
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .dsGlass(tint: DS.Palette.glass(0.7), in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }

            Button {
                model.stop()
            } label: {
                ZStack {
                    Circle()
                        .fill(DS.Palette.hairline(0.1))
                        .overlay(Circle().stroke(DS.Palette.hairline(0.6), lineWidth: 3))
                        .frame(width: 76, height: 76)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DS.Palette.accent)
                        .frame(width: 26, height: 26)
                        .dsPulse(duration: 1.6)
                }
            }
            .buttonStyle(.dsPress)
        }
        .animation(DS.Motion.bloom, value: model.reachedEnd)
        .dsEnter(.rise(duration: 0.4))
    }

    // MARK: - Compare

    private var compareState: some View {
        VStack(spacing: 0) {
            if model.isSaving {
                ProgressView(String(localized: "studio.saving", bundle: .module))
                    .tint(DS.Palette.ink)
                    .padding(.bottom, 14)
            }
            if let previewPlayer {
                VideoPlayer(player: previewPlayer)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.bottom, 14)
            } else if !model.isSaving {
                Text("retake.preview.unavailable", bundle: .module)
                    .dsFont(.sans, .regular, 13)
                    .foregroundStyle(DS.Palette.ink(0.7))
                    .padding(.bottom, 14)
            }
            HStack(spacing: 8) {
                takeCard(
                    .old,
                    kicker: String(localized: "retake.take.old.kicker", bundle: .module),
                    title: String(localized: "retake.take.old.title", bundle: .module),
                    meta: model.segment.selectedTake?.sourceRange.duration.preciseTimecode
                        ?? String(localized: "retake.noPrevious", bundle: .module)
                )
                takeCard(
                    .new,
                    kicker: String(localized: "retake.take.new.kicker", bundle: .module),
                    title: String(localized: "retake.take.new.title", bundle: .module),
                    meta: model.lastCapture.map { MediaTime(seconds: $0.duration).preciseTimecode }
                        ?? String(localized: "studio.saving", bundle: .module)
                )
            }
            .padding(.bottom, 14)

            FlexRow(spacing: 10, weights: [1, 1.3]) {
                DSSecondaryButton(
                    String(localized: "retake.shootAgain", bundle: .module),
                    verticalPadding: 16
                ) {
                    model.redo()
                }
                .disabled(model.isSaving)

                DSPrimaryButton(
                    String(
                        localized: model.choice == .new ? "retake.keep.new" : "retake.keep.old",
                        bundle: .module
                    ),
                    verticalPadding: 16,
                    glow: false
                ) {
                    onKeep(model.choice)
                }
                // Keeping the new take waits for its file to be closed.
                .disabled(model.isSaving || (model.choice == .new && model.lastCapture == nil))
                .opacity(model.isSaving ? 0.5 : 1)
            }
        }
        .dsEnter(.rise(duration: 0.4))
    }

    /// Preview only the source range being replaced, rather than the rest of its recording.
    private func preparePreview() {
        previewPlayer?.pause()
        previewPlayer = nil
        guard model.state == .compare, !model.isSaving else { return }
        let url = model.choice == .old ? model.originalRecordingURL : model.lastCapture?.url
        guard let url else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            model.captureError = String(localized: "retake.preview.audio", bundle: .module)
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        if model.choice == .old, let range = model.segment.selectedTake?.sourceRange {
            item.forwardPlaybackEndTime = CMTime(seconds: range.end.seconds, preferredTimescale: 600)
            item.reversePlaybackEndTime = CMTime(seconds: range.start.seconds, preferredTimescale: 600)
            player.seek(to: CMTime(seconds: range.start.seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        previewPlayer = player
    }

    private func takeCard(
        _ choice: RetakeModel.Choice,
        kicker: String,
        title: String,
        meta: String
    ) -> some View {
        let isOn = model.choice == choice

        return Button {
            withAnimation(DS.Easing.ease(0.3)) { model.choice = choice }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker)
                    .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
                    .foregroundStyle(DS.Palette.ink(0.56))
                Text(title)
                    .dsFont(.archivo, .bold, 16)
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.top, 5)
                Text(meta)
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.ink(0.56))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .dsGlass(
                tint: isOn ? DS.Palette.accent(0.16) : DS.Palette.glass(0.6),
                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous),
                border: isOn ? DS.Palette.accent : DS.Palette.hairline(0.12)
            )
        }
        .buttonStyle(.dsPress)
        .disabled(choice == .old && model.segment.selectedTake == nil)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
