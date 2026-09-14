import AVFoundation
import Domain
import Foundation

/// Builds the finished video out of the timeline, and writes it to a file.
///
/// Composition rather than re-encoding per clip: `AVMutableComposition` references the source files
/// and describes what to play from where, so assembling a video is nearly free and only the final
/// write costs anything. It is also why a retake is cheap — one segment's range changes and the
/// composition is rebuilt from scratch in milliseconds.
public struct VideoComposer: Sendable {
    public init() {}

    public enum ComposeError: Error, Hashable, Sendable {
        case nothingToCompose
        case missingMedia(Recording.ID)
        case noVideoTrack(Recording.ID)
        case exportFailed(String)
    }

    /// A composition plus the instructions that say how each clip is framed inside it.
    public struct Assembled: @unchecked Sendable {
        public var composition: AVMutableComposition
        /// Travels with the composition everywhere. The export needs it, and so does the preview,
        /// or the editor shows something the exported file will not match.
        public var videoComposition: AVMutableVideoComposition
        /// Levels, fades and ducking. Nil when the project has no audio clips, in which case the
        /// voice plays at the level it was recorded at, which is right.
        public var audioMix: AVMutableAudioMix?
        /// Carried so the writer can choose a codec and a bitrate that match what was asked for
        /// instead of guessing from the pixels it happens to see.
        public var format: VideoFormat
        /// The cues, already placed in finished-video time, and how they should look. Burned in at
        /// write time rather than here: Core Animation's layer tool is an export facility and the
        /// preview player ignores it, so the editor draws its own.
        public var captions: [PlacedCue]
        public var captionStyle: CaptionStyle
        public var localeIdentifier: String
        /// Pictures and text over the video, burned in with the captions.
        public var overlays: [Overlay] = []
        public var mediaDirectory: URL?
    }

