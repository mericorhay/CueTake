import AVFoundation
import CoreGraphics
import Domain
import MediaEngine
import Observation
import SwiftUI
import UIKit

public enum SubjectTrackingState: Hashable, Sendable {
    case idle
    case analyzing(Double)
    case applied(Int)
    case noFace
    case failed
}

public struct SubjectTrackReviewPoint: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var timelineTime: Double
    public var confidence: Double
    public var progress: Double

    public init(id: UUID, timelineTime: Double, confidence: Double, progress: Double) {
        self.id = id
        self.timelineTime = timelineTime
        self.confidence = confidence
        self.progress = progress
    }
}

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
    /// The picture or text being edited over the preview.
    public var selectedOverlay: Overlay.ID?
    /// The effect laid over a stretch of the video being edited. See `EditorEffects`.
    public var selectedEffect: TimelineEffect.ID?
    /// The additional movie being positioned above the main cut.
    public var selectedVideoLayer: VideoLayer.ID?
    /// Progress and result of smart reframe for the selected added video.
    public internal(set) var subjectTracking: SubjectTrackingState = .idle
    /// Progress for reframing the primary cut across all recorded segments.
    public internal(set) var mainSubjectTracking: SubjectTrackingState = .idle
    /// Decoded overlay pictures, by overlay. Filled when playback is prepared and when one is added.
    public internal(set) var overlayImages: [Overlay.ID: UIImage] = [:]
    /// Where this project's files live, once playback has been prepared.
    public internal(set) var mediaDirectory: URL?
    /// Drawn peaks, per clip. Computed once per file and kept, because reading a three minute song
    /// to draw it again on every layout pass is how a timeline starts to stutter.
    public private(set) var waveforms: [AudioClip.ID: [Float]] = [:]
    /// Frames for the timeline, per take. Keyed by take rather than segment: a split makes new
    /// segments over the same take range, and a take is what the frames were read from.
    public private(set) var thumbnails: [Take.ID: [CGImage]] = [:]
    /// Frames across the whole of an added video's file, for its trim strip. By recording.
    public internal(set) var recordingFrames: [Recording.ID: [CGImage]] = [:]

    /// How wide one second is drawn. This is what makes the timeline an editing surface rather
    /// than a diagram: laid out proportionally, a 0.2s trim on a 30s video is two pixels wide and
    /// cannot be grabbed. Pinching changes this, and at 240pt a second there is room to work.
    public var pointsPerSecond: Double = TimelineScale.fit
    /// True while the playhead is being dragged, so playback does not fight the finger.
    public var isScrubbing = false
    /// True while an edge or a bar is being dragged on the timeline. The picture follows the edge,
    /// but the timeline must not scroll to the playhead under the finger.
    public var isAdjustingTimeline = false

    /// The last tool that fired, so the timeline can play its answer. Carries a counter rather
    /// than only a kind, because using the same tool twice in a row has to read as two edits.
    public private(set) var lastTool: ToolPulse?
    private var pulseCount = 0

    /// Undo, as snapshots. See `EditorHistory`.
    var past: [EditSnapshot] = []
    var future: [EditSnapshot] = []
    var editCount = 0
    /// True while an AI plan is being carried out, so its many tool calls make one undo step.
    @ObservationIgnored var isApplyingPlan = false
    /// Batches begun inside another batch, so ending the inner one does not end the outer.
    @ObservationIgnored var batchDepth = 0

    /// The AI at work: reading, then changing things one at a time. Nil when it is not. See `AIDirector`.
    public internal(set) var aiSession: AISession?
    /// Everything the AI has changed in this editing session, newest first, each part reversible.
    public internal(set) var aiChanges: [AIChangeSet] = []
    /// Bumped per target each time the AI touches it; views light up when their number moves.
    public internal(set) var aiGlow: [AITarget: Int] = [:]
    /// Bumped on every AI step, for the picture's own flash.
    public internal(set) var aiBeat = 0
    /// The stretch of the timeline the current AI step is working on.
    public internal(set) var aiScan: AIScanMark?
    @ObservationIgnored var aiTask: Task<Void, Never>?
    @ObservationIgnored var aiRequester: AIRequester?

    private var task: Task<Void, Never>?

    /// The real playback. Nil until the project's media has been composed — a project that has
    /// been planned but not shot has nothing to play, and the transport still has to work.
    public private(set) var player: AVPlayer?
    /// Why the preview could not be built, when it could not. Shown instead of a black frame.
    public private(set) var playbackProblem: String?
    /// Counts builds, so a slow one that finishes after a newer one never replaces its player.
    @ObservationIgnored private var playbackGeneration = 0
    /// What the current player was built from. A request to build the same thing again is ignored:
    /// replacing a working player with an identical one only blinks the picture.
    @ObservationIgnored private var builtSignature: [String]?
    /// 0…1 while clips' backgrounds are being replaced, nil otherwise.
    public internal(set) var backgroundProgress: Double?
    /// Background replacements that have been written, by file name.
    public internal(set) var readyBackgrounds: Set<String> = []
    @ObservationIgnored var backgroundJob: Task<Void, Never>?
    @ObservationIgnored var backgroundJobKey = ""
    /// The filters the preview's compositor reads on every frame, kept in step with the project.
    @ObservationIgnored let liveFilters = LiveFilters()
    /// Background replacements that could not be made this session, so they are not retried on
    /// every rebuild. Choosing the background again clears them.
    @ObservationIgnored var failedBackgrounds: Set<String> = []
    /// Set briefly when a background could not be replaced, to say so on the picture.
    public internal(set) var backgroundFailed = false
    /// The player's item failed while a background render was running; rebuild when it ends.
    @ObservationIgnored var recoverAfterBackgrounds = false
    @ObservationIgnored private var itemStatus: NSKeyValueObservation?
    @ObservationIgnored private var playbackRetries = 0
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
        self.mediaDirectory = mediaDirectory
        loadOverlayImages()
        prepareBackgrounds()
        guard project.segments.contains(where: { $0.selectedTake != nil }) else {
            teardownPlayer()
            return
        }
        let signature = compositionSignature
        if player != nil, builtSignature == signature { return }
        playbackGeneration += 1
        let generation = playbackGeneration
        let assembled: VideoComposer.Assembled
        do {
            liveFilters.update(project.effects)
            assembled = try await VideoComposer().compose(
                project: project,
                mediaDirectory: mediaDirectory,
                renderBackgrounds: false,
                liveFilters: liveFilters
            )
        } catch {
            // A build that was superseded or cancelled keeps the picture that is there. Only a real
            // failure with nothing else to show says so — a black frame explained nothing.
            guard generation == playbackGeneration, !Task.isCancelled else { return }
            if player == nil {
                playbackProblem = String(describing: error)
            }
            return
        }
        guard generation == playbackGeneration else { return }
        playbackProblem = nil

        let wasPlaying = isPlaying
        let item = AVPlayerItem(asset: assembled.composition)
        // Levels, fades and ducking in the preview too. An editor whose preview plays the music at
        // full volume and whose export ducks it is not previewing anything.
        item.audioMix = assembled.audioMix
        item.audioTimePitchAlgorithm = .spectral
        // Without this the preview plays raw source frames while the export applies the framing,
        // which is the worst kind of editor: one that shows you something it will not deliver.
        item.videoComposition = assembled.videoComposition
        watch(item)

        // One player for the life of the editor, with its item swapped. A new AVPlayer per rebuild
        // left the preview black: the video view on screen kept drawing the player it was first
        // given, which had just been stopped and emptied.
        let player: AVPlayer
        if let existing = self.player {
            existing.pause()
            existing.replaceCurrentItem(with: item)
            player = existing
        } else {
            player = AVPlayer(playerItem: item)
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
        builtSignature = signature
        // The new item starts where the playhead is, not at zero, and keeps playing if it was.
        playhead = min(playhead, duration)
        player.seek(to: CMTime(seconds: playhead, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
        if wasPlaying { player.play() }
        // A reversed clip's copy may have just been written; its background can start now.
        prepareBackgrounds()
    }

    /// Notices when the item on screen stops being playable.
    ///
    /// A failed item stays failed: AVKit shows its crossed-out play symbol and nothing short of a
    /// new item brings the picture back. Before this the preview simply stayed that way — the
    /// composition had not changed, so nothing ever rebuilt it.
    private func watch(_ item: AVPlayerItem) {
        let id = ObjectIdentifier(item)
        itemStatus = item.observe(\.status, options: [.new]) { @Sendable [weak self] observed, _ in
            let status = observed.status
            let message = observed.error.map { String(describing: $0) } ?? "AVPlayerItem failed"
            Task { @MainActor in
                self?.itemStatusChanged(id, status: status, message: message)
            }
        }
    }

    private func itemStatusChanged(_ id: ObjectIdentifier, status: AVPlayerItem.Status, message: String) {
        guard let current = player?.currentItem, ObjectIdentifier(current) == id else { return }
        switch status {
        case .readyToPlay:
            playbackRetries = 0
        case .failed:
            builtSignature = nil
            guard let mediaDirectory, playbackRetries < 3 else {
                // Out of tries: say so, with a button, rather than a crossed-out frame.
                teardownPlayer()
                playbackRetries = 0
                playbackProblem = message
                return
            }
            playbackRetries += 1
            if backgroundJob != nil {
                // The render is the likeliest reason: wait for it rather than fail again beside it.
                recoverAfterBackgrounds = true
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                await self?.loadPlayback(mediaDirectory: mediaDirectory)
            }
        default:
            break
        }
    }

    /// Everything that changes what the preview plays: which footage, which part of it, in what
    /// order, at what speed, with what voice. The player is rebuilt whenever this changes.
    ///
    /// Only speed and voice used to rebuild it. A cut, split, trim, delete or reorder left the
    /// player on the old edit, so the picture moved to the next clip seconds before the timeline did.
    public var compositionSignature: [String] {
        project.segments.map { segment in
            let take = segment.selectedTake
            let range = take.map { "\($0.id.uuidString):\($0.sourceRange.start.seconds):\($0.sourceRange.duration.seconds)" } ?? "-"
            let playback = segment.playback
            return "\(range)|\(playback.speed)|\(playback.isReversed)|\(playback.freeze?.seconds ?? -1)"
        } + [
            // Where every background effect sits, and whether its render is there to play.
            // Filters are read live by the compositor; only whether there are any changes the build.
            "effects:" + project.effects.filter { $0.filter == nil }.map { effect in
                let sound = effect.sound.map { "\($0.token)\($0.volume)" } ?? "-"
                return "\(effect.start.seconds)+\(effect.duration.seconds):\(effect.background?.token ?? "-"):\(sound)"
            }.joined(separator: ","),
            "filters:\(project.effects.contains { $0.filter != nil })",
            "backgrounds:" + backgroundSignature,
            "voice:\(project.voiceEffects.noiseReduction)\(project.voiceEffects.voiceEnhance)\(project.voiceEffects.deRumble)",
            "format:\(project.format.renderSize.width)x\(project.format.renderSize.height)",
            "main-video:\(project.mainVideoPlacement)|\(project.mainVideoVolume)|\(project.recordings.map { ($0.reframe ?? [], $0.cameraMotions ?? []) })",
            "video-layers:" + project.videoLayers.map { layer in
                "\(layer.id)|\(layer.recordingID)|\(layer.start.seconds)|\(layer.sourceRange.start.seconds)|\(layer.sourceRange.duration.seconds)|\(layer.placement)|\(layer.volume)|\(layer.isMuted)|\(layer.isHidden)|\(layer.keyframes)|\(layer.focusKeyframes ?? [])"
            }.joined(separator: ","),
        ] + project.audio.map { clip in
            "audio:\(clip.id.uuidString)|\(clip.start.seconds)|\(clip.sourceRange.start.seconds)|\(clip.sourceRange.duration.seconds)|\(clip.gain)|\(clip.fadeIn.seconds)|\(clip.fadeOut.seconds)|\(clip.speed)|\(clip.isMuted)|\(clip.ducksUnderVoice)|\(AudioEffectRenderer.token(for: clip.effects))"
        }
    }

    private func teardownPlayer() {
        builtSignature = nil
        itemStatus = nil
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
        MediaTime(seconds: playhead).preciseTimecode
    }

    public var durationLabel: String {
        MediaTime(seconds: duration).timecode
    }

    public func start(at index: Int) -> Double {
        project.segments.prefix(max(0, index)).reduce(0) { $0 + $1.barWeight }
    }

    public func isActive(at index: Int) -> Bool {
        let start = start(at: index)
        return playhead >= start && playhead < start + project.segments[index].barWeight
    }

    public func rangeLabel(at index: Int) -> String {
        guard project.segments.indices.contains(index) else { return "" }
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
            PlaybackAudio.activate()
            player.seek(to: CMTime(seconds: playhead, preferredTimescale: 600)) { _ in }
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
        let playback = project.segments[index].playback
        let wanted = max(0.4, seconds)

        // A frozen segment has no footage to trim: dragging its edge changes how long the frame is
        // held. Same gesture, and it edits the thing the clip's length actually comes from.
        if playback.freeze != nil {
            record("editor.change.freezeLength", symbol: "snowflake", coalescing: "trim-\(index)")
            project.segments[index].playback.freeze = MediaTime(seconds: wanted)
            project.updatedAt = .now
            return
        }

        // The handle is dragged in timeline seconds; what it edits is source seconds. At half
        // speed a centimetre of finger is two seconds of footage.
        var clamped = playback.sourceSeconds(forTimeline: wanted)

        // A segment cannot be longer than the footage behind it. Dragging past the end used to be
        // allowed, and the export found out the hard way.
        if let take = project.segments[index].selectedTake,
           let recording = project.recordings.first(where: { $0.id == take.recordingID }) {
            clamped = min(clamped, recording.duration.seconds - take.sourceRange.start.seconds)
            guard clamped > 0.1 else { return }
        }

        record("editor.change.trim", symbol: "arrow.left.and.right", coalescing: "trim-\(index)")
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
    public var canSplitAtPlayhead: Bool {
        guard let (index, offset) = segmentAtPlayhead else { return false }
        let segment = project.segments[index]
        return offset > 0.15 && segment.barWeight - offset > 0.15 && segment.playback.freeze == nil
    }

    /// Where a cut at `offset` into a clip really goes, in the clip's footage seconds.
    ///
    /// A cut that lands inside a word leaves half a syllable on each side, and the jump it makes
    /// is the first thing anyone notices in a talking video. When the playhead is inside a word,
    /// the cut moves to the nearer edge of that word — a quarter of a second at most.
    func cutPoint(inSegmentAt index: Int, offset: Double, snapToWords: Bool = true) -> Double {
        let segment = project.segments[index]
        let length = segment.sourceSeconds
        let sourceOffset = min(max(0, segment.playback.sourceSeconds(forTimeline: offset)), length)
        // Reversed, the timeline runs from the end of the footage.
        let footage = segment.playback.isReversed ? length - sourceOffset : sourceOffset
        guard snapToWords, let words = segment.selectedTake?.transcript?.words,
              let word = words.first(where: { $0.range.start.seconds < footage && footage < $0.range.end.seconds })
        else { return footage }
        let before = word.range.start.seconds
        let after = word.range.end.seconds
        let nearer = footage - before < after - footage ? before : after
        guard abs(nearer - footage) <= 0.25, nearer > 0.1, nearer < length - 0.1 else { return footage }
        return nearer
    }

    /// Splits the segment under the playhead in two.
    ///
    /// The razor, and the tool our model was waiting for: both halves point at the same recording
    /// with adjacent source ranges, so nothing is copied, nothing is re-encoded, and the file on
    /// disk is untouched. A split is two numbers. It lands between words rather than inside one,
    /// works on reversed clips too, and the playhead moves to where the cut really went.
    ///
    /// - Parameter snapToWords: off for cuts made at an exact number (the AI's, a speed range's).
    public func splitAtPlayhead(snapToWords: Bool = true) {
        guard let (index, offset) = segmentAtPlayhead else { return }
        let segment = project.segments[index]
        // A split right on a boundary produces an empty clip, which is never what was meant.
        guard offset > 0.15, segment.barWeight - offset > 0.15 else { return }
        // A freeze holds one frame: there is nothing inside it to divide.
        guard segment.playback.freeze == nil else { return }

        let reversed = segment.playback.isReversed
        let length = segment.sourceSeconds
        // In footage seconds from the start of the take.
        let footage = cutPoint(inSegmentAt: index, offset: offset, snapToWords: snapToWords)
        guard footage > 0.05, length - footage > 0.05 else { return }
        // The part of the footage that comes first on the timeline, and the part after it.
        let first = reversed ? (from: footage, to: length) : (from: 0.0, to: footage)
        let second = reversed ? (from: 0.0, to: footage) : (from: footage, to: length)

        var left = segment
        var right = segment.copyWithNewIdentity()

        if let take = segment.selectedTake {
            var leftTake = take
            leftTake.sourceRange = MediaTimeRange(
                start: take.sourceRange.start + MediaTime(seconds: first.from),
                duration: MediaTime(seconds: first.to - first.from)
            )
            leftTake.transcript = take.transcript?.slice(from: first.from, to: first.to)
            var rightTake = Take(
                recordingID: take.recordingID,
                sourceRange: MediaTimeRange(
                    start: take.sourceRange.start + MediaTime(seconds: second.from),
                    duration: MediaTime(seconds: second.to - second.from)
                ),
                status: take.status
            )
            // The words go with their footage. This used to be nil, which left the right half with
            // no transcript, no captions and nothing to edit by text until it was listened to again.
            rightTake.transcript = take.transcript?.slice(from: second.from, to: second.to)

            left.takes = [leftTake]
            left.selectedTakeID = leftTake.id
            right.takes = [rightTake]
            right.selectedTakeID = rightTake.id
        } else {
            // Estimates are in source seconds like everything else a segment stores, so the split
            // point has to be converted even when there is no footage behind it yet.
            left.estimatedDuration = MediaTime(seconds: first.to - first.from)
            right.estimatedDuration = MediaTime(seconds: second.to - second.from)
        }

        if let leftWords = left.selectedTake?.transcript, let rightWords = right.selectedTake?.transcript,
           segment.selectedTake?.transcript != nil {
            // What was actually said on each side, rather than the script cut at a guessed ratio.
            left.script = leftWords.text
            right.script = rightWords.text
        } else {
            let words = ScriptText.words(in: segment.script).map(String.init)
            if !words.isEmpty {
                let cut = max(1, min(words.count - 1, Int((offset / segment.barWeight * Double(words.count)).rounded())))
                left.script = words[..<cut].joined(separator: " ")
                right.script = words[cut...].joined(separator: " ")
            }
        }
        // Read again from each half's words, with anything typed by hand carried to the side it
        // was on. Clearing them was how a split used to delete a clip's captions.
        let maxWords = project.captionStyle.maxWordsPerCue
        left.refreshCaptions(maxWordsPerCue: maxWords, carrying: segment.captions.map { $0.shifted(by: -first.from) })
        right.refreshCaptions(maxWordsPerCue: maxWords, carrying: segment.captions.map { $0.shifted(by: -second.from) })

        record("editor.change.split", symbol: "scissors")
        project.segments[index] = left
        project.segments.insert(right, at: index + 1)
        project.updatedAt = .now
        inspectedSegment = right.id
        // The playhead to where the cut really went: the start of the second half.
        seek(to: start(at: index + 1))
    }

    /// Removes a segment. Everything after it closes up on its own, because the timeline is
    /// derived — there is no ripple to perform, only one less thing to lay out.
    public func deleteSegment(at index: Int) {
        guard project.segments.indices.contains(index), project.segments.count > 1 else { return }
        record("editor.change.delete", symbol: "trash")
        let removed = project.segments.remove(at: index)
        if inspectedSegment == removed.id { inspectedSegment = nil }
        project.updatedAt = .now
        playhead = min(playhead, duration)
    }

    public func duplicateSegment(at index: Int) {
        guard project.segments.indices.contains(index) else { return }
        record("editor.change.duplicate", symbol: "plus.square.on.square")
        var copy = project.segments[index].copyWithNewIdentity()
        // Takes keep pointing at the same recording: a duplicate is another window onto the same
        // footage, not another copy of it.
        // Same words at the same times, under new identities so the two copies can be edited apart.
        copy.captions = copy.captions.map {
            CaptionCue(text: $0.text, range: $0.range, styleOverride: $0.styleOverride, position: $0.position, isUserEdited: $0.isUserEdited)
        }
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

        record("editor.change.merge", symbol: "arrow.trianglehead.merge")
        var merged = project.segments[index]
        var take = left
        take.sourceRange = MediaTimeRange(
            start: left.sourceRange.start,
            duration: left.sourceRange.duration + right.sourceRange.duration
        )
        let leftSeconds = left.sourceRange.duration.seconds
        if left.transcript != nil || right.transcript != nil {
            take.transcript = (left.transcript ?? Transcript(localeIdentifier: project.localeIdentifier, words: []))
                .appending(right.transcript, at: leftSeconds)
        }
        merged.takes = [take]
        merged.selectedTakeID = take.id
        merged.script = [project.segments[index].script, project.segments[index + 1].script]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        merged.refreshCaptions(
            maxWordsPerCue: project.captionStyle.maxWordsPerCue,
            carrying: project.segments[index].captions
                + project.segments[index + 1].captions.map { $0.shifted(by: leftSeconds) }
        )

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
        record("editor.change.move", symbol: "arrow.left.arrow.right")
        let segment = project.segments.remove(at: index)
        project.segments.insert(segment, at: destination)
        project.updatedAt = .now
    }

    /// Exchanges two positions without moving the clips between them. This is distinct from
    /// `move`: dropping a lifted clip on another clip means "put these two in each other's place".
    public func swapSegments(at index: Int, with destination: Int) {
        guard project.segments.indices.contains(index),
              project.segments.indices.contains(destination),
              index != destination
        else { return }
        record("editor.change.move", symbol: "arrow.left.arrow.right")
        project.segments.swapAt(index, destination)
        project.updatedAt = .now
    }

    /// Applies the locally analysed structure as one history entry, so the user can review a
    /// useful set of roles and undo it in one step rather than chasing individual chips.
    public func applyRoleSuggestions(_ suggestions: [SegmentRoleAnalyzer.Suggestion]) {
        let byID = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.segmentID, $0.role) })
        let changes = project.segments.filter { byID[$0.id] != nil && byID[$0.id] != $0.role }
        guard !changes.isEmpty else { return }
        record("editor.change.autoStructure", symbol: "sparkles")
        for index in project.segments.indices {
            if let role = byID[project.segments[index].id] {
                project.segments[index].role = role
                project.segments[index].metadata["roleAssignment"] = "automatic"
            }
        }
        project.updatedAt = .now
    }

    /// Runs whenever the editor gains enough text to understand the video's structure. Manual
    /// choices are final; earlier automatic choices may improve when a real transcript arrives.
    @discardableResult
    public func autoAssignSegmentRoles() -> Int {
        let suggestions = SegmentRoleAnalyzer.automaticSuggestions(
            for: project.segments,
            localeIdentifier: project.localeIdentifier
        )
        let changed = suggestions.filter { suggestion in
            project.segments.first(where: { $0.id == suggestion.segmentID })?.role != suggestion.role
        }.count
        applyRoleSuggestions(suggestions)
        return changed
    }
}


