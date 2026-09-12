import AVFoundation
import Domain
import MediaEngine
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

    /// The real playback. Nil until the project's media has been composed — a project that has
    /// been planned but not shot has nothing to play, and the transport still has to work.
    public private(set) var player: AVPlayer?
    private var timeObserver: Any?

    public init(project: Project) {
        self.project = project
    }


    /// Builds the composition and hands it to a player.
    ///
    /// Called whenever the edit changes shape. Rebuilding is cheap — the composition references
    /// the source files rather than copying them — which is what lets a trim or a reorder be
    /// reflected in playback immediately instead of after a render.
    public func loadPlayback(mediaDirectory: URL) async {
        guard project.segments.contains(where: { $0.selectedTake != nil }) else {
            teardownPlayer()
            return
        }
        guard let composition = try? await VideoComposer().compose(
            project: project,
            mediaDirectory: mediaDirectory
        ) else {
            teardownPlayer()
            return
        }

        teardownPlayer()
        let player = AVPlayer(playerItem: AVPlayerItem(asset: composition))
        // Often enough to look continuous, rarely enough not to fight the scrub.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.03, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing, self.isPlaying else { return }
                self.playhead = min(time.seconds, self.duration)
            }
        }
        self.player = player
    }

    private func teardownPlayer() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause()
        player = nil
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

        if let player {
            player.seek(to: CMTime(seconds: playhead, preferredTimescale: 600))
            player.play()
            return
        }

        // No media yet: the playhead still has to move, or the editor cannot be understood before
        // anything has been shot.
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
        player?.pause()
        task?.cancel()
        task = nil
    }

    public func skipToStart() {
        playhead = 0
    }

    public func seek(to seconds: Double) {
        playhead = min(max(0, seconds), duration)
        // Tolerance zero: scrubbing to a boundary and landing near it is how a cut ends up one
        // frame out, which is the one thing the timeline exists to prevent.
        player?.seek(
            to: CMTime(seconds: playhead, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
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
