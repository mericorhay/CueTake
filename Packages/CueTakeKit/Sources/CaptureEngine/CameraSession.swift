import AVFoundation
import Domain
import Observation

/// Owns the `AVCaptureSession` and nothing else.
///
/// Recording is not here yet. This is the half that makes the studio real — a live preview instead
/// of a dark rectangle — and it is worth having on its own: the permission prompt, the device
/// choice and the session lifecycle are the parts that go wrong, and they are easier to get right
/// before an asset writer is also in the picture.
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
    private var isConfigured = false

    public init() {}

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

    private func configure(camera: CameraPosition) {
        session.beginConfiguration()
        // High rather than a preset resolution: the capture format is chosen at record time, and a
        // preview that matches the screen costs less than one that matches the sensor.
        session.sessionPreset = .high

        if let input = Self.input(for: camera), session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
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