// MARK: - Audio

extension EditorModel {
    /// Switches voice repair for the whole video.
    public func setVoiceEffects(_ effects: AudioEffects) {
        guard effects != project.voiceEffects else { return }
        record("editor.change.voice", symbol: "person.wave.2")
        project.voiceEffects = effects
        project.updatedAt = .now
    }

    public var isVoiceCleaned: Bool { project.voiceEffects.isActive }

    public func toggleVoiceCleanup() {
        setVoiceEffects(
            isVoiceCleaned
                ? AudioEffects()
                : AudioEffects(noiseReduction: true, voiceEnhance: true, deRumble: true)
        )
    }

    /// Clips in the order they start, which is the order the lane draws them.
    public var audioClips: [AudioClip] {
        project.audio.sorted { $0.start.seconds < $1.start.seconds }
    }

    public var selectedAudioClip: AudioClip? {
        selectedAudio.flatMap { id in project.audio.first { $0.id == id } }
    }

    public func addAudio(_ clip: AudioClip) {
        record("editor.change.audioAdd", symbol: "music.note")
        project.audio.append(clip)
        project.updatedAt = .now
        selectedAudio = clip.id
        inspectedSegment = nil
    }

    /// Every audio edit goes through here so there is exactly one place that stamps `updatedAt`
    /// and one place that decides what a legal value is.
    public func updateAudio(_ id: AudioClip.ID, _ change: (inout AudioClip) -> Void) {
        guard let index = project.audio.firstIndex(where: { $0.id == id }) else { return }
        record("editor.change.audioAdjust", symbol: "slider.horizontal.3", coalescing: "audio-\(id)")
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
        record("editor.change.audioRemove", symbol: "trash")
        project.audio.removeAll { $0.id == id }
        waveforms[id] = nil
        if selectedAudio == id { selectedAudio = nil }
        project.updatedAt = .now
    }

