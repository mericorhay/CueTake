import AVFoundation
import AVKit
import CoreMedia
import SwiftUI
import UIKit

/// The floating window: Picture in Picture of the kind a video call uses, showing a view.
///
/// It used to be a video — frames fed to a sample buffer layer — and iOS darkened it the moment a
/// camera opened in the app in front, the same as it darkens YouTube's. A video call's window holds
/// a view instead, which is what FaceTime keeps showing while another app uses the camera. The
/// engine draws each frame as a picture and the view shows it. A call's window has no play or skip
/// buttons, so the words start by themselves when it floats and are steered from the stage.
@MainActor
final class SuflorPiP: NSObject {
    private(set) var controller: AVPictureInPictureController?
    private let engine: SuflorEngine
    private let delegate: WindowDelegate
    /// On the stage: the preview, and where the window grows from.
    let sourceView = SuflorFrameView()
    /// In the floating window.
    private let windowView = SuflorFrameView()
    private let content = AVPictureInPictureVideoCallViewController()
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
        delegate = WindowDelegate()
        super.init()
        content.preferredContentSize = CGSize(width: 360, height: 480)
        content.view.backgroundColor = .black
        windowView.frame = content.view.bounds
        windowView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.view.addSubview(windowView)
        engine.onFrame = { [weak self] frame in
            Task { @MainActor in self?.show(frame.image) }
        }
    }

    private func show(_ image: CGImage) {
        sourceView.show(image)
        windowView.show(image)
    }

    var isActive: Bool { controller?.isPictureInPictureActive ?? false }
    var isPossible: Bool { controller?.isPictureInPicturePossible ?? false }

    /// Makes the controller once the preview is on screen: before that it is never possible.
    func attach() {
        guard controller == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        Self.activateAudio(mixing: true)
        let source = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: sourceView, contentViewController: content)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = delegate
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
        }
    }

    func start() {
        controller?.startPictureInPicture()
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

    /// A call's window has no playback state to refresh.
    func invalidate() {}

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

/// Tells the stage when the window opens and closes.
private nonisolated final class WindowDelegate: NSObject, AVPictureInPictureControllerDelegate, @unchecked Sendable {
    var onActiveChange: (@Sendable (Bool) -> Void)?

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

/// Shows the engine's latest frame, fitted.
final class SuflorFrameView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.contentsGravity = .resizeAspect
        layer.contentsScale = 2
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        CATransaction.commit()
    }
}

/// Puts the stage's preview of the floating window on screen: the window as it is right now, and
/// where it grows from when it floats away.
struct SuflorWindowPreview: UIViewRepresentable {
    let view: SuflorFrameView
    let onAttach: () -> Void

    func makeUIView(context: Context) -> Holder {
        let holder = Holder()
        holder.onWindow = onAttach
        view.frame = holder.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        holder.addSubview(view)
        return holder
    }

    func updateUIView(_ holder: Holder, context: Context) {}

    final class Holder: UIView {
        var onWindow: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onWindow?() }
        }
    }
}
