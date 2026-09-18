import AVFoundation
import AVKit
import CoreMedia
import SwiftUI
import UIKit

/// The floating window: Picture in Picture fed by the engine's display layer.
///
/// Its buttons are the system's — play and pause, and the two skip buttons — so they steer the
/// flow: pause stops the words, the skips move a card back or forward, and forward at the ad lets
/// it start now.
@MainActor
final class SuflorPiP: NSObject {
    private(set) var controller: AVPictureInPictureController?
    private let engine: SuflorEngine
    private let delegate: PlaybackDelegate
    private var possibleObservation: NSKeyValueObservation?
    private var fellBack = false
    private var observers: [NSObjectProtocol] = []
    /// Silence, played for real: iOS keeps an app running behind another only while it is making
    /// sound. Without it the phone puts us to sleep the moment a camera opens, and the window,
    /// which we draw ourselves, goes black and stops answering its buttons.
    private var keepAlive = SuflorKeepAlive()

    /// Tells the stage when the window opens and closes, and whether it can.
    var onActiveChange: ((Bool) -> Void)?
    var onPossibleChange: ((Bool) -> Void)?

    init(engine: SuflorEngine) {
        self.engine = engine
        delegate = PlaybackDelegate(engine: engine)
        super.init()
    }

    var isActive: Bool { controller?.isPictureInPictureActive ?? false }
    var isPossible: Bool { controller?.isPictureInPicturePossible ?? false }

    /// Makes the controller once the display layer is on screen: before that it is never possible.
    func attach() {
        guard controller == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        Self.activateAudio(mixing: true)
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: engine.displayLayer, playbackDelegate: delegate)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = delegate
        controller.requiresLinearPlayback = false
        // Leaving the app — for TikTok, for Instagram — floats the window by itself.
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        delegate.onActiveChange = { [weak self] active in
            Task { @MainActor in self?.onActiveChange?(active) }
        }
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor in self?.possibleChanged(possible) }
        }
        self.controller = controller
        keepAlive.start()
        watchAudio()
    }

    /// Instagram's camera, a call, Siri: each takes the sound, and ours stays off unless it is
    /// asked back. Without it the window's buttons stop answering.
    private func watchAudio() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let mixing = !fellBack
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
            Task { @MainActor in self?.wakeAudio(mixing: mixing) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                // Everything audio was torn down: build the silence again from scratch.
                self?.keepAlive.stop()
                self?.keepAlive = SuflorKeepAlive()
                self?.wakeAudio(mixing: mixing)
            }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.keepAlive.start() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wakeAudio(mixing: mixing) }
        })
    }

    private func wakeAudio(mixing: Bool) {
        Self.activateAudio(mixing: mixing)
        keepAlive.start()
    }

    private func possibleChanged(_ possible: Bool) {
        onPossibleChange?(possible)
        guard !possible, !fellBack else { return }
        // Sharing the sound with the other app is the polite way; if the system will not float a
        // window for a session that mixes, fall back to one that does not, after a moment.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !self.isPossible, !self.fellBack else { return }
            self.fellBack = true
            Self.activateAudio(mixing: false)
            self.keepAlive.start()
            self.controller?.invalidatePlaybackState()
        }
    }

    func start() {
        controller?.startPictureInPicture()
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

    func invalidate() {
        controller?.invalidatePlaybackState()
    }

    func detach() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        possibleObservation = nil
        controller?.stopPictureInPicture()
        controller = nil
        keepAlive.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func activateAudio(mixing: Bool) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: mixing ? [.mixWithOthers] : [])
        try? session.setActive(true)
    }
}

/// A second of silence on a loop, mixed under whatever the other app plays.
private nonisolated final class SuflorKeepAlive: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?

    func start() {
        if buffer == nil {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
                  let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100) else { return }
            silence.frameLength = silence.frameCapacity
            if let samples = silence.floatChannelData?[0] {
                samples.update(repeating: 0, count: Int(silence.frameLength))
            }
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            buffer = silence
        }
        guard let buffer else { return }
        if !engine.isRunning {
            engine.prepare()
            guard (try? engine.start()) != nil else { return }
        }
        if !player.isPlaying {
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
        }
    }

    func stop() {
        player.stop()
        engine.stop()
    }
}

/// Answers Picture in Picture's questions from the engine, on whatever thread it asks.
private nonisolated final class PlaybackDelegate: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate, @unchecked Sendable {
    let engine: SuflorEngine
    var onActiveChange: (@Sendable (Bool) -> Void)?

    init(engine: SuflorEngine) {
        self.engine = engine
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        engine.setPlaying(playing)
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        engine.timeRange()
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        !engine.isPlaying
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        engine.nudge(seconds: skipInterval.seconds)
        completionHandler()
    }

    /// The other app's sound keeps playing: the window is silent.
    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onActiveChange?(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onActiveChange?(false)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

/// Puts the engine's display layer on screen: the small live preview of the floating window on
/// the stage, which is also where the window grows from when it floats away.
struct SuflorWindowPreview: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    let onAttach: () -> Void

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.display = layer
        view.layer.addSublayer(layer)
        view.onWindow = onAttach
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {}

    final class LayerView: UIView {
        var display: AVSampleBufferDisplayLayer?
        var onWindow: (() -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            display?.frame = bounds
            CATransaction.commit()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onWindow?() }
        }
    }
}