    public func duplicateAudio(_ id: AudioClip.ID) {
        guard let clip = project.audio.first(where: { $0.id == id }) else { return }
        record("editor.change.duplicate", symbol: "plus.square.on.square")
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

        record("editor.change.split", symbol: "scissors")
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

    /// Reads frames for any take that does not have them yet.
    ///
    /// One frame for every two seconds of footage, between one and six: enough to recognise the
    /// shot at any zoom, few enough that a thirty clip import is not thirty decodes a second.
    public func loadThumbnails(mediaDirectory: URL) async {
        let sampler = ThumbnailSampler()
        for segment in project.segments {
            guard let take = segment.selectedTake, thumbnails[take.id] == nil,
                  let recording = project.recordings.first(where: { $0.id == take.recordingID })
            else { continue }
            let url = mediaDirectory.appending(
                path: (recording.relativePath as NSString).lastPathComponent,
                directoryHint: .notDirectory
            )
            let seconds = take.sourceRange.duration.seconds
            let frames = await sampler.frames(
                of: url,
                from: take.sourceRange.start.seconds,
                duration: seconds,
                count: min(20, max(3, Int(seconds)))
            )
            guard !frames.isEmpty else { continue }
            withAnimation(.easeOut(duration: 0.3)) {
                thumbnails[take.id] = frames
            }
        }
    }

    /// How long the timeline is once the audio is taken into account.
    ///
    /// Music that runs past the last clip is a real thing people do — an outro over black — and a
    /// timeline that refuses to draw it makes the tail impossible to trim.
    public var timelineDuration: Double {
        // Added videos are not counted: they play over the video and end with it, the way every
        // editor's overlay tracks do. A layer drawn past the end was a bar with nothing behind it.
        max(duration, project.audio.map { $0.timelineRange.end.seconds }.max() ?? 0)
    }

    public var selectedVideoLayerValue: VideoLayer? {
        selectedVideoLayer.flatMap { id in project.videoLayers.first { $0.id == id } }
    }

    public func select(videoLayer id: VideoLayer.ID?) {
        selectedVideoLayer = id
        subjectTracking = .idle
        if id != nil {
            inspectedSegment = nil
            selectedAudio = nil
            selectedOverlay = nil
            selectedEffect = nil
        }
    }

    public func updateVideoLayer(_ id: VideoLayer.ID, _ change: (inout VideoLayer) -> Void) {
        updateVideoLayer(id, coalescing: nil, change)
    }

    public func updateVideoLayer(
        _ id: VideoLayer.ID,
        coalescing key: String?,
        _ change: (inout VideoLayer) -> Void
    ) {
        guard let index = project.videoLayers.firstIndex(where: { $0.id == id }) else { return }
        project.videoLayers[index].separateLegacyTracking()
        record("editor.change.videoLayerAdjust", symbol: "rectangle.split.2x1", coalescing: key)
        change(&project.videoLayers[index])
        // Never longer than the file behind it: past its last frame there is nothing to play.
        var length = max(0.2, project.videoLayers[index].sourceRange.duration.seconds)
        if let recording = project.recording(id: project.videoLayers[index].recordingID) {
            length = min(length, max(0.2, recording.duration.seconds - project.videoLayers[index].sourceRange.start.seconds))
        }
        // Inside the video: it starts before the end and stops by it.
        let videoEnd = duration
        let start = min(max(0, project.videoLayers[index].start.seconds), max(0, videoEnd - 0.2))
        length = min(length, max(0.2, videoEnd - start))
        project.videoLayers[index].sourceRange.duration = MediaTime(seconds: length)
        project.videoLayers[index].start = MediaTime(seconds: start)
        project.videoLayers[index].placement = project.videoLayers[index].placement.bounded
        project.videoLayers[index].volume = min(max(project.videoLayers[index].volume, 0), 1)
        project.updatedAt = .now
    }

    public func removeVideoLayer(_ id: VideoLayer.ID) {
        guard project.videoLayers.contains(where: { $0.id == id }) else { return }
        record("editor.change.videoLayerRemove", symbol: "trash")
        project.videoLayers.removeAll { $0.id == id }
        if selectedVideoLayer == id { selectedVideoLayer = nil }
        project.updatedAt = .now
    }

    /// Applies a layout to the main movie and all additional movies, preserving their timing.
    public func applyVideoLayout(_ layout: VideoLayout) {
        guard !project.videoLayers.isEmpty else { return }
        record("editor.change.videoLayout", symbol: "rectangle.split.2x1")
        let placements = layout.placements(count: min(1 + project.videoLayers.count, 4))
        project.mainVideoPlacement = placements[0]
        for index in project.videoLayers.indices {
            project.videoLayers[index].placement = placements[min(index + 1, placements.count - 1)]
            // A layout is a place, not a path: old motion would pull the layer straight back out.
            project.videoLayers[index].keyframes = []
        }
        project.updatedAt = .now
    }

    public func addVideoKeyframe(to id: VideoLayer.ID) {
        guard let layer = project.videoLayers.first(where: { $0.id == id }) else { return }
        let time = min(max(playhead - layer.start.seconds, 0), layer.duration)
        let placement = layer.placement(at: playhead)
        updateVideoLayer(id, coalescing: "video-layer-keyframe-\(id)") { value in
            value.keyframes.removeAll { abs($0.time - time) < 0.02 }
            value.keyframes.append(VideoKeyframe(time: time, placement: placement))
            value.keyframes.sort { $0.time < $1.time }
        }
    }

    /// Mirroring is a property of the whole source, including every smart-reframe point. Toggling
    /// only the base placement made an animated layer turn itself back around at its first frame.
    public func toggleVideoLayerMirror(_ id: VideoLayer.ID) {
        updateVideoLayer(id, coalescing: "video-layer-mirror-\(id)") { value in
            func mirrored(_ placement: VideoPlacement) -> VideoPlacement {
                var placement = placement
                placement.isMirrored.toggle()
                placement.focusX = placement.focusX.map { 1 - $0 }
                return placement
            }
            value.placement = mirrored(value.placement)
            value.keyframes = value.keyframes.map {
                var frame = $0
                frame.placement = mirrored(frame.placement)
                return frame
            }
            value.focusKeyframes = value.focusKeyframes?.map {
                var frame = $0
                frame.x = 1 - frame.x
                return frame
            }
        }
    }

    /// Places the layer. A layer without keyframes simply moves; one that already animates gets a
    /// keyframe at the playhead. Adding a keyframe to every drag used to turn a plain move made in
    /// the middle of a layer into a slow slide from the old place.
    public func setVideoLayerPlacement(_ id: VideoLayer.ID, _ placement: VideoPlacement) {
        updateVideoLayer(id, coalescing: "video-layer-placement-\(id)") { value in
            let time = min(max(playhead - value.start.seconds, 0), value.duration)
            if !value.keyframes.isEmpty {
                value.keyframes.removeAll { abs($0.time - time) < 0.02 }
                value.keyframes.append(VideoKeyframe(time: time, placement: placement.bounded))
                value.keyframes.sort { $0.time < $1.time }
            } else {
                value.placement = placement.bounded
            }
        }
    }

    public func nudgeVideoLayer(_ id: VideoLayer.ID, x: Double = 0, y: Double = 0) {
        updateVideoLayer(id, coalescing: "video-layer-nudge-\(id)") { value in
            var placement = value.placement(at: playhead)
            placement.x += x
            placement.y += y
            let time = min(max(playhead - value.start.seconds, 0), value.duration)
            if !value.keyframes.isEmpty {
                value.keyframes.removeAll { abs($0.time - time) < 0.02 }
                value.keyframes.append(VideoKeyframe(time: time, placement: placement.bounded))
                value.keyframes.sort { $0.time < $1.time }
            } else {
                value.placement = placement.bounded
            }
        }
    }

    /// Follows the principal face inside this layer's existing rectangle. The layout stays where
    /// the user put it; only the crop moves, so side-by-side and picture-in-picture remain intact.
    public func smartReframeVideoLayer(_ id: VideoLayer.ID) async {
        if case .analyzing = subjectTracking { return }
        guard let layer = project.videoLayers.first(where: { $0.id == id }),
              let recording = project.recording(id: layer.recordingID),
              let mediaDirectory
        else {
            subjectTracking = .failed
            return
        }

        pause()
        subjectTracking = .analyzing(0)
        let source = mediaDirectory.appending(
            path: (recording.relativePath as NSString).lastPathComponent,
            directoryHint: .notDirectory
        )
        do {
            let focuses = try await SubjectTracker().faceFocus(
                in: source,
                sourceStart: layer.sourceRange.start.seconds,
                duration: layer.duration
            ) { [weak self] progress in
                guard self?.selectedVideoLayer == id else { return }
                self?.subjectTracking = .analyzing(progress)
            }
            // The layer as it is now: it may have been trimmed or moved while the frames were read.
            guard let index = project.videoLayers.firstIndex(where: { $0.id == id }),
                  project.videoLayers[index].sourceRange.start == layer.sourceRange.start
            else {
                subjectTracking = .idle
                return
            }
            guard !focuses.isEmpty else {
                subjectTracking = .noFace
                return
            }
            let mirrored = project.videoLayers[index].placement.isMirrored
            record("editor.change.smartReframe", symbol: "viewfinder")
            project.videoLayers[index].separateLegacyTracking()
            project.videoLayers[index].placement.fillsFrame = true
            project.videoLayers[index].placement.focusX = nil
            project.videoLayers[index].placement.focusY = nil
            project.videoLayers[index].keyframes = project.videoLayers[index].keyframes.map { frame in
                var frame = frame
                frame.placement.fillsFrame = true
                frame.placement.focusX = nil
                frame.placement.focusY = nil
                return frame
            }
            project.videoLayers[index].focusKeyframes = focuses.map {
                VideoFocusKeyframe(time: $0.time, x: mirrored ? 1 - $0.x : $0.x, y: $0.y, confidence: $0.confidence)
            }
            project.updatedAt = .now
            subjectTracking = .applied(focuses.count)
        } catch SubjectTrackingError.noFace {
            subjectTracking = .noFace
        } catch is CancellationError {
            subjectTracking = .idle
        } catch {
            subjectTracking = .failed
        }
    }

    /// True when the added video follows a face.
    public func isReframed(videoLayer id: VideoLayer.ID) -> Bool {
        !(project.videoLayers.first { $0.id == id }?.orderedFocusKeyframes.isEmpty ?? true)
    }

    /// Stops following the face: the crop goes back to the centre.
    public func removeReframe(fromVideoLayer id: VideoLayer.ID) {
        guard isReframed(videoLayer: id),
              let index = project.videoLayers.firstIndex(where: { $0.id == id }) else { return }
        record("editor.change.smartReframeRemoved", symbol: "viewfinder")
        project.videoLayers[index].focusKeyframes = []
        project.updatedAt = .now
        subjectTracking = .idle
    }

    /// True when any recording of the main video follows a face.
    public var isMainVideoReframed: Bool {
        project.recordings.contains { !($0.reframe ?? []).isEmpty }
    }

    /// Stops following faces in the main video.
    public func removeMainReframe() {
        guard isMainVideoReframed else { return }
        record("editor.change.smartReframeRemoved", symbol: "viewfinder")
        for index in project.recordings.indices { project.recordings[index].reframe = nil }
        project.updatedAt = .now
        mainSubjectTracking = .idle
    }

    /// The still shown by the subject picker is the source frame, not the already-cropped player.
    /// That makes a stroke's normalised coordinates the same coordinates Vision receives.
    public func subjectSelectionFrame() async -> UIImage? {
        guard let target = subjectTrackingTarget() else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: target.url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1440, height: 1440)
        guard let (image, _) = try? await generator.image(
            at: CMTime(seconds: target.reference, preferredTimescale: 600)
        ) else { return nil }
        return UIImage(cgImage: image)
    }

