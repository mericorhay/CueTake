import Domain
import Observation
import SwiftUI

/// Editor state: the playhead and which segment is being inspected.
///
/// The timeline itself is never stored — it is derived from the project by `TimelineBuilder`,
/// so a retake that changes one segment's length moves everything after it automatically.
@MainActor
@Observable
public final class EditorModel {
    public enum InspectorTab: String, CaseIterable, Sendable {
        case script = "Script"
        case caption = "Caption"
        case timing = "Timing"
        case take = "Take"
        case style = "Style"
    }

    public var project: Project
    public private(set) var playhead: Double = 0
    public private(set) var isPlaying = false
    public var inspectedSegment: Segment.ID?
    public var inspectorTab: InspectorTab = .script

    /// How wide one second is drawn. This is what makes the timeline an editing surface rather
    /// than a diagram: laid out proportionally, a 0.2s trim on a 30s video is two pixels wide and
    /// cannot be grabbed. Pinching changes this, and at 240pt a second there is room to work.
    public var pointsPerSecond: Double = TimelineScale.fit
    /// True while the playhead is being dragged, so playback does not fight the finger.
    public var isScrubbing = false

    private var task: Task<Void, Never>?

    public init(project: Project) {
        self.project = project
    }

    /// Total running time from the segments' durations.
    public var duration: Double {
        max(1, project.segments.reduce(0) { $0 + $1.barWeight })
    }

    public var playheadFraction: Double { playhead / duration }

    public var playheadLabel: String {
        MediaTime(seconds: playhead).timecode
    }

    public var durationLabel: String {
        MediaTime(seconds: duration).timecode
    }

    public func start(at index: Int) -> Double {
        project.segments.prefix(index).reduce(0) { $0 + $1.barWeight }
    }

    public func isActive(at index: Int) -> Bool {
        let start = start(at: index)
        return playhead >= start && playhead < start + project.segments[index].barWeight
    }

    public func rangeLabel(at index: Int) -> String {
        let start = start(at: index)
        let end = start + project.segments[index].barWeight
        return "\(MediaTime(seconds: start).timecode) – \(MediaTime(seconds: end).timecode)"
    }

    // MARK: - Transport

    /// Advances the playhead in real time. AVPlayer takes this over once MediaEngine is implemented.
    public func togglePlayback() {
        if isPlaying {
            pause()
            return
        }
        isPlaying = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                guard let self, isPlaying else { return }
                let next = playhead + 0.06
                if next >= duration {
                    playhead = 0
                    pause()
                    return
                }
                playhead = next
            }
        }
    }

    public func pause() {
        isPlaying = false
        task?.cancel()
        task = nil
    }

    public func skipToStart() {
        playhead = 0
    }

    public func seek(to seconds: Double) {
        playhead = min(max(0, seconds), duration)
    }

    public func beginScrub() {
        pause()
        isScrubbing = true
    }

    public func endScrub() {
        isScrubbing = false
    }

    // MARK: - Editing

    /// Segment boundaries, plus zero and the end: the points a scrub should snap to.
    public var snapPoints: [Double] {
        var points = [0.0]
        var running = 0.0
        for segment in project.segments {
            running += segment.barWeight
            points.append(running)
        }
        return points
    }

    /// The nearest boundary within `tolerance` seconds, or nil when the finger is between them.
    public func snapTarget(for seconds: Double, tolerance: Double) -> Double? {
        snapPoints
            .min { abs($0 - seconds) < abs($1 - seconds) }
            .flatMap { abs($0 - seconds) <= tolerance ? $0 : nil }
    }

    /// Sets a segment's length.
    ///
    /// With a take, this trims the range into the recording and never touches the file. Without
    /// one — a project that has been planned but not shot — it sets the estimate the whole app
    /// lays out against. Same gesture, and the caller does not have to know which case it is in.
    public func setDuration(_ seconds: Double, forSegmentAt index: Int) {
        guard project.segments.indices.contains(index) else { return }
        let clamped = max(0.4, seconds)

        if let takeID = project.segments[index].selectedTakeID,
           let takeIndex = project.segments[index].takes.firstIndex(where: { $0.id == takeID }) {
            let take = project.segments[index].takes[takeIndex]
            project.segments[index].takes[takeIndex].sourceRange = MediaTimeRange(
                start: take.sourceRange.start,
                duration: MediaTime(seconds: clamped)
            )
        } else {
            project.segments[index].estimatedDuration = MediaTime(seconds: clamped)
        }
        project.updatedAt = .now
    }

    public func move(segmentAt index: Int, to destination: Int) {
        guard project.segments.indices.contains(index),
              destination >= 0, destination < project.segments.count,
              index != destination
        else { return }
        let segment = project.segments.remove(at: index)
        project.segments.insert(segment, at: destination)
        project.updatedAt = .now
    }
}
