import CaptureEngine
import Domain
import Foundation
import Observation
import SpeechEngine

/// Moves the prompter while a take is rolling: by listening when it can, by pace when it cannot.
///
/// Both the studio and the retake screen used to step through the script on a 130 ms timer — about
/// 450 words a minute, three times faster than anyone speaks — and ended the recording when the
/// timer ran out of words, whether or not the speaker had. This replaces that with the thing the
/// app is named for: the text waits for you.
///
/// - While the voice is heard, the place comes from the words (`ScriptFollower`).
/// - Before any word has been heard for a few seconds — the language model still downloading, a
///   language the recogniser does not have, no microphone — it scrolls at a real speaking pace set
///   by the prompter's speed control, and hands back to the voice the moment one arrives.
/// - It never stops the recording. Reaching the last word is announced; stopping is the speaker's.
@MainActor
@Observable
final class PrompterDriver {
    enum Mode: Equatable {
        /// Rolling, nothing heard yet.
        case waiting
        /// Following the voice.
        case following
        /// Scrolling by pace.
        case pacing
    }

    private(set) var mode: Mode = .waiting
    private(set) var reachedEnd = false
    /// How fast the voice is reading, while it is being followed.
    private(set) var wordsPerMinute: Double?
    private var paceMeter = PaceMeter()

    /// Where the place moved to, whoever moved it.
    @ObservationIgnored var onMove: ((ScriptFollower.Position) -> Void)?
    /// The prompter's pause and speed, read live so changing them mid-take takes effect.
    @ObservationIgnored var isPaused: () -> Bool = { false }
    @ObservationIgnored var speedMultiplier: () -> Double = { 1 }
    /// Words to tell the recogniser about beyond the script's own: the brand's name and phrases.
    @ObservationIgnored var extraHints: [String] = []
    /// The last words heard, whatever the place: for an ad's checks while it is recorded.
    @ObservationIgnored var onHeard: (([String]) -> Void)?

    /// Where the voice was last found, and how many words the text has glided past it since.
    private var heardPosition: ScriptFollower.Position?
    private var heardAt: Date?
    private var lead = 0
    /// Words the text may run ahead of the voice on its own.
    static let maximumLead = 2

    private var follower: ScriptFollower
    private let scripts: [String]
    private let localeIdentifier: String
    private let speech: any SpeechTranscribing

    private var audio: AsyncStream<SpeechAudioFrame>.Continuation?
    private var listening: Task<Void, Never>?
    private var ticking: Task<Void, Never>?
    private var startedAt: Date?
    private var lastWordAt: Date?
    private var paceCarry = 0.0

    /// Seconds of hearing nothing, at the start, before the text starts moving on its own.
    static let patience = 6.0

    init(scripts: [String], localeIdentifier: String, speech: any SpeechTranscribing) {
        self.scripts = scripts
        self.localeIdentifier = localeIdentifier
        self.speech = speech
        follower = ScriptFollower(scripts: scripts, locale: Locale(identifier: localeIdentifier))
    }

    var position: ScriptFollower.Position {
        follower.position ?? .init(segment: 0, word: 0)
    }