    /// Turns one direct manipulation on the picture into a source-space motion track. Zoom is a
    /// separate camera channel: changing it never rewrites the selected subject's path.
    public func trackSelectedSubject(in bounds: CGRect, zoom: Double, correctionRadius: Double? = nil) async {
        if case .analyzing = mainSubjectTracking { return }
        guard canApplySubjectTracking, let target = subjectTrackingTarget() else {
            mainSubjectTracking = .failed
            return
        }
        let takeStart = target.take.sourceRange.start.seconds
        let takeEnd = target.take.sourceRange.end.seconds
        let analysisStart = correctionRadius.map { max(takeStart, target.reference - max(0.5, $0)) } ?? takeStart
        let analysisEnd = correctionRadius.map { min(takeEnd, target.reference + max(0.5, $0)) } ?? takeEnd
        pause()
        mainSubjectTracking = .analyzing(0)
        do {
            let focuses = try await SubjectTracker().objectFocus(
                in: target.url,
                sourceStart: analysisStart,
                duration: analysisEnd - analysisStart,
                referenceTime: target.reference,
                initialBounds: bounds
            ) { [weak self] progress in
                self?.mainSubjectTracking = .analyzing(progress)
            }
            guard !focuses.isEmpty,
                  let recordingIndex = project.recordings.firstIndex(where: { $0.id == target.recordingID }),
                  project.segments.contains(where: {
                      $0.selectedTake?.id == target.take.id && $0.selectedTake?.sourceRange == target.take.sourceRange
                  })
            else { mainSubjectTracking = .failed; return }

            record(correctionRadius == nil ? "editor.change.subjectTrack" : "editor.change.subjectTrackCorrection", symbol: "scope")
            let replacement = focuses.map {
                VideoFocusKeyframe(
                    time: analysisStart + $0.time,
                    x: $0.x,
                    y: $0.y,
                    zoom: min(max(zoom, 1.1), 1.2),
                    confidence: $0.confidence
                )
            }
            // A local correction only replaces the span Vision actually recovered. If tracking
            // immediately loses one side, deleting the still-valid old points there makes the fix
            // worse than the original. A full new track intentionally replaces the whole take.
            let range = correctionRadius == nil
                ? takeStart...takeEnd
                : (replacement.first?.time ?? analysisStart)...(replacement.last?.time ?? analysisEnd)
            let kept = (project.recordings[recordingIndex].reframe ?? []).filter { !range.contains($0.time) }
            project.recordings[recordingIndex].reframe = (kept + replacement).sorted { $0.time < $1.time }
            project.mainVideoPlacement.fillsFrame = true
            project.updatedAt = .now
            let total = (project.recordings[recordingIndex].reframe ?? []).filter {
                $0.time >= takeStart - 0.0001 && $0.time <= takeEnd + 0.0001
            }.count
            mainSubjectTracking = .applied(total)
        } catch is CancellationError {
            mainSubjectTracking = .idle
        } catch {
            mainSubjectTracking = .failed
        }
    }