    /// Assembles the project's selected takes, in segment order.
    ///
    /// - Parameter mediaDirectory: where `Recording.relativePath` resolves against. The document
    ///   stores paths relative to the project because the container path changes between installs.
    /// - Parameter renderBackgrounds: render any missing background replacement first (export).
    ///   The preview passes false and plays those clips as shot until the editor's own render is done.
    /// - Parameter liveFilters: where the compositor reads filters from; the editor passes its own
    ///   so a slider changes the picture without a rebuild. Nil reads them from `project`.
    public func compose(
        project: Project,
        mediaDirectory: URL,
        renderBackgrounds: Bool = true,
        liveFilters: LiveFilters? = nil
    ) async throws -> Assembled {
        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else { throw ComposeError.nothingToCompose }

        let recordings = Dictionary(uniqueKeysWithValues: project.recordings.map { ($0.id, $0) })
        // Cleaned voice per recording, looked up once: several segments usually share one file.
        let cleaner = VoiceCleaner()
        var cleanedVoice: [Recording.ID: AVAssetTrack] = [:]
        let renderSize = CGSize(
            width: CGFloat(project.format.renderSize.width),
            height: CGFloat(project.format.renderSize.height)
        )

        var cursor = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []
        /// The voice's level from each moment on, for sound effects that change it.
        var voiceLevels: [(time: CMTime, gain: Float)] = []
        var effectTracks: [String: AVAssetTrack] = [:]

        for (segmentIndex, segment) in project.segments.enumerated() {
            guard let take = segment.selectedTake,
                  let recording = recordings[take.recordingID]
            else { continue }

            let playback = segment.playback
            var url = mediaDirectory.appending(
                path: (recording.relativePath as NSString).lastPathComponent,
                directoryHint: .notDirectory
            )
            var sourceStart = CMTime(seconds: take.sourceRange.start.seconds, preferredTimescale: 600)
            let sourceLength = CMTime(seconds: take.sourceRange.duration.seconds, preferredTimescale: 600)
            // The recording itself, for the sound: a clip whose picture is a processed copy (reversed,
            // background replaced) still speaks with the voice it was recorded with.
            let original = AVURLAsset(url: url)
            let originalStart = sourceStart
            var pictureReplaced = false

            // A composition can scale time but it cannot run it backwards, so a reversed clip is a
            // different file — written once and cached — and so is its sound, written backwards
            // beside it (see `AudioReverser`).
            var reversedAudio: URL?
            if playback.isReversed, playback.freeze == nil {
                let key = "\(take.id.uuidString)-\(Int(take.sourceRange.start.seconds * 1000))-\(Int(take.sourceRange.duration.seconds * 1000))"
                reversedAudio = await AudioReverser.reversedAudio(
                    for: recording,
                    range: CMTimeRange(start: sourceStart, duration: sourceLength),
                    key: key,
                    in: mediaDirectory
                )
                if let reversed = await VideoReverser().reversedClip(
                    source: url,
                    range: CMTimeRange(start: sourceStart, duration: sourceLength),
                    key: key,
                    in: mediaDirectory
                ) {
                    url = reversed
                    sourceStart = .zero
                    pictureReplaced = true
                } else {
                    // The picture could not be reversed, so it plays forwards; its sound must too.
                    reversedAudio = nil
                }
            }

            let asset = AVURLAsset(url: url)

            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
                throw ComposeError.noVideoTrack(recording.id)
            }

            // Clamped to what the file actually contains. Trimming a segment longer than its
            // recording asked AVFoundation for time that does not exist, which it answers by
            // trapping — that was the crash on export.
            let assetDuration = try await asset.load(.duration)
            guard sourceStart < assetDuration else { continue }
            var range = CMTimeRange(
                start: sourceStart,
                duration: min(sourceLength, assetDuration - sourceStart)
            )

            // A freeze is one frame held open. That is the whole trick: insert a single frame and
            // stretch it. No still image, no second asset, and the frame held is the one the clip
            // starts on, which is the one the user was looking at when they froze it.
            if playback.freeze != nil {
                let oneFrame = CMTime(
                    value: 1,
                    timescale: CMTimeScale(max(24, recording.format.frameRate))
                )
                range = CMTimeRange(start: sourceStart, duration: min(oneFrame, range.duration))
            }
            guard range.duration.seconds > 0.001 else { continue }
            // Where the sound for this range is: the recording's own timeline, unless the sound too
            // was written to a file of its own that starts at zero (reversed).
            let soundStart = reversedAudio != nil ? CMTime.zero : originalStart
            let soundRange = CMTimeRange(start: soundStart, duration: range.duration)

            // The picture, stretch by stretch: a background effect can cover part of a clip, so the
            // clip is laid in as pieces, each from the footage as shot or from its processed copy.
            // Speed and freeze are the same operation to a composition — take the range just
            // inserted and say how long it should last instead — applied to each piece.
            let natural = try await sourceVideo.load(.naturalSize)
            let preferred = try await sourceVideo.load(.preferredTransform)
            let speed = min(max(playback.speed, 0.1), 8)
            var processedTracks: [String: (track: AVAssetTrack, duration: CMTime, natural: CGSize, preferred: CGAffineTransform)] = [:]
            var pieceCursor = cursor

            for stretch in project.stretches(ofSegmentAt: segmentIndex) {
                var pieceRange: CMTimeRange
                if playback.freeze != nil {
                    pieceRange = range
                } else {
                    let from = CMTime(seconds: stretch.from * speed, preferredTimescale: 600)
                    let to = stretch.to >= segment.barWeight - 0.001
                        ? range.duration
                        : CMTimeMinimum(range.duration, CMTime(seconds: stretch.to * speed, preferredTimescale: 600))
                    guard to > from else { continue }
                    pieceRange = CMTimeRange(start: range.start + from, duration: to - from)
                }

                var track = sourceVideo
                var trackNatural = natural
                var trackPreferred = preferred
                if let settings = stretch.background {
                    let destination = BackgroundRemover.cachedURL(take: take, reversed: pictureReplaced, settings: settings, in: mediaDirectory)
                    if processedTracks[settings.token] == nil {
                        var processed: URL?
                        if BackgroundRemover.isUsableCache(destination) {
                            processed = destination
                        } else if renderBackgrounds {
                            processed = await BackgroundRemover().render(
                                source: url,
                                range: CMTimeRange(start: sourceStart, duration: sourceLength),
                                settings: settings,
                                destination: destination
                            )
                        }
                        let copy = processed.map { AVURLAsset(url: $0) }
                        if let copy,
                           let copyTrack = try? await copy.loadTracks(withMediaType: .video).first,
                           let copyDuration = try? await copy.load(.duration),
                           let copyNatural = try? await copyTrack.load(.naturalSize),
                           let copyPreferred = try? await copyTrack.load(.preferredTransform) {
                            processedTracks[settings.token] = (copyTrack, copyDuration, copyNatural, copyPreferred)
                        }
                    }
                    // The processed copy starts where the take starts, so the same offset
                    // addresses it. Played as shot until it exists.
                    if let copy = processedTracks[settings.token] {
                        let start = pieceRange.start - sourceStart
                        let length = CMTimeMinimum(pieceRange.duration, copy.duration - start)
                        if start < copy.duration, length.seconds > 0.001 {
                            pieceRange = CMTimeRange(start: start, duration: length)
                            track = copy.track
                            trackNatural = copy.natural
                            trackPreferred = copy.preferred
                        }
                    }
                }

                try videoTrack.insertTimeRange(pieceRange, of: track, at: pieceCursor)
                let pieceTarget = CMTime(
                    seconds: playback.freeze != nil
                        ? playback.timelineSeconds(forSource: 0)
                        : pieceRange.duration.seconds / speed,
                    preferredTimescale: 600
                )
                if abs(pieceTarget.seconds - pieceRange.duration.seconds) > 0.001 {
                    videoTrack.scaleTimeRange(CMTimeRange(start: pieceCursor, duration: pieceRange.duration), toDuration: pieceTarget)
                }

                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
                let pieceTimelineStart = (pieceCursor - cursor).seconds
                let pieceTimelineEnd = pieceTimelineStart + pieceTarget.seconds
                if segment.smartReframe.isEmpty {
                    // Keep the long-standing static instruction for ordinary clips. A ramp with
                    // identical endpoints is needlessly rejected by some iOS AVFoundation builds
                    // when the source has been time-scaled.
                    let geometry = VideoFrameGeometry(natural: trackNatural, preferred: trackPreferred, placement: project.mainVideoPlacement, render: renderSize)
                    layer.setTransform(geometry.transform, at: pieceCursor)
                    layer.setCropRectangle(geometry.crop, at: pieceCursor)
                }
                let internalTimes = segment.smartReframe.compactMap { frame -> Double? in
                    let sourceOffset = playback.isReversed
                        ? max(0, take.sourceRange.duration.seconds - frame.time)
                        : frame.time
                    let time = playback.timelineSeconds(forSource: sourceOffset)
                    return time > pieceTimelineStart + 0.001 && time < pieceTimelineEnd - 0.001 ? time : nil
                }
                let geometryTimes = ([pieceTimelineStart] + internalTimes + [pieceTimelineEnd]).sorted()
                for (from, to) in zip(geometryTimes, geometryTimes.dropFirst()) where !segment.smartReframe.isEmpty && to > from {
                    let firstPlacement = Self.mainPlacement(
                        project.mainVideoPlacement,
                        focuses: segment.smartReframe,
                        sourceDuration: take.sourceRange.duration.seconds,
                        playback: playback,
                        timelineTime: from
                    )
                    let lastPlacement = Self.mainPlacement(
                        project.mainVideoPlacement,
                        focuses: segment.smartReframe,
                        sourceDuration: take.sourceRange.duration.seconds,
                        playback: playback,
                        timelineTime: to
                    )
                    let first = VideoFrameGeometry(natural: trackNatural, preferred: trackPreferred, placement: firstPlacement, render: renderSize)
                    let last = VideoFrameGeometry(natural: trackNatural, preferred: trackPreferred, placement: lastPlacement, render: renderSize)
                    let ramp = CMTimeRange(
                        start: cursor + CMTime(seconds: from, preferredTimescale: 600),
                        end: cursor + CMTime(seconds: to, preferredTimescale: 600)
                    )
                    layer.setTransformRamp(fromStart: first.transform, toEnd: last.transform, timeRange: ramp)
                    layer.setCropRectangleRamp(fromStartCropRectangle: first.crop, toEndCropRectangle: last.crop, timeRange: ramp)
                }
                layer.setOpacity(Float(project.mainVideoPlacement.bounded.opacity), at: pieceCursor)
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: pieceCursor, duration: pieceTarget)
                instruction.layerInstructions = [layer]
                instructions.append(instruction)

                pieceCursor = pieceCursor + pieceTarget
            }
            let target = pieceCursor - cursor
            guard target > .zero else { continue }

