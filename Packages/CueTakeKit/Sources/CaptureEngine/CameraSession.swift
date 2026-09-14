import AVFoundation
import Domain
import Foundation
import Observation

/// Owns the `AVCaptureSession`: preview, device choice, permissions, and writing the file.
///
/// `@unchecked Sendable` with a serial queue is the shape Apple's own samples use, and it is the
/// only one that works: `AVCaptureSession` is not `Sendable`, `startRunning()` blocks for long
/// enough that it must not run on the main thread, and the preview layer has to read the session
/// from the main thread. Every mutation below happens on `queue`; `session` is handed to the
/// preview layer, which is what Apple intends it to be handed to.
public final class CameraSession: @unchecked Sendable {
    /// Given straight to `AVCaptureVideoPreviewLayer`.
    public let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "com.orhay.cuetake.camera")
    private var videoInput: AVCaptureDeviceInput?
    /// The lens currently feeding the session, for zoom and for reporting what it can do.
    private var videoDevice: AVCaptureDevice?
    private var audioInput: AVCaptureDeviceInput?
    private let movieOutput = AVCaptureMovieFileOutput()
    private let recordingDelegate = RecordingDelegate()
    /// A copy of the microphone for following the script. The movie file gets its own; this one
    /// only listens.
    private let audioOutput = AVCaptureAudioDataOutput()
    private let audioTap = AudioTap()
    private let audioQueue = DispatchQueue(label: "com.orhay.cuetake.camera.audio")
    private var isConfigured = false

    public init() {}

    public var isRecording: Bool { movieOutput.isRecording }

    /// What this lens can actually do. A telephoto starts at 1x of its own field of view, so the
    /// numbers are relative to the current lens rather than to the phone.
    public var zoomRange: ClosedRange<Double> {
        guard let device = videoDevice else { return 1...1 }
        // Capped well below the hardware maximum: past a few times optical, the picture is a
        // digital crop and offering 100x is a promise of mush.
        return 1...min(Double(device.activeFormat.videoMaxZoomFactor), 8)
    }

    public var zoom: Double {
        Double(videoDevice?.videoZoomFactor ?? 1)
    }

    /// Sets the zoom, clamped to what the lens allows.
    ///
    /// Locked for configuration rather than set directly: another part of the system can be holding
    /// the device, and writing to it unlocked throws — which on a pinch means a crash mid-gesture.
    public func setZoom(_ factor: Double) {
        queue.async { [self] in
            guard let device = videoDevice else { return }
            let clamped = min(max(1, factor), min(Double(device.activeFormat.videoMaxZoomFactor), 8))
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.videoZoomFactor = CGFloat(clamped)
            device.unlockForConfiguration()
        }
    }

    // MARK: - Authorization

    public static func authorization(for media: AVMediaType) -> CaptureAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Asks for the camera, and for the microphone only if it will be used. Asking for both at once
    /// stacks two system prompts on first launch, which reads as an app taking more than it needs.
    public static func requestAuthorization(includingMicrophone: Bool) async -> CaptureAuthorizationStatus {
        var camera = authorization(for: .video)
        if camera == .notDetermined {
            camera = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        }

        guard includingMicrophone else {
            return CaptureAuthorizationStatus(camera: camera, microphone: authorization(for: .audio))
        }

        var microphone = authorization(for: .audio)
        if microphone == .notDetermined {
            microphone = await AVCaptureDevice.requestAccess(for: .audio) ? .authorized : .denied
        }
        return CaptureAuthorizationStatus(camera: camera, microphone: microphone)
    }

    // MARK: - Lifecycle

    /// Configures on first call and starts running. Safe to call again — rotating the phone or
    /// coming back from the background should not rebuild the session.
    public func start(camera: CameraPosition) {
        queue.async { [self] in
            if !isConfigured {
                configure(camera: camera)
                isConfigured = true
            }
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    public func stop() {
        queue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    /// Swaps the video input in place, leaving the session running so the preview does not blink.
    public func switchTo(camera: CameraPosition) {
        queue.async { [self] in
            guard isConfigured, let current = videoInput else { return }
            session.beginConfiguration()
            session.removeInput(current)
            if let input = Self.input(for: camera), session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
                videoDevice = input.device
            } else {
                // Putting the old one back is better than leaving the session with no video at all.
                session.addInput(current)
            }
            session.commitConfiguration()
        }
    }

    // MARK: - Listening

    private static let tapDisabledKey = "CueTake.audioTapDisabled"

    /// Whether recordings also feed the microphone to speech tracking. On unless a recording ever
    /// came back without sound while the tap was attached — then off for good on this device,
    /// because a prompter that follows you is worth less than a take that has its audio.
    public static var tapsAudio: Bool {
        !UserDefaults.standard.bool(forKey: tapDisabledKey)
    }

    public static func disableAudioTap() {
        UserDefaults.standard.set(true, forKey: tapDisabledKey)
    }

    /// Receives microphone audio while recording, on a background queue. Nil stops it.
    public func setAudioHandler(_ handler: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        audioTap.setHandler(handler)
    }

    // MARK: - Recording
    //
    // `AVCaptureMovieFileOutput` rather than an asset writer. The protocol's note asks for a
    // writer so audio buffers can be teed to speech tracking — and that is still the right end
    // state — but speech tracking does not exist yet, and a writer brings its own pixel buffer
    // pipeline, rotation handling and interruption edge cases. Recording that works today beats
    // a writer that half works, and the seam is one file either way.

    /// Adds the microphone and starts writing. The mic is only asked for here, which is why the
    /// preview alone never triggers a second permission prompt.
    public func startRecording(to url: URL) async -> Bool {
        let status = await Self.requestAuthorization(includingMicrophone: true)
        guard status.camera == .authorized, status.microphone == .authorized else { return false }

        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard isConfigured, !movieOutput.isRecording else {
                    continuation.resume(returning: false)
                    return
                }

                if audioInput == nil, status.microphone == .authorized {
                    session.beginConfiguration()
                    if let device = AVCaptureDevice.default(for: .audio),
                       let input = try? AVCaptureDeviceInput(device: device),
                       session.canAddInput(input) {
                        session.addInput(input)
                        audioInput = input
                    }
                    session.commitConfiguration()
                }

                // Apps built for iOS 16 and later may run a data output beside the movie output;
                // before that only one of them received anything.
                if audioInput != nil, Self.tapsAudio, !session.outputs.contains(audioOutput) {
                    session.beginConfiguration()
                    if session.canAddOutput(audioOutput) {
                        session.addOutput(audioOutput)
                        audioOutput.setSampleBufferDelegate(audioTap, queue: audioQueue)
                    }
                    session.commitConfiguration()
                }

                guard audioInput != nil else {
                    continuation.resume(returning: false)
                    return
                }
                recordingDelegate.onStart = { started in continuation.resume(returning: started) }
                movieOutput.startRecording(to: url, recordingDelegate: recordingDelegate)
            }
        }
    }

    /// Stops and waits for the file to be closed. Reading a movie before the writer has finished
    /// is how a recording comes back with a zero duration.
    public func stopRecording() async -> URL? {
        guard movieOutput.isRecording else { return nil }
        return await withCheckedContinuation { continuation in
            recordingDelegate.onFinish = { url in continuation.resume(returning: url) }
            queue.async { [self] in movieOutput.stopRecording() }
        }
    }

    private func configure(camera: CameraPosition) {
        session.beginConfiguration()
        // High rather than a preset resolution: the capture format is chosen at record time, and a
        // preview that matches the screen costs less than one that matches the sensor.
        session.sessionPreset = .high

        if let input = Self.input(for: camera), session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
            videoDevice = input.device
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        session.commitConfiguration()
    }

    // MARK: - Capture format

    /// Asks the sensor for a specific resolution and frame rate.
    ///
    /// `sessionPreset` cannot express this. A preset is a rough size and nothing at all about
    /// frames per second, so anything above 30 — and 4K or 8K at any rate — has to be chosen from
    /// the device's own format list. This is the difference between an app that records what the
    /// project asked for and one that records whatever the preset felt like.
    ///
    /// Silent when the format does not exist rather than failing: a phone that cannot shoot 8K
    /// should still record, at the best thing it has.
    public func apply(_ format: VideoFormat) {
        queue.async { [self] in
            guard let device = videoDevice,
                  let best = Self.bestFormat(on: device, for: format)
            else { return }

            do {
                try device.lockForConfiguration()
                device.activeFormat = best
                // Both ends pinned. Leaving the maximum open lets the camera drop frames in low
                // light, which is sensible for a photo app and ruinous for footage that has to
                // line up with a timeline.
                let duration = CMTime(value: 1, timescale: CMTimeScale(format.frameRate))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                device.unlockForConfiguration()
            } catch {
                // The camera is in use by something else. The session keeps whatever it had.
            }
        }
    }

    /// Which resolutions and frame rates this device can actually deliver.
    ///
    /// Used to build the format control, so it offers 120fps only on hardware that has it instead
    /// of offering it everywhere and failing quietly on the phones that do not.
    public func availableFormats(for camera: CameraPosition) -> [(resolution: VideoFormat.Resolution, frameRates: [Int])] {
        let position: AVCaptureDevice.Position = camera == .front ? .front : .back
        guard let device = videoDevice ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        else { return [] }

        return VideoFormat.Resolution.allCases.compactMap { resolution in
            let rates = VideoFormat.frameRateChoices.filter { rate in
                Self.bestFormat(
                    on: device,
                    for: VideoFormat(aspectRatio: .portrait9x16, resolution: resolution, frameRate: rate)
                ) != nil
            }
            return rates.isEmpty ? nil : (resolution, rates)
        }
    }

    /// The narrowest format that satisfies the request.
    ///
    /// Narrowest rather than largest: a format bigger than what was asked for costs battery, heat
    /// and a thermal throttle three minutes into a take, and none of it reaches the export, which
    /// scales to the project's render size anyway.
    static func bestFormat(on device: AVCaptureDevice, for wanted: VideoFormat) -> AVCaptureDevice.Format? {
        let targetShortEdge = wanted.resolution.shortEdge
        let fps = Double(wanted.frameRate)

        return device.formats
            .filter { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let shortEdge = Int(min(dimensions.width, dimensions.height))
                guard shortEdge >= targetShortEdge else { return false }
                return format.videoSupportedFrameRateRanges.contains {
                    $0.maxFrameRate + 0.01 >= fps && $0.minFrameRate - 0.01 <= fps
                }
            }
            .min { left, right in
                let a = CMVideoFormatDescriptionGetDimensions(left.formatDescription)
                let b = CMVideoFormatDescriptionGetDimensions(right.formatDescription)
                return Int(a.width) * Int(a.height) < Int(b.width) * Int(b.height)
            }
    }

    private static func input(for camera: CameraPosition) -> AVCaptureDeviceInput? {
        let position: AVCaptureDevice.Position = camera == .front ? .front : .back
        // The virtual multi-camera device where there is one: it switches between the ultra-wide,
        // wide and telephoto lenses by itself as the zoom changes, which is what makes zooming on
        // the back camera stay sharp instead of turning into a digital crop at 2x.
        let preferred: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]

        for type in preferred {
            if let device = AVCaptureDevice.default(type, for: .video, position: position),
               let input = try? AVCaptureDeviceInput(device: device) {
                return input
            }
        }
        return nil
    }
}