    /// Confidence points for the primary clip under the playhead, converted from recording time
    /// to the visible timeline. Old projects have no confidence and stay quietly green.
    public var subjectTrackReviewPoints: [SubjectTrackReviewPoint] {
        guard let (index, _) = segmentAtPlayhead,
              let take = project.segments[index].selectedTake,
              let recording = project.recording(id: take.recordingID)
        else { return [] }
        let segment = project.segments[index]
        let takeStart = take.sourceRange.start.seconds
        let takeLength = take.sourceRange.duration.seconds
        let timelineStart = start(at: index)
        return (recording.reframe ?? []).compactMap { frame in
            let sourceOffset = frame.time - takeStart
            guard let localTime = segment.playback.timelineOffset(
                forSourceOffset: sourceOffset,
                sourceLength: takeLength
            ) else { return nil }
            return SubjectTrackReviewPoint(
                id: frame.id,
                timelineTime: timelineStart + localTime,
                confidence: min(max(frame.confidence ?? 1, 0), 1),
                progress: min(max(localTime / max(segment.barWeight, 0.001), 0), 1)
            )
        }.sorted { $0.progress < $1.progress }
    }

    public func beginSubjectCorrection(at timelineTime: Double) {
        pause()
        seek(to: timelineTime)
        mainSubjectTracking = .idle
    }

