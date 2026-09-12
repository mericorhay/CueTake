import AVFoundation
import Domain
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
    private var audioInput: AVCaptureDeviceInput?
    private let movieOutput = AVCaptureMovieFileOutput()
    private let recordingDelegate = RecordingDelegate()
    private var isConfigured = false

    public init() {}

    public var isRecording: Bool { movieOutput.isRecording }

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
            } else {
                // Putting the old one back is better than leaving the session with no video at all.
                session.addInput(current)
            }
            session.commitConfiguration()
        }
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
        guard status.camera == .authorized else { return false }

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

                movieOutput.startRecording(to: url, recordingDelegate: recordingDelegate)
                continuation.resume(returning: true)
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
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        session.commitConfiguration()
    }

    private static func input(for camera: CameraPosition) -> AVCaptureDeviceInput? {
        let position: AVCaptureDevice.Position = camera == .front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return nil }
        return input
    }
}


/// Bridges the delegate callback back to the `async` call that started the recording.
private final class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    /// Set for the duration of one stop. Cleared as soon as it fires, so a later interruption
    /// cannot resume a continuation twice.
    var onFinish: ((URL?) -> Void)?

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        let handler = onFinish
        onFinish = nil
        handler?(error == nil ? outputFileURL : nil)
    }
}
