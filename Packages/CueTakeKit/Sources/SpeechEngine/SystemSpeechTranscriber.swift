import AVFoundation
import Domain
import Foundation
import Speech

/// Which of Apple's on-device recognisers is listening.
///
/// `SpeechTranscriber` is the newer, better model, but it covers a short list of languages —
/// Turkish is not on it. `DictationTranscriber` is the keyboard's dictation model and covers far
/// more. Asking only for the first is why "listen to the footage" heard nothing and the prompter
/// never followed anyone speaking Turkish: the locale was refused before a word was read.
enum Recognizer: Sendable {
    case speech(SpeechTranscriber)
    case dictation(DictationTranscriber)

    var module: any SpeechModule {
        switch self {
        case .speech(let transcriber): transcriber
        case .dictation(let transcriber): transcriber
        }
    }

    /// Results as text and finality, whichever recogniser produced them.
    func results() -> AsyncThrowingStream<(text: AttributedString, isFinal: Bool), any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch self {
                    case .speech(let transcriber):
                        for try await result in transcriber.results {
                            continuation.yield((result.text, result.isFinal))
                        }
                    case .dictation(let transcriber):
                        for try await result in transcriber.results {
                            continuation.yield((result.text, result.isFinal))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The best recogniser for a language, with its model downloaded.
    ///
    /// - Parameter live: volatile results for following a speaker; final results with word
    ///   timings for a file.
    static func make(localeIdentifier: String, live: Bool) async throws -> Recognizer {
        let requested = Locale(identifier: localeIdentifier)
        let recognizer: Recognizer
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            recognizer = .speech(
                SpeechTranscriber(
                    locale: locale,
                    transcriptionOptions: [],
                    reportingOptions: live ? [.volatileResults] : [],
                    attributeOptions: live ? [] : [.audioTimeRange]
                )
            )
        } else if let locale = await DictationTranscriber.supportedLocale(equivalentTo: requested) {
            recognizer = .dictation(
                DictationTranscriber(locale: locale, preset: live ? .progressiveLongDictation : .timeIndexedLongDictation)
            )
        } else {
            throw SpeechError.localeNotSupported(localeIdentifier)
        }

        // The model for a language arrives the first time it is needed. Without it the analyzer
        // hears nothing and the transcript comes back empty, which reads as "no one spoke".
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [recognizer.module]) {
            try await request.downloadAndInstall()
        }
        return recognizer
    }
}

/// Transcription on Apple's on-device `SpeechAnalyzer`: files for captions and editing by text,
/// the microphone for following the script. No upload, no quota, works on a plane.
public struct SystemSpeechTranscriber: SpeechTranscribing {
    public init() {}

    public func supportedLocaleIdentifiers() async -> [String] {
        let speech = await SpeechTranscriber.supportedLocales.map(\.identifier)
        let dictation = await DictationTranscriber.supportedLocales.map(\.identifier)
        return Array(Set(speech + dictation)).sorted()
    }

    /// Live transcription of the microphone while recording, for following the script.
    ///
    /// Volatile results on: they arrive within a fraction of a second and are replaced as the
    /// recogniser firms up, which is exactly what a prompter needs — an early guess at the word
    /// being said now beats a certain answer about the word said a second ago. Words carry no
    /// timings here; the file is transcribed properly once the take ends.
    public func transcribe(
        _ audio: AsyncStream<SpeechAudioFrame>,
        localeIdentifier: String
    ) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        AsyncThrowingStream { continuation in
            let work = Task {
                do {
                    let recognizer = try await Recognizer.make(localeIdentifier: localeIdentifier, live: true)
                    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [recognizer.module]) else {
                        throw SpeechError.localeNotSupported(localeIdentifier)
                    }

                    let analyzer = SpeechAnalyzer(modules: [recognizer.module])
                    let (inputs, feed) = AsyncStream<AnalyzerInput>.makeStream()
                    try await analyzer.start(inputSequence: inputs)

                    let reader = Task {
                        for try await result in recognizer.results() {
                            let words = ScriptText.words(in: String(result.text.characters)).map {
                                TimedWord(text: String($0), range: MediaTimeRange(start: .zero, duration: .zero))
                            }
                            continuation.yield(TranscriptUpdate(words: words, isFinal: result.isFinal))
                        }
                    }

                    let converter = PCMConverter(target: format)
                    for await frame in audio {
                        if Task.isCancelled { break }
                        if let converted = converter.convert(frame.buffer) {
                            feed.yield(AnalyzerInput(buffer: converted))
                        }
                    }
                    feed.finish()
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                    try await reader.value
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    public func transcribeFile(at url: URL, localeIdentifier: String) async throws -> Transcript {
        // A video is read through its sound. `AVAudioFile` opens audio files; handed a .mov it
        // can fail outright, which is the other half of why listening to footage heard nothing.
        let audioURL = try await Self.audioFile(for: url)
        let recognizer = try await Recognizer.make(localeIdentifier: localeIdentifier, live: false)

        let analyzer = SpeechAnalyzer(modules: [recognizer.module])
        let file = try AVAudioFile(forReading: audioURL)

        // Collect on a task of its own: results arrive while the analyzer is still reading, and
        // waiting for the read to finish before listening would miss them.
        let collector = Task {
            var text = ""
            var words: [TimedWord] = []
            for try await result in recognizer.results() where result.isFinal {
                text += String(result.text.characters) + " "
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

    /// The sound of a file as an audio file: itself when it already is one, otherwise its audio
    /// track copied out once to an m4a beside it.
    static func audioFile(for url: URL) async throws -> URL {
        let audioExtensions: Set<String> = ["m4a", "wav", "caf", "aif", "aiff", "mp3", "aac"]
        if audioExtensions.contains(url.pathExtension.lowercased()) { return url }

        let destination = url.deletingLastPathComponent().appending(
            path: url.deletingPathExtension().lastPathComponent + "-speech.m4a",
            directoryHint: .notDirectory
        )
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            return destination
        }

        let asset = AVURLAsset(url: url)
        guard (try? await asset.loadTracks(withMediaType: .audio).first) != nil,
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else { throw SpeechError.noAudio }
        do {
            try await session.export(to: destination, as: .m4a)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw SpeechError.noAudio
        }
        return destination
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

/// Converts microphone buffers to the format the analyzer wants.
///
/// The microphone speaks 48 kHz interleaved integers; the analyzer asks for something else, and a
/// buffer in the wrong format is not an error it reports but silence it hears.
final class PCMConverter {
    private let target: AVAudioFormat
    private var converter: AVAudioConverter?
    private var source: AVAudioFormat?

    init(target: AVAudioFormat) {
        self.target = target
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == target { return buffer }
        if converter == nil || source != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            // No priming: the analyzer lines results up against the audio it was given, and
            // priming frames shift everything by a few milliseconds each buffer.
            converter?.primeMethod = .none
            source = buffer.format
        }
        guard let converter else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        // Read and written only inside the synchronous convert call below.
        nonisolated(unsafe) var consumed = false
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, inputStatus in
            defer { consumed = true }
            inputStatus.pointee = consumed ? .noDataNow : .haveData
            return consumed ? nil : buffer
        }
        guard status != .error, failure == nil, output.frameLength > 0 else { return nil }
        return output
    }
}