    public var mainVideoZoom: Double {
        if let recipe = cameraMotionAtPlayhead, recipe.kind == .hold {
            return 1 + recipe.amount
        }
        return project.mainVideoPlacement.zoom ?? 1
    }

    public var canApplySubjectTracking: Bool {
        guard let (index, _) = segmentAtPlayhead else { return false }
        return project.segments[index].selectedTake != nil && project.segments[index].playback.freeze == nil
    }

    public var canApplyCameraMotion: Bool { canApplySubjectTracking }

    public func setMainVideoZoom(_ value: Double) {
        let zoom = min(max(value, 1), 3)
        guard let target = cameraMotionTarget(),
              let recordingIndex = project.recordings.firstIndex(where: { $0.id == target.recordingID })
        else { return }
        let range = target.take.sourceRange
        let overlapping = (project.recordings[recordingIndex].cameraMotions ?? []).filter {
            $0.end > range.start.seconds + 0.0001 && $0.start < range.end.seconds - 0.0001
        }
        let sameHold = overlapping.count == 1
            && overlapping[0].kind == .hold
            && abs(1 + overlapping[0].amount - zoom) < 0.0001
            && project.mainVideoPlacement.zoom == nil
        guard !sameHold else { return }
        record("editor.change.zoom", symbol: "plus.magnifyingglass", coalescing: "main-video-zoom-\(target.take.id)")
        let kept = (project.recordings[recordingIndex].cameraMotions ?? []).filter {
            $0.end <= range.start.seconds + 0.0001 || $0.start >= range.end.seconds - 0.0001
        }
        if zoom > 1.005 {
            let priorHold = overlapping.last { $0.kind == .hold }
            let hold = CameraMotionRecipe(
                id: priorHold?.id ?? UUID(),
                sourceRange: range,
                amount: zoom - 1,
                kind: .hold
            )
            project.recordings[recordingIndex].cameraMotions = (kept + [hold]).sorted { $0.start < $1.start }
        } else {
            project.recordings[recordingIndex].cameraMotions = kept
        }
        project.mainVideoPlacement.fillsFrame = true
        // Build 66 stored this globally. The first intentional edit migrates it to this source clip.
        project.mainVideoPlacement.zoom = nil
        project.updatedAt = .now
    }