            // Audio is optional on purpose: a clip with no audio track is a legitimate thing to
            // put in a video, and refusing the whole export over it would be absurd. A frozen
            // frame is asked for silence — a held picture playing a second of sound under it is
            // the one thing a freeze must never do.
            var hasAudio = false
            let sounds = playback.freeze == nil && !playback.isReversed ? project.soundStretches(ofSegmentAt: segmentIndex) : []
            if sounds.contains(where: { $0.sound != nil }) {
                // Sound effects over part of the clip: the voice is laid in stretch by stretch, each
                // from the voice as recorded (or repaired) or from its effect file, all of them on
                // the recording's own clock.
                var voiceFile: URL?
                var baseTrack: AVAssetTrack?
                if project.voiceEffects.isActive,
                   let url = await cleaner.cleanedAudio(for: recording, effects: project.voiceEffects, in: mediaDirectory) {
                    voiceFile = url
                    baseTrack = try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first
                }
                if baseTrack == nil {
                    baseTrack = try? await original.loadTracks(withMediaType: .audio).first
                    voiceFile = await VoiceCleaner.extractedVoice(for: recording, in: mediaDirectory)
                }
                let voiceToken = project.voiceEffects.isActive ? AudioEffectRenderer.token(for: project.voiceEffects) : "raw"
                var audioCursor = cursor
                for stretch in sounds {
                    let from = CMTime(seconds: stretch.from * speed, preferredTimescale: 600)
                    let to = stretch.to >= segment.barWeight - 0.001
                        ? range.duration
                        : CMTimeMinimum(range.duration, CMTime(seconds: stretch.to * speed, preferredTimescale: 600))
                    guard to > from else { continue }
                    let piece = CMTimeRange(start: originalStart + from, duration: to - from)
                    let pieceTarget = CMTime(seconds: piece.duration.seconds / speed, preferredTimescale: 600)

                    var track = baseTrack
                    if let settings = stretch.sound, settings.needsRender, let voiceFile {
                        let key = "\(recording.id)-\(voiceToken)-\(settings.token)"
                        if effectTracks[key] == nil,
                           let url = await SoundEffectRenderer().rendered(settings, recording: recording, voice: voiceFile, voiceToken: voiceToken, in: mediaDirectory),
                           let rendered = try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first {
                            effectTracks[key] = rendered
                        }
                        track = effectTracks[key] ?? baseTrack
                    }
                    if let track, (try? audioTrack.insertTimeRange(piece, of: track, at: audioCursor)) != nil {
                        hasAudio = true
                        if abs(pieceTarget.seconds - piece.duration.seconds) > 0.001 {
                            audioTrack.scaleTimeRange(CMTimeRange(start: audioCursor, duration: piece.duration), toDuration: pieceTarget)
                        }
                    }
                    voiceLevels.append((audioCursor, Float(stretch.sound?.gain ?? 1)))
                    audioCursor = audioCursor + pieceTarget
                }
                cursor = cursor + target
                continue
            }
            voiceLevels.append((cursor, 1))
            if playback.freeze == nil, !playback.isReversed, project.voiceEffects.isActive {
                if cleanedVoice[recording.id] == nil,
                   let url = await cleaner.cleanedAudio(for: recording, effects: project.voiceEffects, in: mediaDirectory),
                   let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first {
                    cleanedVoice[recording.id] = track
                }
                // Same timeline as the recording, so the take's own range addresses it directly.
                if let cleaned = cleanedVoice[recording.id] {
                    hasAudio = (try? audioTrack.insertTimeRange(soundRange, of: cleaned, at: cursor)) != nil
                }
            }
            // A reversed clip's sound, written backwards to its own file. Starts at zero like the
            // reversed picture, so the same range addresses both.
            if !hasAudio, let reversedAudio,
               let track = try? await AVURLAsset(url: reversedAudio).loadTracks(withMediaType: .audio).first {
                hasAudio = (try? audioTrack.insertTimeRange(soundRange, of: track, at: cursor)) != nil
            }
            if !hasAudio, playback.freeze == nil, !playback.isReversed,
               let sourceAudio = try await original.loadTracks(withMediaType: .audio).first {
                hasAudio = (try? audioTrack.insertTimeRange(soundRange, of: sourceAudio, at: cursor)) != nil
            }
            // The voice lasts exactly as long as the pictures laid above it.
            if hasAudio, abs(target.seconds - range.duration.seconds) > 0.001 {
                audioTrack.scaleTimeRange(CMTimeRange(start: cursor, duration: range.duration), toDuration: target)
            }

