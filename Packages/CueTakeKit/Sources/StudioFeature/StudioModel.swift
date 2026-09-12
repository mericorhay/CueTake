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

    public let teleprompter = TeleprompterModel()
    public private(set) var project: Project

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

    public func startRecording() {
        guard task == nil else { return }
        phase = .recording
        segmentIndex = 0
        wordIndex = 0
        teleprompter.isSettingsOpen = false
        publishPosition()

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
    }

    /// Cancels the running timer without touching what is already on screen, the way the design
    /// clears its intervals on every navigation.
    public func stopTimers() {
        task?.cancel()
        task = nil
    }

    public func reset()() {
        task?.cancel()
        task = nil
        phase = .idle
        segmentIndex = 0
        wordIndex = 0
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
