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
    /// The audio clip being worked on. Separate from `inspectedSegment` because they are two
    /// different selections on two different lanes, and collapsing them into one is how an editor
    /// ends up showing music controls for a piece of footage.
    public var selectedAudio: AudioClip.ID?
    /// Drawn peaks, per clip. Computed once per file and kept, because reading a three minute song
    /// to draw it again on every layout pass is how a timeline starts to stutter.
    public private(set) var waveforms: [AudioClip.ID: [Float]] = [:]

    /// How wide one second is drawn. This is what makes the timeline an editing surface rather
    /// than a diagram: laid out proportionally, a 0.2s trim on a 30s video is two pixels wide and
    /// cannot be grabbed. Pinching changes this, and at 240pt a second there is room to work.
    public var pointsPerSecond: Double = TimelineScale.fit
    /// True while the playhead is being dragged, so playback does not fight the finger.
    public var isScrubbing = false

    /// The last tool that fired, so the timeline can play its answer. Carries a counter rather
    /// than only a kind, because using the same tool twice in a row has to read as two edits.
    public private(set) var lastTool: ToolPulse?
    private var pulseCount = 0

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
        guard let assembled = try? await VideoComposer().compose(
            project: project,
            mediaDirectory: mediaDirectory
        ) else {
            teardownPlayer()
            return
        }

        teardownPlayer()
        let item = AVPlayerItem(asset: assembled.composition)
        // Levels, fades and ducking in the preview too. An editor whose preview plays the music at
        // full volume and whose export ducks it is not previewing anything.
        item.audioMix = assembled.audioMix
        item.audioTimePitchAlgorithm = .spectral
        // Without this the preview plays raw source frames while the export applies the framing,
        // which is the worst kind of editor: one that shows you something it will not deliver.
        item.videoComposition = assembled.videoComposition
        let player = AVPlayer(playerItem: item)
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
        seek(to: 0)
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
        var clamped = max(0.4, seconds)

        // A segment cannot be longer than the footage behind it. Dragging past the end used to be
        // allowed, and the export found out the hard way.
        if let take = project.segments[index].selectedTake,
           let recording = project.recordings.first(where: { $0.id == take.recordingID }) {
            clamped = min(clamped, recording.duration.seconds - take.sourceRange.start.seconds)
            guard clamped > 0.1 else { return }
        }

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

    /// The segment under the playhead, and how far into it the playhead sits.
    public var segmentAtPlayhead: (index: Int, offset: Double)? {
        var running = 0.0
        for (index, segment) in project.segments.enumerated() {
            let end = running + segment.barWeight
            if playhead >= running && playhead < end {
                return (index, playhead - running)
            }
            running = end
        }
        return nil
    }

    /// Splits the segment under the playhead in two.
    ///
    /// The razor, and the tool our model was waiting for: both halves point at the same recording
    /// with adjacent source ranges, so nothing is copied, nothing is re-encoded, and the file on
    /// disk is untouched. A split is two numbers.
    ///
    /// The script goes with it, cut at the same proportion, so the prompter and the captions still
    /// describe the right half.
    public func splitAtPlayhead() {
        guard let (index, offset) = segmentAtPlayhead else { return }
        let segment = project.segments[index]
        // A split right on a boundary produces an empty clip, which is never what was meant.
        guard offset > 0.15, segment.barWeight - offset > 0.15 else { return }

        var left = segment
        var right = segment.copyWithNewIdentity()

        if let take = segment.selectedTake {
            var leftTake = take
            leftTake.sourceRange = MediaTimeRange(
                start: take.sourceRange.start,
                duration: MediaTime(seconds: offset)
            )
            var rightTake = Take(
                recordingID: take.recordingID,
                sourceRange: MediaTimeRange(
                    start: take.sourceRange.start + MediaTime(seconds: offset),
                    duration: take.sourceRange.duration - MediaTime(seconds: offset)
                ),
                status: take.status
            )
            rightTake.transcript = nil

            left.takes = [leftTake]
            left.selectedTakeID = leftTake.id
            right.takes = [rightTake]
            right.selectedTakeID = rightTake.id
        } else {
            left.estimatedDuration = MediaTime(seconds: offset)
            right.estimatedDuration = MediaTime(seconds: segment.barWeight - offset)
        }

        let words = ScriptText.words(in: segment.script).map(String.init)
        if !words.isEmpty {
            let cut = max(1, min(words.count - 1, Int((offset / segment.barWeight * Double(words.count)).rounded())))
            left.script = words[..<cut].joined(separator: " ")
            right.script = words[cut...].joined(separator: " ")
        }
        left.captions = []
        right.captions = []

        project.segments[index] = left
        project.segments.insert(right, at: index + 1)
        project.updatedAt = .now
        inspectedSegment = right.id
    }

    /// Removes a segment. Everything after it closes up on its own, because the timeline is
    /// derived — there is no ripple to perform, only one less thing to lay out.
    public func deleteSegment(at index: Int) {
        guard project.segments.indices.contains(index), project.segments.count > 1 else { return }
        let removed = project.segments.remove(at: index)
        if inspectedSegment == removed.id { inspectedSegment = nil }
        project.updatedAt = .now
        playhead = min(playhead, duration)
    }

    public func duplicateSegment(at index: Int) {
        guard project.segments.indices.contains(index) else { return }
        var copy = project.segments[index].copyWithNewIdentity()
        // Takes keep pointing at the same recording: a duplicate is another window onto the same
        // footage, not another copy of it.
        copy.captions = []
        project.segments.insert(copy, at: index + 1)
        project.updatedAt = .now
        inspectedSegment = copy.id
    }

    /// Joins a segment with the one after it, when they are two halves of the same shot.
    ///
    /// Refused across different recordings: there is one range per take, so a join would have to
    /// invent a clip that spans two files, and that is a different feature wearing this one's name.
    public func canMerge(at index: Int) -> Bool {
        guard project.segments.indices.contains(index + 1),
              let left = project.segments[index].selectedTake,
              let right = project.segments[index + 1].selectedTake,
              left.recordingID == right.recordingID
        else { return false }
        return abs(left.sourceRange.end.seconds - right.sourceRange.start.seconds) < 0.05
    }

    public func mergeWithNext(at index: Int) {
        guard canMerge(at: index),
              let left = project.segments[index].selectedTake,
              let right = project.segments[index + 1].selectedTake
        else { return }

        var merged = project.segments[index]
        var take = left
        take.sourceRange = MediaTimeRange(
            start: left.sourceRange.start,
            duration: left.sourceRange.duration + right.sourceRange.duration
        )
        take.transcript = nil
        merged.takes = [take]
        merged.selectedTakeID = take.id
        merged.script = [project.segments[index].script, project.segments[index + 1].script]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        merged.captions = []

        project.segments[index] = merged
        project.segments.remove(at: index + 1)
        project.updatedAt = .now
        inspectedSegment = merged.id
    }

    /// Announces an edit at the playhead. Called by the tools, watched by the timeline.
    public func pulse(_ kind: ToolKind) {
        pulseCount += 1
        lastTool = ToolPulse(
            id: pulseCount,
            kind: kind,
            position: timelineDuration > 0 ? playhead / timelineDuration : 0
        )
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


// MARK: - Audio

extension EditorModel {
    /// Clips in the order they start, which is the order the lane draws them.
    public var audioClips: [AudioClip] {
        project.audio.sorted { $0.start.seconds < $1.start.seconds }
    }

    public var selectedAudioClip: AudioClip? {
        selectedAudio.flatMap { id in project.audio.first { $0.id == id } }
    }

    public func addAudio(_ clip: AudioClip) {
        project.audio.append(clip)
        project.updatedAt = .now
        selectedAudio = clip.id
        inspectedSegment = nil
    }

    /// Every audio edit goes through here so there is exactly one place that stamps `updatedAt`
    /// and one place that decides what a legal value is.
    public func updateAudio(_ id: AudioClip.ID, _ change: (inout AudioClip) -> Void) {
        guard let index = project.audio.firstIndex(where: { $0.id == id }) else { return }
        change(&project.audio[index])
        // Clamped here rather than trusted from the interface: a slider is one caller, and the
        // next one will be a keyboard, a gesture, or an AI asked to make the music quieter.
        project.audio[index].gain = min(max(project.audio[index].gain, 0), 2)
        project.audio[index].speed = min(max(project.audio[index].speed, 0.5), 2)
        if project.audio[index].start.seconds < 0 {
            project.audio[index].start = .zero
        }
        project.updatedAt = .now
    }

    public func removeAudio(_ id: AudioClip.ID) {
        project.audio.removeAll { $0.id == id }
        waveforms[id] = nil
        if selectedAudio == id { selectedAudio = nil }
        project.updatedAt = .now
    }

    public func duplicateAudio(_ id: AudioClip.ID) {
        guard let clip = project.audio.first(where: { $0.id == id }) else { return }
        var copy = clip.copyWithNewIdentity()
        copy.start = MediaTime(seconds: clip.timelineRange.end.seconds)
        project.audio.append(copy)
        project.updatedAt = .now
        selectedAudio = copy.id
    }

    /// Splits an audio clip under the playhead, the same way footage splits: two ranges into one
    /// file, nothing copied.
    public func splitAudioAtPlayhead(_ id: AudioClip.ID) {
        guard let clip = project.audio.first(where: { $0.id == id }) else { return }
        let offset = playhead - clip.start.seconds
        guard offset > 0.15, clip.timelineDuration.seconds - offset > 0.15 else { return }

        let sourceOffset = offset * clip.speed

        var left = clip
        left.sourceRange = MediaTimeRange(
            start: clip.sourceRange.start,
            duration: MediaTime(seconds: sourceOffset)
        )
        left.fadeOut = MediaTime(seconds: 0)

        var right = clip.copyWithNewIdentity()
        right.start = MediaTime(seconds: playhead)
        right.sourceRange = MediaTimeRange(
            start: clip.sourceRange.start + MediaTime(seconds: sourceOffset),
            duration: clip.sourceRange.duration - MediaTime(seconds: sourceOffset)
        )
        right.fadeIn = MediaTime(seconds: 0)

        if let index = project.audio.firstIndex(where: { $0.id == id }) {
            project.audio[index] = left
        }
        project.audio.append(right)
        project.updatedAt = .now
        selectedAudio = right.id
    }

    /// The clip under the playhead, if any. What the split tool acts on when the audio lane has
    /// the selection.
    public var audioAtPlayhead: AudioClip? {
        project.audio.first { $0.timelineRange.contains(MediaTime(seconds: playhead)) }
    }

    /// Reads the peaks for anything that does not have them yet.
    ///
    /// Incremental on purpose: importing a second song should not re-read the first.
    public func loadWaveforms(mediaDirectory: URL) async {
        let sampler = WaveformSampler()
        for clip in project.audio where waveforms[clip.id] == nil {
            let url = mediaDirectory.appending(
                path: (clip.relativePath as NSString).lastPathComponent,
                directoryHint: .notDirectory
            )
            let peaks = await sampler.peaks(of: url)
            guard !peaks.isEmpty else { continue }
            waveforms[clip.id] = peaks
        }
    }

    /// How many rows the audio lane needs.
    ///
    /// Lives here rather than in the view because two views need the same answer — the lane draws
    /// the rows and the playhead has to be tall enough to cross them — and two independent
    /// calculations of the same number always drift apart eventually.
    public var audioRowCount: Int {
        guard !project.audio.isEmpty else { return 0 }
        var ends: [Double] = []
        for clip in audioClips {
            let start = clip.start.seconds
            if let row = ends.firstIndex(where: { $0 <= start + 0.01 }) {
                ends[row] = clip.timelineRange.end.seconds
            } else {
                ends.append(clip.timelineRange.end.seconds)
            }
        }
        return ends.count
    }

    /// How long the timeline is once the audio is taken into account.
    ///
    /// Music that runs past the last clip is a real thing people do — an outro over black — and a
    /// timeline that refuses to draw it makes the tail impossible to trim.
    public var timelineDuration: Double {
        max(duration, project.audio.map { $0.timelineRange.end.seconds }.max() ?? 0)
    }
}