            cursor = cursor + target
        }

        guard !instructions.isEmpty || !project.videoLayers.isEmpty else { throw ComposeError.nothingToCompose }

        let audioMix = await mix(
            project: project,
            mediaDirectory: mediaDirectory,
            into: composition,
            voiceTrack: audioTrack,
            voiceLevels: voiceLevels
        )
        let layered = try await addVideoLayers(project: project, directory: mediaDirectory, composition: composition, base: instructions, render: renderSize)
        let combinedMix = audioMix ?? AVMutableAudioMix()
        combinedMix.inputParameters += layered.audio

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(max(24, project.format.frameRate))
        )
        videoComposition.instructions = layered.instructions
        // Filters need a compositor of their own. Only then: every other project keeps the
        // system's, which is also the only one the export's caption tool works with.
        if project.effects.contains(where: { $0.filter != nil }) {
            let filters = liveFilters ?? LiveFilters(project.effects)
            videoComposition.customVideoCompositorClass = FilterCompositor.self
            videoComposition.instructions = layered.instructions.map { FilterInstruction($0, filters: filters) }
        }

        return Assembled(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: combinedMix,
            format: project.format,
            captions: project.captionCues,
            captionStyle: project.captionStyle,
            localeIdentifier: project.localeIdentifier,
            overlays: project.overlays,
            mediaDirectory: mediaDirectory
        )
    }

    /// The face point at a primary clip's timeline moment. Focus uses source time so changing speed
    /// keeps it attached to the same frame; reverse simply reads the source track backwards.
    private static func mainPlacement(
        _ base: VideoPlacement,
        focuses: [VideoFocusKeyframe],
        sourceDuration: Double,
        playback: ClipPlayback,
        timelineTime: Double
    ) -> VideoPlacement {
        guard !focuses.isEmpty else { return base }
        let sourceTime = playback.isReversed
            ? max(0, sourceDuration - playback.sourceSeconds(forTimeline: timelineTime))
            : playback.sourceSeconds(forTimeline: timelineTime)
        let ordered = focuses.sorted { $0.time < $1.time }
        var previous = ordered[0]
        var focus = previous
        for frame in ordered.dropFirst() {
            if sourceTime < frame.time {
                let fraction = min(max((sourceTime - previous.time) / max(0.001, frame.time - previous.time), 0), 1)
                focus = VideoFocusKeyframe(
                    time: sourceTime,
                    x: previous.x + (frame.x - previous.x) * fraction,
                    y: previous.y + (frame.y - previous.y) * fraction
                )
                break
            }
            previous = frame
            focus = frame
        }
        var placement = base
        placement.fillsFrame = true
        placement.focusX = focus.x
        placement.focusY = focus.y
        return placement.bounded
    }

    // MARK: - Audio

    /// Lays the music, voiceovers and effects into the composition and builds the mix.
    ///
    /// One composition track per clip, rather than one shared track: two clips that overlap in
    /// time cannot live on the same track, and the moment someone puts a sting over a bed of music
    /// a single track silently drops one of them. A track per clip is also what makes per-clip
    /// levels possible at all — `AVAudioMix` addresses tracks, not ranges.
    private func mix(
        project: Project,
        mediaDirectory: URL,
        into composition: AVMutableComposition,
        voiceTrack: AVMutableCompositionTrack,
        voiceLevels: [(time: CMTime, gain: Float)] = []
    ) async -> AVMutableAudioMix? {

        let renderer = AudioEffectRenderer()
        let spoken = project.spokenRanges
        var parameters: [AVMutableAudioMixInputParameters] = []

        for clip in project.audio {
            guard let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            let url = await renderer.source(for: clip, in: mediaDirectory)
            let asset = AVURLAsset(url: url)
            guard let source = try? await asset.loadTracks(withMediaType: .audio).first,
                  let assetDuration = try? await asset.load(.duration)
            else { continue }

            let start = CMTime(seconds: clip.sourceRange.start.seconds, preferredTimescale: 600)
            guard start < assetDuration else { continue }
            let wanted = CMTime(seconds: clip.sourceRange.duration.seconds, preferredTimescale: 600)
            let range = CMTimeRange(start: start, duration: min(wanted, assetDuration - start))
            guard range.duration.seconds > 0.01 else { continue }

            let at = CMTime(seconds: clip.start.seconds, preferredTimescale: 600)
            guard (try? track.insertTimeRange(range, of: source, at: at)) != nil else { continue }

            // Speed. Scaling the inserted range rather than resampling the file: the source is
            // untouched, the change is one number, and it can be undone by typing 1. Pitch is
            // preserved at the writer, which is the difference between a faster voice and a
            // cartoon one.
            if abs(clip.speed - 1) > 0.01 {
                let scaled = CMTime(seconds: clip.timelineDuration.seconds, preferredTimescale: 600)
                track.scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: scaled)
            }

            let input = AVMutableAudioMixInputParameters(track: track)
            // Ramps are placed on whole ticks, each starting no earlier than the last one ended.
            // AVFoundation raises an Objective-C exception for overlapping ramps — which Swift
            // cannot catch, so it is a crash — and converting each start and duration from seconds
            // separately can round two neighbours into overlapping by a single 1/600 s tick.
            var previousEnd = CMTime.zero
            for ramp in AudioEnvelope.ramps(for: clip, spoken: spoken) {
                let start = CMTimeMaximum(
                    CMTime(seconds: clip.start.seconds + ramp.start, preferredTimescale: 600),
                    previousEnd
                )
                let end = CMTime(seconds: clip.start.seconds + ramp.start + ramp.duration, preferredTimescale: 600)
                guard end > start else { continue }
                input.setVolumeRamp(
                    fromStartVolume: Float(ramp.from),
                    toEndVolume: Float(ramp.to),
                    timeRange: CMTimeRange(start: start, end: end)
                )
                previousEnd = end
            }
            parameters.append(input)
        }


        // The voice is named explicitly at full volume. Without an entry of its own it inherits
        // whatever the mix decides, and a track nobody described is a track that can surprise you.
        let voice = AVMutableAudioMixInputParameters(track: voiceTrack)
        let mainVolume = Float(min(max(project.mainVideoVolume, 0), 1))
        voice.setVolume(mainVolume, at: .zero)
        // Sound effects raise or lower the voice over their stretch.
        var lastTime = CMTime.negativeInfinity
        var lastGain: Float = 1
        for level in voiceLevels.sorted(by: { $0.time < $1.time }) where level.time > lastTime && level.gain != lastGain {
            voice.setVolume(mainVolume * level.gain, at: level.time)
            lastTime = level.time
            lastGain = level.gain
        }
        parameters.append(voice)

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        return audioMix
    }

    /// Places one clip inside the render frame.
    ///
    /// Fit rather than fill. Filling a landscape clip into a vertical frame throws away three
    /// quarters of the width, which on a talking-head shot means throwing away the head. Bars are
    /// honest about what the footage is; a crop silently destroys the take. Per-clip crop and zoom
    /// belong to the user, not to an exporter acting behind their back.
    ///
    /// `preferredTransform` is applied first — it is what makes a portrait clip portrait, and
    /// ignoring it is why footage comes back sideways — and its origin is normalised, because a
    /// rotation leaves the content sitting in negative space.
    static func fit(natural: CGSize, preferred: CGAffineTransform, into render: CGSize) -> CGAffineTransform {
        let rotated = CGRect(origin: .zero, size: natural).applying(preferred)
        let display = CGSize(width: abs(rotated.width), height: abs(rotated.height))
        guard display.width > 0, display.height > 0, render.width > 0, render.height > 0 else {
            return preferred
        }

        let scale = min(render.width / display.width, render.height / display.height)
        let scaled = CGSize(width: display.width * scale, height: display.height * scale)

        return preferred
            .concatenating(CGAffineTransform(translationX: -rotated.origin.x, y: -rotated.origin.y))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(
                CGAffineTransform(
                    translationX: (render.width - scaled.width) / 2,
                    y: (render.height - scaled.height) / 2
                )
            )
    }

    /// Writes the assembled video to a file, reporting real progress as it goes.
    ///
    /// - Parameter onProgress: called on the main actor with 0...1. The export screen used to
    ///   advance on a timer, which finished before the file did on anything long.
    public func write(
        _ assembled: Assembled,
        to destination: URL,
        onProgress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        // The caption tool only works with the system's compositor. A filtered video is written
        // once with its filters, then captions and overlays are laid on that file.
        if assembled.videoComposition.customVideoCompositorClass != nil {
            let filtered = FileManager.default.temporaryDirectory
                .appending(path: "filtered-\(UUID().uuidString).mov", directoryHint: .notDirectory)
            defer { try? FileManager.default.removeItem(at: filtered) }
            try await exportFiltered(assembled, to: filtered) { value in
                await onProgress?(value * 0.6)
            }
            let asset = AVURLAsset(url: filtered)
            let composition = AVMutableComposition()
            let duration = try await asset.load(.duration)
            if let video = try await asset.loadTracks(withMediaType: .video).first,
               let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: video, at: .zero)
            }
            if let audio = try await asset.loadTracks(withMediaType: .audio).first,
               let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audio, at: .zero)
            }
            let plain = AVMutableVideoComposition()
            plain.renderSize = assembled.videoComposition.renderSize
            plain.frameDuration = assembled.videoComposition.frameDuration
            if let videoTrack = composition.tracks(withMediaType: .video).first {
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
                instruction.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)]
                plain.instructions = [instruction]
            }
            var second = assembled
            second.composition = composition
            second.videoComposition = plain
            second.audioMix = nil
            return try await write(second, to: destination) { value in
                onProgress?(0.6 + value * 0.4)
            }
        }

        // A passthrough preset ignores the video composition and hands back the source frames,
        // sideways and unscaled. The render size lives in the composition, so the preset only has
        // to be one that re-encodes.
        // Above 1080p the codec is not a preference. H.264 has no level that carries 8K, and at
        // 4K it costs roughly twice the file for the same picture.
        let preset = assembled.format.resolution.prefersHEVC
            ? AVAssetExportPresetHEVCHighestQuality
            : AVAssetExportPresetHighestQuality

        guard let session = AVAssetExportSession(asset: assembled.composition, presetName: preset)
            ?? AVAssetExportSession(asset: assembled.composition, presetName: AVAssetExportPresetHighestQuality)
        else {
            throw ComposeError.exportFailed("no export session")
        }
        // Captions go on here, at the last moment, because the same video composition is handed
        // to the preview player and the animation tool would mean nothing to it.
        let renderSize = assembled.videoComposition.renderSize
        let overlayLayers = assembled.mediaDirectory.map {
            OverlayRenderer.layers(for: assembled.overlays, renderSize: renderSize, mediaDirectory: $0)
        } ?? []
        assembled.videoComposition.animationTool = CaptionRenderer.tool(
            cues: assembled.captions,
            style: assembled.captionStyle,
            locale: Locale(identifier: assembled.localeIdentifier),
            renderSize: renderSize,
            underlays: overlayLayers
        )
        session.videoComposition = assembled.videoComposition
        session.audioMix = assembled.audioMix
        // Spectral: the frequency-domain stretch. It is the expensive one and the only one that
        // leaves a sped-up voice sounding like the same person.
        // Spectral: the frequency-domain stretch. It is the expensive one and the only one that
        // leaves a slowed or sped-up voice sounding like the same person.
        session.audioTimePitchAlgorithm = .spectral

        // `AVAssetExportSession` is not Sendable, so the polling task cannot hold it. Reading one
        // atomic float from another thread is safe in a way the type system has no way to express,
        // and this box says so once rather than scattering the claim.
        let reader = ProgressReader(session: session)
        let reporter: Task<Void, Never>? = onProgress.map { report in
            Task {
                while !Task.isCancelled {
                    let value = reader.value
                    await report(value)
                    if value >= 0.999 { return }
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
        }
        defer { reporter?.cancel() }

        let partial = destination.deletingLastPathComponent().appending(
            path: "partial-\(UUID().uuidString)-\(destination.lastPathComponent)",
            directoryHint: .notDirectory
        )
        defer { try? FileManager.default.removeItem(at: partial) }
        do {
            try await session.export(to: partial, as: .mov)
            let rendered = AVURLAsset(url: partial)
            let duration = try await rendered.load(.duration)
            let videoTracks = try await rendered.loadTracks(withMediaType: .video)
            guard duration.seconds > 0.001, !videoTracks.isEmpty
            else { throw ComposeError.exportFailed("empty output") }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            if let error = error as? ComposeError { throw error }
            throw ComposeError.exportFailed(error.localizedDescription)
        }
        return destination
    }
}