    /// Starts listening to the camera's microphone and the pace clock.
    func start(camera: CameraSession?) {
        stop(camera: camera)
        follower = ScriptFollower(scripts: scripts, locale: Locale(identifier: localeIdentifier))
        mode = .waiting
        reachedEnd = false
        startedAt = .now
        lastWordAt = nil
        paceCarry = 0
        paceMeter.reset()
        wordsPerMinute = nil
        heardPosition = nil
        heardAt = nil
        lead = 0

        if let camera, CameraSession.tapsAudio {
            let (frames, continuation) = AsyncStream<SpeechAudioFrame>.makeStream(bufferingPolicy: .bufferingNewest(128))
            audio = continuation
            camera.setAudioHandler { @Sendable buffer in
                continuation.yield(SpeechAudioFrame(buffer: buffer))
            }
            listen(to: frames)
        } else {
            mode = .pacing
        }

        ticking = Task { [weak self] in
            var last = Date.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }
                let now = Date.now
                tick(seconds: now.timeIntervalSince(last), now: now)
                last = now
            }
        }
    }

    func stop(camera: CameraSession?) {
        camera?.setAudioHandler(nil)
        audio?.finish()
        audio = nil
        listening?.cancel()
        listening = nil
        ticking?.cancel()
        ticking = nil
    }

    private func listen(to frames: AsyncStream<SpeechAudioFrame>) {
        let hints = extraHints + SpeechHints.terms(scripts: scripts, localeIdentifier: localeIdentifier)
        let updates = speech.transcribe(frames, localeIdentifier: localeIdentifier, hints: hints)
        listening = Task { [weak self] in
            var settled: [String] = []
            var tail: [String] = []
            do {
                for try await update in updates {
                    guard let self else { return }
                    let words = update.words.map(\.text)
                    guard !words.isEmpty else { continue }
                    let recent = Array((settled + words).suffix(8))
                    if update.isFinal { settled = recent }
                    onHeard?(Array((tail + words).suffix(24)))
                    if update.isFinal { tail = Array((tail + words).suffix(24)) }
                    hear(recent)
                }
            } catch {
                // Could not listen: the pace takes over from wherever the text is.
            }
            self?.listeningEnded()
        }
    }

    private func hear(_ words: [String]) {
        lastWordAt = .now
        if mode != .following {
            // The text may have run ahead by itself before the voice arrived; let the voice find
            // its place a little behind.
            if mode == .pacing { follower.rewind(words: 12) }
            mode = .following
            paceMeter.reset()
        }
        if isPaused() {
            // Held while ad-libbing: the pause is not slow reading.
            paceMeter.reset()
            wordsPerMinute = nil
            return
        }
        guard let moved = follower.hear(words) else { return }
        reachedEnd = follower.isAtEnd
        if let startedAt {
            paceMeter.record(
                word: ScriptTiming.globalWord(scripts: scripts, segment: moved.segment, word: moved.word),
                at: Date.now.timeIntervalSince(startedAt)
            )
            wordsPerMinute = paceMeter.wordsPerMinute
        }
        // The text may already be showing this word, having glided ahead of the recogniser. Then
        // it stays where it is instead of stepping back.
        let shown = heardPosition.map { (segment: $0.segment, word: $0.word + lead) }
        heardPosition = moved
        heardAt = .now
        if let shown, shown.segment == moved.segment, moved.word < shown.word, moved.word >= shown.word - Self.maximumLead {
            lead = shown.word - moved.word
            return
        }
        lead = 0
        onMove?(moved)
    }

    private func listeningEnded() {
        guard ticking != nil else { return }
        mode = .pacing
        wordsPerMinute = nil
    }

    private func tick(seconds: Double, now: Date) {
        switch mode {
        case .following:
            glide(now: now)
            return
        case .waiting:
            guard let startedAt, now.timeIntervalSince(startedAt) >= Self.patience else { return }
            mode = .pacing
        case .pacing:
            break
        }
        guard !isPaused(), !reachedEnd else { return }

        let perMinute = SpeakingRate.wordsPerMinute(forLocaleIdentifier: localeIdentifier) * speedMultiplier()
        paceCarry += seconds * perMinute / 60
        guard paceCarry >= 1 else { return }
        paceCarry -= 1
        step()
    }

    /// Moves the text on between the recogniser's answers, at the pace the voice is reading.
    ///
    /// Results arrive a few hundred milliseconds after the sound, in bursts, so text that only
    /// follows them jumps. Between two answers it runs ahead by a word or two at the measured pace,
    /// never past the end of the segment, and the next answer settles it.
    private func glide(now: Date) {
        guard !isPaused(), let base = heardPosition, let heardAt,
              let pace = wordsPerMinute, pace > 40
        else { return }
        let due = Int(now.timeIntervalSince(heardAt) / (60 / pace))
        let wanted = min(Self.maximumLead, due)
        guard wanted > lead else { return }
        let count = scripts.indices.contains(base.segment) ? ScriptText.words(in: scripts[base.segment]).count : 0
        guard base.word + wanted < count else { return }
        lead = wanted
        onMove?(.init(segment: base.segment, word: base.word + wanted))
    }

    /// One word forward by pace, or by a tap on the prompter.
    func step() {
        let current = follower.position
        let next: ScriptFollower.Position
        if let current {
            let words = scripts.indices.contains(current.segment)
                ? ScriptText.words(in: scripts[current.segment]).count : 0
            if current.word + 1 < words {
                next = .init(segment: current.segment, word: current.word + 1)
            } else {
                var segment = current.segment + 1
                while segment < scripts.count, ScriptText.words(in: scripts[segment]).isEmpty { segment += 1 }
                guard segment < scripts.count else {
                    reachedEnd = true
                    return
                }
                next = .init(segment: segment, word: 0)
            }
        } else {
            guard let segment = scripts.firstIndex(where: { !ScriptText.words(in: $0).isEmpty }) else { return }
            next = .init(segment: segment, word: 0)
        }
        follower.place(at: next)
        reachedEnd = follower.isAtEnd
        onMove?(next)
    }
}
