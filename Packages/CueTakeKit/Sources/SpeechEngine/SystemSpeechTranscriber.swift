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
            // The whole feature is in this line. With time ranges attached to each run, the
            // transcript stops being a paragraph about the take and becomes an index into it —
            // which is what makes editing by text possible at all.
            attributeOptions: [.audioTimeRange]
        )

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)

        // Collect on a task of its own: results arrive while the analyzer is still reading, and
        // waiting for the read to finish before listening would miss them.
        let collector = Task {
            var text = ""
            var words: [TimedWord] = []
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
                words += Self.words(in: result.text)
            }
            return (text, words)
        }

        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        }

        let (text, timed) = try await collector.value
        let duration = Double(file.length) / file.fileFormat.sampleRate

        return Transcript(
            localeIdentifier: localeIdentifier,
            // The proportional spread stays as the fallback, not as the answer. A locale whose
            // model does not report ranges still gets captions in roughly the right places, and
            // the code that consumes timings does not have to know which kind it got.
            words: timed.isEmpty ? Self.timedWords(in: text, over: duration) : timed
        )
    }

    /// Pulls the per-word timings out of a result.
    ///
    /// The analyzer attaches an audio time range to each *run*, and a run is usually a word but is
    /// sometimes a short phrase. Where it is a phrase the words inside it are spread across the
    /// run in proportion to their length — over a run of a few hundred milliseconds that error is
    /// smaller than the gap between two spoken words, which is the only precision anything here
    /// actually needs.
    static func words(in attributed: AttributedString) -> [TimedWord] {
        var result: [TimedWord] = []

        for run in attributed.runs {
            guard let range = run.audioTimeRange else { continue }
            let piece = String(attributed[run.range].characters)
            let words = ScriptText.words(in: piece).map(String.init)
            guard !words.isEmpty else { continue }

            let start = range.start.seconds
            let length = max(range.duration.seconds, 0.01)
            let total = Double(words.reduce(0) { $0 + max(1, $1.count) })
            var cursor = start

            for word in words {
                let share = Double(max(1, word.count)) / total * length
                result.append(
                    TimedWord(
                        text: word,
                        range: MediaTimeRange(
                            start: MediaTime(seconds: cursor),
                            duration: MediaTime(seconds: share)
                        )
                    )
                )
                cursor += share
            }
        }

        return result
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
