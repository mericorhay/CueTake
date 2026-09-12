import AVFoundation
import Domain
import Foundation
import Speech

/// File transcription on Apple's on-device `SpeechAnalyzer`.
///
/// This is the one place where the app's promise about speed is actually kept: no upload, no
/// queue, no per-minute quota, and it works on a plane. It is also the input everything else has
/// been waiting for — captions, script alignment and silence trimming are all the same transcript
/// read three different ways.
///
/// Live microphone tracking is the other half and is not here yet. Transcribing a finished file is
/// the half that can be verified: a wrong word in a caption is visible, whereas a prompter that
/// drifts is hard to tell from a reader who paused.
public struct SystemSpeechTranscriber: SpeechTranscribing {
    public init() {}

    public func supportedLocaleIdentifiers() async -> [String] {
        await SpeechTranscriber.supportedLocales.map(\.identifier)
    }

    public func transcribe(
        _ audio: AsyncStream<SpeechAudioFrame>,
        localeIdentifier: String
    ) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        AsyncThrowingStream { $0.finish(throwing: SpeechError.notImplemented) }
    }

    public func transcribeFile(at url: URL, localeIdentifier: String) async throws -> Transcript {
        let locale = Locale(identifier: localeIdentifier)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            // Final results only: a file is not being read as it arrives, and volatile guesses
            // would just be thrown away.
            reportingOptions: [],
            attributeOptions: []
        )

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)

        // Collect on a task of its own: results arrive while the analyzer is still reading, and
        // waiting for the read to finish before listening would miss them.
        let collector = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }

        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        }

        let text = try await collector.value
        let duration = Double(file.length) / file.fileFormat.sampleRate

        return Transcript(
            localeIdentifier: localeIdentifier,
            words: Self.timedWords(in: text, over: duration)
        )
    }

    /// Spreads the words across the clip in proportion to their length.
    ///
    /// A placeholder for real per-word timings, and marked as one rather than hidden: the analyzer
    /// can attach an audio time range to each run of the result, and swapping this for that changes
    /// only this function. Proportional timings are already enough for captions to be cut at the
    /// right words and for a segment to be aligned; they are not enough for karaoke highlighting,
    /// which is the thing to judge the replacement by.
    static func timedWords(in text: String, over duration: Double) -> [TimedWord] {
        let words = ScriptText.words(in: text).map(String.init)
        guard !words.isEmpty, duration > 0 else { return [] }

        let total = Double(words.reduce(0) { $0 + max(1, $1.count) })
        var cursor = 0.0

        return words.map { word in
            let share = Double(max(1, word.count)) / total * duration
            let range = MediaTimeRange(
                start: MediaTime(seconds: cursor),
                duration: MediaTime(seconds: share)
            )
            cursor += share
            return TimedWord(text: word, range: range)
        }
    }
}
