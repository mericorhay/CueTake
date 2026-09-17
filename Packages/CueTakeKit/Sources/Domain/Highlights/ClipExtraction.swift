import Foundation

extension Project {
    /// A new project holding one stretch of this one, vertical, ready to be a short.
    ///
    /// The clips inside the stretch are trimmed to it, with their words and captions; the look of
    /// the captions, the voice repair, the framing and the transitions between the kept clips come
    /// along. Sound, pictures and added videos pinned to the long video's clock are left behind:
    /// their moments belong to the long video.
    ///
    /// The new project points at the same recordings; the app copies or links those files into the
    /// new project's folder.
    public func extractingClip(from start: Double, to end: Double, title: String) -> Project {
        var segments: [Segment] = []
        var renamed: [Segment.ID: Segment.ID] = [:]
        var cursor = 0.0
        for segment in self.segments {
            let length = segment.barWeight
            defer { cursor += length }
            let a = max(0, start - cursor)
            let b = min(length, end - cursor)
            guard b - a >= 0.1, let take = segment.selectedTake else { continue }

            let playback = segment.playback
            let sourceLength = segment.sourceSeconds
            let first = min(max(playback.sourceSeconds(forTimeline: a), 0), sourceLength)
            let last = min(max(playback.sourceSeconds(forTimeline: b), 0), sourceLength)
            let from = playback.isReversed ? sourceLength - last : first
            let to = playback.isReversed ? sourceLength - first : last
            guard to - from >= 0.05 else { continue }

            var trimmed = Take(
                recordingID: take.recordingID,
                sourceRange: MediaTimeRange(
                    start: take.sourceRange.start + MediaTime(seconds: from),
                    duration: MediaTime(seconds: to - from)
                ),
                status: take.status
            )
            trimmed.transcript = take.transcript?.slice(from: from, to: to)

            var clip = segment.copyWithNewIdentity()
            clip.takes = [trimmed]
            clip.selectedTakeID = trimmed.id
            if let words = trimmed.transcript, !words.words.isEmpty {
                clip.script = words.text
                clip.refreshCaptions(maxWordsPerCue: captionStyle.maxWordsPerCue)
            } else {
                clip.captions = segment.captions.compactMap { cue in
                    guard cue.range.start.seconds >= from - 0.01, cue.range.end.seconds <= to + 0.01 else { return nil }
                    var moved = cue
                    moved.range = MediaTimeRange(start: MediaTime(seconds: cue.range.start.seconds - from), duration: cue.range.duration)
                    return moved
                }
            }
            renamed[segment.id] = clip.id
            segments.append(clip)
        }

        let used = Set(segments.compactMap { $0.selectedTake?.recordingID })
        // As sharp as the footage it is cut from: a short from 4K video is a 4K short.
        let sharpest = recordings
            .filter { used.contains($0.id) }
            .map(\.format.resolution)
            .max { $0.shortEdge < $1.shortEdge }
        let resolution = [format.resolution, sharpest].compactMap { $0 }.max { $0.shortEdge < $1.shortEdge } ?? format.resolution
        var clip = Project(
            title: title,
            format: VideoFormat(aspectRatio: .portrait9x16, resolution: resolution, frameRate: format.frameRate),
            localeIdentifier: localeIdentifier,
            segments: segments,
            recordings: recordings.filter { used.contains($0.id) },
            captionStyle: captionStyle,
            metadata: ["sourceProject": id.uuidString, "sourceStart": String(format: "%.2f", start), "sourceEnd": String(format: "%.2f", end)]
        )
        clip.voiceEffects = voiceEffects
        clip.mainVideoVolume = mainVideoVolume
        clip.mainVideoPlacement = mainVideoPlacement
        let lastKept = segments.last?.id
        clip.transitions = transitions.compactMap { transition in
            guard let after = renamed[transition.after], after != lastKept else { return nil }
            var moved = transition
            moved.after = after
            return moved
        }
        return clip
    }

    /// Whether the footage is a different shape from a vertical video, so a short cut from it
    /// needs the camera to follow the speaker.
    public var needsVerticalReframe: Bool {
        recordings.contains { $0.format.aspectRatio != .portrait9x16 }
    }
}
