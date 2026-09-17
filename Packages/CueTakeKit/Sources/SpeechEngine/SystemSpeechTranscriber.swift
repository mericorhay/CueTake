import AVFoundation
import Domain
import Foundation
import Speech

/// Which of Apple's on-device recognisers is listening, newest first.
///
/// 1. `SpeechTranscriber` — Apple's newest model, the best results, a short list of languages.
/// 2. `DictationTranscriber` — the same new analyzer with the dictation model, for the languages
///    the first does not cover (Turkish among them).
/// 3. `LegacySpeech` (`SFSpeechRecognizer`) — the older API, kept beside them as the safety net:
///    used whenever the new ones refuse a language, fail, or hear nothing.
enum Recognizer: Sendable {
    case speech(SpeechTranscriber)
    case dictation(DictationTranscriber)

    var module: any SpeechModule {
        switch self {
        case .speech(let transcriber): transcriber
        case .dictation(let transcriber): transcriber
        }
    }

    var isDictation: Bool {
        if case .dictation = self { return true }
        return false
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

    /// The newest recogniser that has this language, with its model downloaded.
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

/// Transcription on Apple's on-device recognisers: files for captions and editing by text, the
/// microphone for following the script. No upload, no quota, works on a plane.
public struct SystemSpeechTranscriber: SpeechTranscribing {
    public init() {}

    public func supportedLocaleIdentifiers() async -> [String] {
        let speech = await SpeechTranscriber.supportedLocales.map(\.identifier)
        let dictation = await DictationTranscriber.supportedLocales.map(\.identifier)
        let legacy = SFSpeechRecognizer.supportedLocales().map(\.identifier)
        return Array(Set(speech + dictation + legacy)).sorted()
    }

    /// Live transcription of the microphone while recording, for following the script.
    ///
    /// Volatile results on: an early guess at the word being said now beats a certain answer
    /// about the word said a second ago. If the new analyzer cannot start, or has heard nothing
    /// after several seconds of sound, the same microphone is handed to the older recogniser
    /// without the take noticing.
    public func transcribe(
        _ audio: AsyncStream<SpeechAudioFrame>,
        localeIdentifier: String
    ) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        transcribe(audio, localeIdentifier: localeIdentifier, hints: [])
    }

    /// The names, brands and numbers of the script, given to the recogniser before it listens, so
    /// it spells them the way the script does.
    public func transcribe(
        _ audio: AsyncStream<SpeechAudioFrame>,
        localeIdentifier: String,
        hints: [String]
    ) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        let hints = Array(hints.prefix(SpeechHints.limit))
        return AsyncThrowingStream { continuation in
            let work = Task {
                let recognizer: Recognizer
                let format: AVAudioFormat
                do {
                    recognizer = try await Recognizer.make(localeIdentifier: localeIdentifier, live: true)
                    guard let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [recognizer.module]) else {
                        throw SpeechError.localeNotSupported(localeIdentifier)
                    }
                    format = best
                } catch {
                    do {
                        try await LegacySpeech.follow(audio, localeIdentifier: localeIdentifier, hints: hints, into: continuation)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                    return
                }

                do {
                    let analyzer = SpeechAnalyzer(modules: [recognizer.module])
                    await Self.give(hints, to: analyzer)
                    let (inputs, feed) = AsyncStream<AnalyzerInput>.makeStream()
                    try await analyzer.start(inputSequence: inputs)

                    let heardSomething = Flag()
                    let reader = Task {
                        for try await result in recognizer.results() {
                            let words = ScriptText.words(in: String(result.text.characters)).map {
                                TimedWord(text: String($0), range: MediaTimeRange(start: .zero, duration: .zero))
                            }
                            if !words.isEmpty { heardSomething.set() }
                            continuation.yield(TranscriptUpdate(words: words, isFinal: result.isFinal))
                        }
                    }

                    let converter = PCMConverter(target: format)
                    let started = Date.now
                    var fallback: LegacySpeech.LiveSession?

                    for await frame in audio {
                        if Task.isCancelled { break }
                        if let fallback {
                            fallback.append(frame.buffer)
                            continue
                        }
                        if let converted = converter.convert(frame.buffer) {
                            feed.yield(AnalyzerInput(buffer: converted))
                        }
                        // Eight seconds of sound and not one word: hand over to the older
                        // recogniser for the rest of the take.
                        if !heardSomething.isSet, Date.now.timeIntervalSince(started) > 8 {
                            fallback = try? await LegacySpeech.LiveSession(localeIdentifier: localeIdentifier, hints: hints, into: continuation)
                            if fallback != nil {
                                feed.finish()
                                reader.cancel()
                            }
                        }
                    }

                    if let fallback {
                        fallback.finish()
                    } else {
                        feed.finish()
                        try await analyzer.finalizeAndFinishThroughEndOfInput()
                        try await reader.value
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    /// Every word of a file, newest recogniser first, the older one if the new ones refuse the
    /// language, fail, or come back with nothing.
    public func transcribeFile(at url: URL, localeIdentifier: String) async throws -> Transcript {
        try await transcribeFile(at: url, localeIdentifier: localeIdentifier, hints: [])
    }

    public func transcribeFile(at url: URL, localeIdentifier: String, hints: [String]) async throws -> Transcript {
        let hints = Array(hints.prefix(SpeechHints.limit))
        // A video is read through its sound. `AVAudioFile` opens audio files; handed a .mov it
        // can fail outright, which is half of why listening to footage used to hear nothing.
        let audioURL = try await Self.audioFile(for: url)

        var modernError: (any Error)?
        do {
            let transcript = try await Self.analyzerTranscript(of: audioURL, localeIdentifier: localeIdentifier, hints: hints)
            if !transcript.words.isEmpty { return transcript }
        } catch {
            modernError = error
        }

        do {
            return try await LegacySpeech.transcribeFile(at: audioURL, localeIdentifier: localeIdentifier, hints: hints)
        } catch {
            // The more useful of the two failures: a language the new model does not have is
            // explained better by the older recogniser's answer.
            throw modernError is SpeechError ? error : (modernError ?? error)
        }
    }

    /// Tells the analyzer which words to expect. Best effort: a context it refuses is a context
    /// it listens without.
    static func give(_ hints: [String], to analyzer: SpeechAnalyzer) async {
        guard !hints.isEmpty else { return }
        let context = AnalysisContext()
        context.contextualStrings[.general] = hints
        try? await analyzer.setContext(context)
    }

    private static func analyzerTranscript(of audioURL: URL, localeIdentifier: String, hints: [String]) async throws -> Transcript {
        let recognizer = try await Recognizer.make(localeIdentifier: localeIdentifier, live: false)
        let analyzer = SpeechAnalyzer(modules: [recognizer.module])
        await give(hints, to: analyzer)
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return Transcript(
            localeIdentifier: localeIdentifier,
            // The proportional spread stays as the fallback for a model that reports no ranges.
            words: timed.isEmpty ? Self.timedWords(in: trimmed, over: duration) : timed
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

/// Speech recognition on `SFSpeechRecognizer`, for the languages the new analyzer does not have.
///
/// Older API, and the one with the long language list: Turkish included, on device on current
/// phones. The new `SpeechTranscriber` refuses those languages outright, and the dictation module
/// meant to cover them came back empty in testing — so for any language the new model does not
/// support, this is the path, and it is a path that is known to work.
enum LegacySpeech {
    static func authorize() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }

    static func recognizer(for localeIdentifier: String) async throws -> SFSpeechRecognizer {
        guard await authorize() else { throw SpeechError.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable
        else { throw SpeechError.localeNotSupported(localeIdentifier) }
        return recognizer
    }

    /// Every word of an audio file, with when it was said.
    ///
    /// Listens to the whole file. The recogniser hands a long recording back one utterance at a
    /// time — each pause ends a "final" result holding only the words since the last one — and this
    /// used to stop at the first of them: a talking video came back as its first sentence, or as
    /// nothing at all when the file opened on a moment of silence ("no speech detected" for that
    /// first stretch). Every final result is kept now, and the answer is given when the task says
    /// it has finished.
    static func transcribeFile(at url: URL, localeIdentifier: String, hints: [String] = []) async throws -> Transcript {
        let recognizer = try await recognizer(for: localeIdentifier)
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.contextualStrings = hints
        // On device where the phone can: no length limit, no network, nothing leaves the phone.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let collector = FileRecognition()
        let words: [TimedWord] = try await withCheckedThrowingContinuation { continuation in
            collector.continuation = continuation
            collector.task = recognizer.recognitionTask(with: request, delegate: collector)
        }
        // The recogniser and its delegate have to live until the last word is in.
        withExtendedLifetime((recognizer, collector)) {}
        return Transcript(localeIdentifier: localeIdentifier, words: words)
    }

    /// Collects every final result of one file, in order, and answers once.
    final class FileRecognition: NSObject, SFSpeechRecognitionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var words: [TimedWord] = []
        private var answered = false
        var continuation: CheckedContinuation<[TimedWord], any Error>?
        var task: SFSpeechRecognitionTask?

        func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition result: SFSpeechRecognitionResult) {
            let segments = result.bestTranscription.segments
                .map { (text: $0.substring.trimmingCharacters(in: .whitespacesAndNewlines), start: $0.timestamp, length: $0.duration, confidence: $0.confidence) }
                .filter { !$0.text.isEmpty }
            guard !segments.isEmpty else { return }
            lock.withLock {
                let lastEnd = words.last.map { $0.range.end.seconds } ?? 0
                var fresh = segments[...]
                var shift = 0.0
                if segments.count >= words.count, !words.isEmpty,
                   zip(words, segments).allSatisfy({ $0.text == $1.text }) {
                    // The whole transcript so far, sent again with more on the end.
                    fresh = segments.dropFirst(words.count)
                } else if let first = segments.first, !words.isEmpty, first.start < lastEnd - 0.3 {
                    // A result timed from its own beginning rather than the file's.
                    shift = lastEnd + 0.3 - first.start
                }
                for segment in fresh {
                    words.append(
                        TimedWord(
                            text: segment.text,
                            range: MediaTimeRange(
                                start: MediaTime(seconds: segment.start + shift),
                                duration: MediaTime(seconds: max(0.05, segment.length))
                            ),
                            confidence: Double(segment.confidence)
                        )
                    )
                }
            }
        }

        func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
            let (heard, first) = lock.withLock { () -> ([TimedWord], Bool) in
                defer { answered = true }
                return (words, !answered)
            }
            guard first else { return }
            if successfully || !heard.isEmpty {
                continuation?.resume(returning: heard)
                return
            }
            // "No speech detected" is an answer, not a failure.
            if let error = task.error as NSError?, error.code != 1110, error.code != 203 {
                continuation?.resume(throwing: error)
            } else {
                continuation?.resume(returning: [])
            }
        }
    }

    /// The microphone, live, for following the script.
    static func follow(
        _ audio: AsyncStream<SpeechAudioFrame>,
        localeIdentifier: String,
        hints: [String] = [],
        into continuation: AsyncThrowingStream<TranscriptUpdate, any Error>.Continuation
    ) async throws {
        let session = try await LiveSession(localeIdentifier: localeIdentifier, hints: hints, into: continuation)
        for await frame in audio {
            if Task.isCancelled { break }
            session.append(frame.buffer)
        }
        session.finish()
    }

    /// One live recognition, fed buffer by buffer.
    final class LiveSession: @unchecked Sendable {
        private let request = SFSpeechAudioBufferRecognitionRequest()
        private var task: SFSpeechRecognitionTask?

        init(
            localeIdentifier: String,
            hints: [String] = [],
            into continuation: AsyncThrowingStream<TranscriptUpdate, any Error>.Continuation
        ) async throws {
            let recognizer = try await LegacySpeech.recognizer(for: localeIdentifier)
            request.shouldReportPartialResults = true
            request.contextualStrings = hints
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            task = recognizer.recognitionTask(with: request) { result, _ in
                guard let result else { return }
                // Partial results are the whole utterance so far; the follower only needs the end.
                let words = ScriptText.words(in: result.bestTranscription.formattedString)
                    .suffix(12)
                    .map { TimedWord(text: String($0), range: MediaTimeRange(start: .zero, duration: .zero)) }
                continuation.yield(TranscriptUpdate(words: Array(words), isFinal: result.isFinal))
            }
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            request.append(buffer)
        }

        func finish() {
            request.endAudio()
            task?.finish()
        }
    }
}

/// Set once, read from anywhere.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
