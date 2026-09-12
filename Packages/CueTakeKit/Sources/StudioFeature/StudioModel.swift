import CaptureEngine
import Domain
import Observation
import SwiftUI
import Teleprompter

/// Drives the studio: which segment and word the speaker is on, and the elapsed time.
///
/// Until CaptureEngine and SpeechEngine are implemented, `startRecording` advances through the
/// script on a timer at the design's 135ms per word. Swapping that stand-in for real speech
/// tracking means feeding `ScriptPosition` values into `advance(to:)` instead — the screens,
/// the teleprompter and the progress pips already read from here.
@MainActor
@Observable
public final class StudioModel {
    public enum Phase: Sendable {
        case idle
        case recording
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

    public let teleprompter = TeleprompterModel()
    public private(set) var project: Project

    public let camera = CameraSession()
    public private(set) var cameraAuthorization: CaptureAuthorization = .notDetermined

    /// Asks for the camera and starts the preview. The microphone is left alone until there is
    /// something to record with it — two prompts on first launch reads as an app taking more than
    /// it needs, and the studio is useful with a preview alone.
    public func startCamera(position: CameraPosition) async {
        let status = await CameraSession.requestAuthorization(includingMicrophone: false)
        cameraAuthorization = status.camera
        guard status.camera == .authorized else { return }
        camera.start(camera: position)
    }

    public func stopCamera() {
        camera.stop()
    }

    /// Keeps the prompter's preset tables in step with the studio's orientation.
    ///
    /// The design file has a rotate button because a browser cannot be turned on its side. A phone
    /// can, so the real signal is the window's shape — the button stays, but rotating the device
    /// is what normally drives this.
    public func setLandscape(_ landscape: Bool) {
        guard landscape != isLandscape else { return }
        isLandscape = landscape
        teleprompter.setLandscape(landscape)
    }

    private var task: Task<Void, Never>?

    public init(project: Project) {
        self.project = project
        teleprompter.load(project.segments)
    }

    public var currentSegment: Segment? {
        project.segments.indices.contains(segmentIndex) ? project.segments[segmentIndex] : project.segments.first
    }

    /// Elapsed time, accumulated per finished segment plus progress through the current one.
    public var elapsedLabel: String {
        var elapsed = 0.0
        for (index, segment) in project.segments.enumerated() {
            let words = max(1, ScriptText.words(in: segment.script).count)
            if index < segmentIndex {
                elapsed += segment.barWeight
            } else if index == segmentIndex {
                elapsed += segment.barWeight * (Double(wordIndex) / Double(words))
            }
        }
        return "0:" + String(format: "%02d", Int(elapsed))
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
        guard task == nil, phase == .idle else { return }
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
    }

    /// Where the file is being written, and when each segment began inside it.
    ///
    /// The boundaries are what turn one continuous file into per-segment takes: the prompter
    /// already knows when the speaker moved on, so the split is recorded as it happens rather than
    /// guessed afterwards. This is the same shape a real speech tracker will produce — it will just
    /// be right about the timings instead of assuming a steady pace.
    private var pendingRecordingURL: URL?
    private var recordingURL: URL?
    private var recordingStart: Date?
    private var segmentStarts: [Double] = []

    /// The finished recording, for whoever owns the project to fold in.
    public private(set) var lastCapture: (url: URL, segmentStarts: [Double], duration: Double)?

    public func startRecording(writingTo url: URL? = nil) {
        guard task == nil else { return }
        phase = .recording
        segmentIndex = 0
        wordIndex = 0
        teleprompter.isSettingsOpen = false
        publishPosition()

        recordingURL = url
        recordingStart = .now
        segmentStarts = [0]

        if let url {
            Task { [camera] in _ = await camera.startRecording(to: url) }
        }

        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(135))
                guard let self, phase == .recording else { return }
                step()
                if phase == .complete { return }
            }
        }
    }

    public func stopRecording() {
        task?.cancel()
        task = nil
        phase = .complete

        let elapsed = recordingStart.map { Date.now.timeIntervalSince($0) } ?? 0
        let starts = segmentStarts
        let url = recordingURL
        recordingURL = nil
        recordingStart = nil

        guard url != nil else { return }
        Task { [weak self] in
            guard let finished = await self?.camera.stopRecording() else { return }
            self?.lastCapture = (finished, starts, elapsed)
        }
    }

    /// Cancels the running timer without touching what is already on screen, the way the design
    /// clears its intervals on every navigation.
    public func stopTimers() {
        task?.cancel()
        task = nil
        countdown = nil
    }

    public func reset() {
        task?.cancel()
        task = nil
        phase = .idle
        segmentIndex = 0
        wordIndex = 0
        countdown = nil
        lastCapture = nil
        recordingURL = nil
        recordingStart = nil
        segmentStarts = []
    }

    /// Real speech tracking calls this instead of the timer.
    public func advance(to position: ScriptPosition) {
        guard let index = project.segments.firstIndex(where: { $0.id == position.segmentID }) else { return }
        segmentIndex = index
        wordIndex = position.wordIndex
        teleprompter.speakerDidReach(position)
    }

    private func step() {
        guard let segment = currentSegment else { return }
        let words = ScriptText.words(in: segment.script).count
        if wordIndex + 1 >= words {
            if segmentIndex + 1 >= project.segments.count {
                stopRecording()
                return
            }
            segmentIndex += 1
            wordIndex = 0
            if let recordingStart {
                segmentStarts.append(Date.now.timeIntervalSince(recordingStart))
            }
        } else {
            wordIndex += 1
        }
        publishPosition()
    }

    private func publishPosition() {
        guard let segment = currentSegment else { return }
        teleprompter.speakerDidReach(ScriptPosition(segmentID: segment.id, wordIndex: wordIndex))
    }
}
