import CaptureEngine
import Domain
import Foundation
import Observation
import SpeechEngine
import SwiftUI
import Teleprompter

/// Drives the studio: which segment and word the speaker is on, and the elapsed time.
///
/// The place in the script comes from `PrompterDriver` — the speaker's own voice while it can be
/// heard, a real speaking pace when it cannot. It used to be a 135 ms timer, which ran through the
/// script at three times the speed of speech and then stopped the recording on its own.
@MainActor
@Observable
public final class StudioModel {
    public enum Phase: Sendable {
        case idle
        case preparing
        case recording
        /// Stop was pressed and the file is being closed. The take does not exist until this ends,
        /// and moving on before it did is how a recording used to go missing.
        case finishing
        case complete
    }

    public private(set) var phase: Phase = .idle
    public private(set) var segmentIndex = 0
    public private(set) var wordIndex = 0
    public var isLandscape = false
    /// Rule-of-thirds guides over the preview. Off by default; it is a framing aid, not decoration.
    public var showsGrid = false
    /// Seconds left before recording starts, or nil when no countdown is running.
    public private(set) var countdown: Int?
    /// Seconds since recording began.
    public private(set) var elapsed: Double = 0
    public var captureError: String?
    public private(set) var needsCapturePermissions = false

    public var hasScript: Bool {
        project.segments.contains { !$0.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public var hasFootage: Bool { project.segments.contains { $0.selectedTake != nil } }

    /// Reserve the shutter before any suspension, and settle permissions before the countdown.
    public func prepareCapture() async -> Bool {
        guard phase == .idle || phase == .complete else { return false }
        phase = .preparing
        captureError = nil
        needsCapturePermissions = false
        let status = await CameraSession.requestAuthorization(includingMicrophone: true)
        guard phase == .preparing else { return false }
        cameraAuthorization = status.camera
        guard status.camera == .authorized, status.microphone == .authorized else {
            needsCapturePermissions = true
            failCapture("studio.capture.permissions")
            return false
        }
        return true
    }

    public func failCapture(_ key: String.LocalizationValue) {
        captureError = String(localized: key, bundle: .module)
        phase = .idle
    }

    public let teleprompter = TeleprompterModel()
    public private(set) var project: Project

    public let camera = CameraSession()
    public private(set) var cameraAuthorization: CaptureAuthorization = .notDetermined
    public private(set) var cameraPosition: CameraPosition = .front
    /// Mirrors the lens so the UI can show it without reaching across threads for it.
    public private(set) var zoom: Double = 1

    /// Flipping mid-take would change the shot inside one file, so it is refused while rolling.
    public func flipCamera() {
        guard phase == .idle, countdown == nil else { return }
        cameraPosition = cameraPosition == .front ? .back : .front
        zoom = 1
        camera.setZoom(1)
        camera.switchTo(camera: cameraPosition)
    }

    public func setZoom(_ factor: Double) {
        let clamped = min(max(1, factor), camera.zoomRange.upperBound)
        zoom = clamped
        camera.setZoom(clamped)
    }

    public var zoomRange: ClosedRange<Double> { camera.zoomRange }

    /// Asks for the camera and starts the preview. The microphone is left alone until there is
    /// something to record with it — two prompts on first launch reads as an app taking more than
    /// it needs, and the studio is useful with a preview alone.
    public func startCamera(position: CameraPosition) async {
        let status = await CameraSession.requestAuthorization(includingMicrophone: false)
        cameraAuthorization = status.camera
        guard status.camera == .authorized else { return }
        cameraPosition = position
        camera.start(camera: position)
        // The project decides what gets shot. Recording 1080p30 into a 4K60 project and finding
        // out at export is the kind of mistake that costs a reshoot rather than a render.
        camera.apply(project.format)
    }

    public func stopCamera() {
        camera.stop()
    }

    /// Keeps the prompter's preset tables in step with the studio's orientation.
    ///
    /// The window's shape is the signal. Changing only the controls would leave the camera and
    /// the prompter using different orientations.
    public func setLandscape(_ landscape: Bool) {
        guard landscape != isLandscape else { return }
        isLandscape = landscape
        teleprompter.setLandscape(landscape)
    }

    private var task: Task<Void, Never>?
    private var clock: Task<Void, Never>?
    private let driver: PrompterDriver

    public init(project: Project, speech: any SpeechTranscribing = SystemSpeechTranscriber()) {
        self.project = project
        driver = PrompterDriver(
            scripts: project.segments.map(\.script),
            localeIdentifier: project.localeIdentifier,
            speech: speech
        )
        teleprompter.load(project.segments)
        driver.onMove = { [weak self] position in self?.move(to: position) }
        driver.isPaused = { [weak self] in self?.teleprompter.isPaused ?? false }
        // The prompter's speed control, 0–100, shown as 0.6×–1.6×, now means what it says.
        driver.speedMultiplier = { [weak self] in 0.6 + (self?.teleprompter.speed ?? 40) / 100 }
    }

    /// How the text is moving right now: following the voice, waiting for it, or by pace.
    public var prompterMode: PrompterMode {
        switch driver.mode {
        case .waiting: .listening
        case .following: .followingVoice
        case .pacing: .autoScroll
        }
    }

    /// The last word of the script has been reached. The take keeps rolling until stop.
    public var reachedEnd: Bool { driver.reachedEnd }

    public var currentSegment: Segment? {
        project.segments.indices.contains(segmentIndex) ? project.segments[segmentIndex] : project.segments.first
    }

    public var elapsedLabel: String {
        let whole = Int(elapsed)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// Per-segment progress for the recording pips: 0, partial, or 100 percent.
    public func progress(forSegmentAt index: Int) -> Double {
        guard project.segments.indices.contains(index) else { return 0 }
        if index < segmentIndex { return 1 }
        guard index == segmentIndex else { return 0 }
        let words = max(1, ScriptText.words(in: project.segments[index].script).count - 1)
        return min(1, Double(wordIndex) / Double(words))
    }

    /// Three seconds to put the phone on the tripod and find the lens.
    ///
    /// Every recording teleprompter ships this, and the reason is not politeness: without it the
    /// first seconds of every take are the reader reaching back from the shutter, which is exactly
    /// the footage they then have to trim.
    public func beginCountdown(from seconds: Int = 3, writingTo url: URL? = nil) {
        guard task == nil, phase == .preparing else { return }
        teleprompter.isSettingsOpen = false
        pendingRecordingURL = url
        countdown = seconds
        task = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, let value = countdown else { return }
                if value <= 1 {
                    countdown = nil
                    task = nil
                    startRecording(writingTo: pendingRecordingURL)
                    return
                }
                countdown = value - 1
            }
        }
    }

    public func cancelCountdown() {
        guard countdown != nil else { return }
        task?.cancel()
        task = nil
        countdown = nil
        pendingRecordingURL = nil
        phase = .idle
    }

    /// Where the file is being written, and when each segment began inside it.
    ///
    /// The boundaries are recorded as the voice moves from one segment to the next. They are a
    /// first answer: once the file is closed its transcript is matched against the script, and
    /// those times replace these wherever a segment could be found.
    private var pendingRecordingURL: URL?
    private var recordingURL: URL?
    private var recordingStart: Date?
    private var segmentStarts: [Double] = []

    /// The finished recording, for whoever owns the project to fold in.
    public private(set) var lastCapture: (url: URL, segmentStarts: [Double], duration: Double)?

    public func startRecording(writingTo url: URL? = nil) {
        guard phase == .preparing else { return }
        guard let url else {
            failCapture("studio.capture.storage")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let started = await camera.startRecording(to: url)
            guard phase == .preparing else {
                if started { _ = await camera.stopRecording() }
                return
            }
            guard started else {
                failCapture("studio.capture.failed")
                return
            }
            didStartRecording(to: url)
        }
    }

    private func didStartRecording(to url: URL) {
        phase = .recording
        segmentIndex = 0
        wordIndex = 0
        elapsed = 0
        lastCapture = nil
        teleprompter.isPaused = false
        teleprompter.isSettingsOpen = false
        publishPosition()

        recordingURL = url
        recordingStart = .now
        segmentStarts = [0]

        if hasScript { driver.start(camera: camera) }

        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, phase == .recording, let recordingStart else { return }
                elapsed = Date.now.timeIntervalSince(recordingStart)
            }
        }
    }

    public func stopRecording() {
        guard phase == .recording else { return }
        driver.stop(camera: camera)
        clock?.cancel()
        clock = nil

        let duration = recordingStart.map { Date.now.timeIntervalSince($0) } ?? elapsed
        let starts = segmentStarts
        let url = recordingURL
        recordingURL = nil
        recordingStart = nil

        guard url != nil else {
            phase = .complete
            return
        }
        phase = .finishing
        Task { [weak self] in
            let finished = await self?.camera.stopRecording()
            guard let self else { return }
            if let finished {
                lastCapture = (finished, starts, duration)
                phase = .complete
            } else {
                failCapture("studio.capture.saveFailed")
            }
        }
    }

    /// Moves the place on by one word, for a tap on the prompter when the voice is not being heard.
    public func nudgeForward() {
        guard phase == .recording else { return }
        driver.step()
    }

    /// Cancels anything ticking, the way the design clears its intervals on every navigation. A
    /// take still rolling is stopped properly rather than left writing behind a screen.
    public func stopTimers() {
        task?.cancel()
        task = nil
        countdown = nil
        if phase == .preparing { phase = .idle }
        if phase == .recording {
            stopRecording()
        }
    }

    public func reset() {
        task?.cancel()
        task = nil
        driver.stop(camera: camera)
        clock?.cancel()
        clock = nil
        phase = .idle
        segmentIndex = 0
        wordIndex = 0
        elapsed = 0
        countdown = nil
        lastCapture = nil
        recordingURL = nil
        recordingStart = nil
        segmentStarts = []
    }

    /// A place in the script from outside, by segment identifier.
    public func advance(to position: ScriptPosition) {
        guard let index = project.segments.firstIndex(where: { $0.id == position.segmentID }) else { return }
        move(to: .init(segment: index, word: position.wordIndex))
    }

    private func move(to position: ScriptFollower.Position) {
        guard phase == .recording, project.segments.indices.contains(position.segment),
              position.segment >= segmentIndex
        else { return }
        if position.segment > segmentIndex, let recordingStart {
            // A beat before the word was recognised: results arrive a few hundred milliseconds
            // after the sound, and a cut that lands on the word clips its first consonant.
            let at = max(0, Date.now.timeIntervalSince(recordingStart) - 0.45)
            for _ in segmentIndex..<position.segment {
                segmentStarts.append(at)
            }
        }
        segmentIndex = position.segment
        wordIndex = position.word
        publishPosition()
    }

    private func publishPosition() {
        guard let segment = currentSegment else { return }
        teleprompter.speakerDidReach(ScriptPosition(segmentID: segment.id, wordIndex: wordIndex))
    }
}

/// How the prompter is moving, for the recording badge.
public enum PrompterMode: Sendable {
    case listening
    case followingVoice
    case autoScroll
}
