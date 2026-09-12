import AVFAudio
import Domain
import Foundation

// Real-time capture only: session, devices, permissions, writing the file.
// Anything that happens after the file exists (composition, rendering, export) is MediaEngine.

public struct CaptureConfiguration: Hashable, Sendable {
    public var format: VideoFormat
    public var camera: CameraPosition
    public var isMicrophoneEnabled: Bool

    public init(format: VideoFormat, camera: CameraPosition = .front, isMicrophoneEnabled: Bool = true) {
        self.format = format
        self.camera = camera
        self.isMicrophoneEnabled = isMicrophoneEnabled
    }
}

public enum CaptureAuthorization: Hashable, Sendable {
    case notDetermined
    case authorized
    case denied
}

public struct CaptureAuthorizationStatus: Hashable, Sendable {
    public var camera: CaptureAuthorization
    public var microphone: CaptureAuthorization

    public init(camera: CaptureAuthorization, microphone: CaptureAuthorization) {
        self.camera = camera
        self.microphone = microphone
    }
}

/// The finished file. The caller turns it into a `Recording` + `Take`s, because only the caller
/// knows the project directory and which segment(s) were being recorded.
public struct CaptureResult: Hashable, Sendable {
    public var fileURL: URL
    public var duration: MediaTime
    public var configuration: CaptureConfiguration

    public init(fileURL: URL, duration: MediaTime, configuration: CaptureConfiguration) {
        self.fileURL = fileURL
        self.duration = duration
        self.configuration = configuration
    }
}

public enum CaptureEvent: Hashable, Sendable {
    case sessionRunning
    case sessionInterrupted
    case recordingStarted
    case recordingFinished(CaptureResult)
    case failed(CaptureError)
}

public enum CaptureError: Error, Hashable, Sendable {
    case notAuthorized
    case deviceUnavailable
    case notConfigured
    case notImplemented
}

/// Live microphone audio, teed to speech tracking while recording.
public struct CapturedAudioFrame: @unchecked Sendable {
    // AVAudioPCMBuffer is not Sendable. A frame is produced once and never mutated after hand-off.
    public let buffer: AVAudioPCMBuffer
    public let hostTime: UInt64

    public init(buffer: AVAudioPCMBuffer, hostTime: UInt64) {
        self.buffer = buffer
        self.hostTime = hostTime
    }
}

/// Implemented later by an actor over AVCaptureSession, writing with AVAssetWriter
/// (not AVCaptureMovieFileOutput) so audio buffers can be teed to speech tracking.
/// The preview surface is added together with that implementation.
public protocol CameraCapturing: Sendable {
    func authorizationStatus() async -> CaptureAuthorizationStatus
    func requestAuthorization() async -> CaptureAuthorizationStatus
    func configure(_ configuration: CaptureConfiguration) async throws
    func startRecording(to fileURL: URL) async throws
    func stopRecording() async throws -> CaptureResult
    func events() -> AsyncStream<CaptureEvent>
    func audioFrames() -> AsyncStream<CapturedAudioFrame>
}

public struct UnimplementedCameraCapture: CameraCapturing {
    public init() {}

    public func authorizationStatus() async -> CaptureAuthorizationStatus {
        CaptureAuthorizationStatus(camera: .notDetermined, microphone: .notDetermined)
    }

    public func requestAuthorization() async -> CaptureAuthorizationStatus {
        await authorizationStatus()
    }

    public func configure(_ configuration: CaptureConfiguration) async throws {
        throw CaptureError.notImplemented
    }

    public func startRecording(to fileURL: URL) async throws {
        throw CaptureError.notImplemented
    }

    public func stopRecording() async throws -> CaptureResult {
        throw CaptureError.notImplemented
    }

    public func events() -> AsyncStream<CaptureEvent> {
        AsyncStream { $0.finish() }
    }

    public func audioFrames() -> AsyncStream<CapturedAudioFrame> {
        AsyncStream { $0.finish() }
    }
}
