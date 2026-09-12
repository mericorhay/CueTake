import AVFAudio
import Domain
import Foundation

// On-device transcription and live script tracking.
// Implemented later with SpeechAnalyzer + SpeechTranscriber (iOS 26), falling back to
// SFSpeechRecognizer for locales SpeechTranscriber does not support.

public struct SpeechAudioFrame: @unchecked Sendable {
    // AVAudioPCMBuffer is not Sendable. A frame is produced once and never mutated after hand-off.
    public let buffer: AVAudioPCMBuffer

    public init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

public struct TranscriptUpdate: Hashable, Sendable {
    public var words: [TimedWord]
    /// False for volatile (fast, may still change) results, true once finalized.
    public var isFinal: Bool

    public init(words: [TimedWord], isFinal: Bool) {
        self.words = words
        self.isFinal = isFinal
    }
}

public enum SpeechError: Error, Hashable, Sendable {
    case notAuthorized
    case localeNotSupported(String)
    case notImplemented
}

public protocol SpeechTranscribing: Sendable {
    func supportedLocaleIdentifiers() async -> [String]
    /// Live transcription while recording.
    func transcribe(_ audio: AsyncStream<SpeechAudioFrame>, localeIdentifier: String) -> AsyncThrowingStream<TranscriptUpdate, any Error>
    /// Final, accurate pass over a finished recording.
    func transcribeFile(at url: URL, localeIdentifier: String) async throws -> Transcript
}

/// Follows the speaker through the script in real time and drives the teleprompter.
///
/// Deterministic and on-device, low latency. The AI `SpeechAligning` capability is the separate,
/// post-recording pass (ad-libs, paraphrases, splitting a continuous take into segments).
public protocol ScriptTracking: Sendable {
    func track(
        _ updates: AsyncThrowingStream<TranscriptUpdate, any Error>,
        segments: [Segment],
        localeIdentifier: String
    ) -> AsyncStream<ScriptPosition>
}

public struct UnimplementedSpeechTranscriber: SpeechTranscribing {
    public init() {}

    public func supportedLocaleIdentifiers() async -> [String] { [] }

    public func transcribe(_ audio: AsyncStream<SpeechAudioFrame>, localeIdentifier: String) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        AsyncThrowingStream { $0.finish(throwing: SpeechError.notImplemented) }
    }

    public func transcribeFile(at url: URL, localeIdentifier: String) async throws -> Transcript {
        throw SpeechError.notImplemented
    }
}

public struct UnimplementedScriptTracker: ScriptTracking {
    public init() {}

    public func track(
        _ updates: AsyncThrowingStream<TranscriptUpdate, any Error>,
        segments: [Segment],
        localeIdentifier: String
    ) -> AsyncStream<ScriptPosition> {
        AsyncStream { $0.finish() }
    }
}