/// Turns the microphone's sample buffers into PCM buffers for whoever is listening.
private final class AudioTap: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func setHandler(_ handler: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        lock.withLock { self.handler = handler }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let handler = lock.withLock({ handler }), let buffer = Self.pcm(from: sampleBuffer) else { return }
        handler(buffer)
    }

    static func pcm(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)
        else { return nil }
        var stream = basic.pointee
        guard let format = AVAudioFormat(streamDescription: &stream) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }
}

/// Bridges the delegate callback back to the `async` call that started the recording.
private final class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var startHandler: (@Sendable (Bool) -> Void)?
    private var finishHandler: (@Sendable (URL?) -> Void)?

    var onStart: (@Sendable (Bool) -> Void)? {
        get { lock.withLock { startHandler } }
        set { lock.withLock { startHandler = newValue } }
    }
    /// Set for the duration of one stop. Cleared as soon as it fires, so a later interruption
    /// cannot resume a continuation twice.
    var onFinish: (@Sendable (URL?) -> Void)? {
        get { lock.withLock { finishHandler } }
        set { lock.withLock { finishHandler = newValue } }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        let handler = lock.withLock {
            let handler = startHandler
            startHandler = nil
            return handler
        }
        handler?(true)
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        let handlers = lock.withLock {
            let handlers = (startHandler, finishHandler)
            startHandler = nil
            finishHandler = nil
            return handlers
        }
        // A failed start can finish without a didStart callback. Release the waiting shutter.
        handlers.0?(false)
        let saved = error == nil || (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        handlers.1?(saved ? outputFileURL : nil)
    }
}