    public func applyCameraMotion(
        _ kind: CameraMotionRecipe.Kind,
        amount: Double,
        feel: CameraMotionRecipe.Feel = .natural
    ) {
        guard canApplyCameraMotion,
              let target = cameraMotionTarget(),
              let recordingIndex = project.recordings.firstIndex(where: { $0.id == target.recordingID })
        else { return }
        record("editor.change.zoomRecipe", symbol: "plus.magnifyingglass")
        let range = target.take.sourceRange
        let reversed = segmentAtPlayhead.map { project.segments[$0.index].playback.isReversed } ?? false
        let existing = (project.recordings[recordingIndex].cameraMotions ?? []).filter {
            $0.end <= range.start.seconds || $0.start >= range.end.seconds
        }
        let recipe = CameraMotionRecipe(
            sourceRange: range,
            amount: amount,
            kind: kind.facingTimeline(isReversed: reversed),
            feel: feel
        )
        project.recordings[recordingIndex].cameraMotions = (existing + [recipe]).sorted { $0.start < $1.start }
        // A manual static zoom and a motion recipe describe the same camera channel. The recipe is
        // visible on the timeline, so choosing it intentionally replaces the hidden static value.
        project.mainVideoPlacement.zoom = nil
        project.mainVideoPlacement.fillsFrame = true
        project.updatedAt = .now
    }

    public var cameraMotionAtPlayhead: CameraMotionRecipe? {
        guard let target = cameraMotionTarget(),
              let recording = project.recording(id: target.recordingID)
        else { return nil }
        guard var recipe = recording.cameraMotions?.last(where: {
            target.reference >= $0.start - 0.0001 && target.reference <= $0.end + 0.0001
        }) else { return nil }
        let reversed = segmentAtPlayhead.map { project.segments[$0.index].playback.isReversed } ?? false
        recipe.kind = recipe.kind.facingTimeline(isReversed: reversed)
        return recipe
    }

    public func removeCameraMotionAtPlayhead() {
        guard let target = cameraMotionTarget(),
              let recordingIndex = project.recordings.firstIndex(where: { $0.id == target.recordingID }),
              let selected = cameraMotionAtPlayhead
        else { return }
        record("editor.change.zoomRecipeRemoved", symbol: "minus.magnifyingglass")
        project.recordings[recordingIndex].cameraMotions?.removeAll { $0.id == selected.id }
        project.updatedAt = .now
    }