/// Reads an export session's progress from another task.
private struct ProgressReader: @unchecked Sendable {
    let session: AVAssetExportSession
    var value: Double { Double(session.progress) }
}

extension VideoComposer {
    /// The first of two passes for a filtered video: the picture through the filter compositor and
    /// the mixed sound, with no captions.
    func exportFiltered(
        _ assembled: Assembled,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        let preset = assembled.format.resolution.prefersHEVC ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: assembled.composition, presetName: preset) else {
            throw ComposeError.exportFailed("no export session")
        }
        session.videoComposition = assembled.videoComposition
        session.audioMix = assembled.audioMix
        session.audioTimePitchAlgorithm = .spectral
        let reader = ProgressReader(session: session)
        let reporter = Task {
            while !Task.isCancelled {
                let value = reader.value
                await onProgress(value)
                if value >= 0.999 { return }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        defer { reporter.cancel() }
        do {
            try await session.export(to: destination, as: .mov)
            let rendered = AVURLAsset(url: destination)
            let duration = try await rendered.load(.duration)
            let videoTracks = try await rendered.loadTracks(withMediaType: .video)
            guard duration.seconds > 0.001, !videoTracks.isEmpty
            else { throw ComposeError.exportFailed("empty filtered output") }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if let error = error as? ComposeError { throw error }
            throw ComposeError.exportFailed(error.localizedDescription)
        }
    }
}