    private struct SubjectTrackingTarget {
        var url: URL
        var take: Take
        var recordingID: Recording.ID
        var reference: Double
    }

    private struct CameraMotionTarget {
        var take: Take
        var recordingID: Recording.ID
        var reference: Double
    }

    /// Camera metadata remains editable while playback is still preparing. It only needs the
    /// selected source clock; requiring a resolved media URL made fast taps silently do nothing.
    private func cameraMotionTarget() -> CameraMotionTarget? {
        guard let (index, offset) = segmentAtPlayhead,
              let take = project.segments[index].selectedTake,
              let recording = project.recording(id: take.recordingID)
        else { return nil }
        let resolvedOffset = project.segments[index].playback.sourceOffset(
            forTimeline: offset,
            sourceLength: take.sourceRange.duration.seconds
        )
        let reference = take.sourceRange.start.seconds
            + min(max(resolvedOffset, 0), max(0, take.sourceRange.duration.seconds - 0.02))
        return CameraMotionTarget(take: take, recordingID: recording.id, reference: reference)
    }

    private func subjectTrackingTarget() -> SubjectTrackingTarget? {
        guard let mediaDirectory,
              let target = cameraMotionTarget(),
              let recording = project.recording(id: target.recordingID)
        else { return nil }
        let url = mediaDirectory.appending(
            path: (recording.relativePath as NSString).lastPathComponent,
            directoryHint: .notDirectory
        )
        return SubjectTrackingTarget(
            url: url,
            take: target.take,
            recordingID: recording.id,
            reference: target.reference
        )
    }

    /// Reframes the primary cut. Faces are found once per recording file, across the part of it
    /// the clips use, and kept in the file's own seconds — so splitting, trimming, speed and
    /// choosing another take all stay on the face. Edits made while it reads are kept: only the
    /// recordings' tracks are written at the end.
    public func smartReframeMainVideo() async {
        if case .analyzing = mainSubjectTracking { return }
        guard let mediaDirectory else { mainSubjectTracking = .failed; return }
        // Per file: the span from the first used second to the last.
        var spans: [(recording: Recording, start: Double, end: Double)] = []
        for take in project.segments.compactMap(\.selectedTake) {
            guard let recording = project.recording(id: take.recordingID) else { continue }
            let start = take.sourceRange.start.seconds, end = start + take.sourceRange.duration.seconds
            if let i = spans.firstIndex(where: { $0.recording.id == recording.id }) {
                spans[i].start = min(spans[i].start, start)
                spans[i].end = max(spans[i].end, end)
            } else {
                spans.append((recording, start, end))
            }
        }
        guard !spans.isEmpty else { mainSubjectTracking = .failed; return }
        pause()
        mainSubjectTracking = .analyzing(0)
        var tracks: [Recording.ID: [VideoFocusKeyframe]] = [:]
        do {
            for (done, span) in spans.enumerated() {
                try Task.checkCancellation()
                let url = mediaDirectory.appending(path: (span.recording.relativePath as NSString).lastPathComponent, directoryHint: .notDirectory)
                do {
                    let focuses = try await SubjectTracker().faceFocus(
                        in: url,
                        sourceStart: span.start,
                        duration: span.end - span.start
                    ) { [weak self] local in
                        self?.mainSubjectTracking = .analyzing((Double(done) + local) / Double(spans.count))
                    }
                    tracks[span.recording.id] = focuses.map {
                        VideoFocusKeyframe(time: span.start + $0.time, x: $0.x, y: $0.y, confidence: $0.confidence)
                    }
                } catch SubjectTrackingError.noFace {
                    continue
                } catch SubjectTrackingError.emptyRange {
                    continue
                }
            }
            let points = tracks.values.reduce(0) { $0 + $1.count }
            guard points > 0 else { mainSubjectTracking = .noFace; return }
            record("editor.change.smartReframe", symbol: "viewfinder")
            for index in project.recordings.indices {
                if let track = tracks[project.recordings[index].id] { project.recordings[index].reframe = track }
            }
            project.updatedAt = .now
            mainSubjectTracking = .applied(points)
        } catch is CancellationError {
            mainSubjectTracking = .idle
        } catch {
            mainSubjectTracking = .failed
        }
    }
}


// MARK: - The inspector's edits

extension EditorModel {
    /// Everything the inspector changes goes through one of these rather than through a binding
    /// straight into the array. One place stamps `updatedAt`, one place decides what a legal value
    /// is, and the app-level save sees every edit the same way.
    public func updateSegment(at index: Int, _ change: (inout Segment) -> Void) {
        guard project.segments.indices.contains(index) else { return }
        // Coalesced by segment: typing in the script field is one edit, not one per keystroke.
        record("editor.change.segment", symbol: "pencil", coalescing: "segment-\(index)")
        change(&project.segments[index])
        project.updatedAt = .now
    }

    public func updatePlayback(at index: Int, _ change: (inout ClipPlayback) -> Void) {
        guard project.segments.indices.contains(index) else { return }
        record("editor.change.playback", symbol: "gauge.with.dots.needle.67percent")
        change(&project.segments[index].playback)
        let speed = project.segments[index].playback.speed
        project.segments[index].playback.speed = min(max(speed, 0.25), 4)
        if let freeze = project.segments[index].playback.freeze {
            project.segments[index].playback.freeze = MediaTime(seconds: min(max(freeze.seconds, 0.2), 30))
        }
        project.updatedAt = .now
        playhead = min(playhead, duration)
    }

    /// Switches which attempt at a segment is the one in the video.
    ///
    /// Captions go with it. They describe the old take's speech and keeping them would leave the
    /// video saying one thing and the words on screen saying another.
    public func selectTake(_ id: Take.ID, at index: Int) {
        guard project.segments.indices.contains(index) else { return }
        record("editor.change.take", symbol: "film.stack")
        try? project.selectTake(id, inSegment: project.segments[index].id)
    }

    public func updateCaption(_ id: CaptionCue.ID, at index: Int, _ change: (inout CaptionCue) -> Void) {
        guard project.segments.indices.contains(index),
              let cue = project.segments[index].captions.firstIndex(where: { $0.id == id })
        else { return }
        record("editor.change.caption", symbol: "text.bubble", coalescing: "caption-\(id)")
        change(&project.segments[index].captions[cue])
        // Marked by hand, so a later transcription knows not to overwrite it.
        project.segments[index].captions[cue].isUserEdited = true
        project.updatedAt = .now
    }

    /// Seeks to where a segment begins. What the inspector's timing rows do when tapped, so a
    /// number on screen can always be checked against the picture.
    public func seekToStart(of index: Int) {
        seek(to: start(at: index))
    }
}
