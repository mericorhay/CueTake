import Domain
import Foundation

/// Tools applied from one moment to another: adding them, moving and stretching them, removing them.
///
/// Every tool that used to be "this clip or every clip" is placed on the timeline instead — a
/// background from 0:04 to 0:09, a speed-up for three seconds in the middle of a clip — and shows
/// up in a lane of its own under the clips, where it can be seen, grabbed and changed later.
extension EditorModel {
    /// The effect being edited.
    public var selectedEffectValue: TimelineEffect? {
        selectedEffect.flatMap { id in project.effects.first { $0.id == id } }
    }

    public func select(effect id: TimelineEffect.ID?) {
        selectedEffect = id
        if id != nil {
            inspectedSegment = nil
            selectedAudio = nil
            selectedOverlay = nil
        }
    }

    /// Where a clip sits on the finished video.
    public func timelineRange(ofSegmentAt index: Int) -> ClosedRange<Double> {
        guard project.segments.indices.contains(index) else { return 0...0 }
        let start = start(at: index)
        return start...(start + project.segments[index].barWeight)
    }

    /// The background effect under the playhead, top one first.
    public var backgroundAtPlayhead: TimelineEffect? {
        project.effects.last { $0.background != nil && $0.start.seconds <= playhead + 0.001 && playhead < $0.end - 0.001 }
    }

    /// Lays a background over a stretch of the video and selects it.
    @discardableResult
    public func addBackground(_ settings: BackgroundSettings, from: Double, to: Double) -> TimelineEffect.ID {
        record("editor.change.background", symbol: "person.crop.rectangle")
        failedBackgrounds.removeAll()
        let start = min(max(0, from), max(0, duration - TimelineEffect.minimumLength))
        let end = min(max(to, start + TimelineEffect.minimumLength), max(duration, start + TimelineEffect.minimumLength))
        let effect = TimelineEffect(
            start: MediaTime(seconds: start),
            duration: MediaTime(seconds: end - start),
            kind: .background(settings)
        )
        project.effects.append(effect)
        project.updatedAt = .now
        pulse(.speed)
        select(effect: effect.id)
        return effect.id
    }

    /// Every effect edit passes through here: one place for history, limits and `updatedAt`.
    public func updateEffect(_ id: TimelineEffect.ID, coalescing key: String = "effect", _ change: (inout TimelineEffect) -> Void) {
        guard let index = project.effects.firstIndex(where: { $0.id == id }) else { return }
        record("editor.change.effect", symbol: "slider.horizontal.3", coalescing: "\(key)-\(id)")
        var effect = project.effects[index]
        change(&effect)
        let length = max(TimelineEffect.minimumLength, effect.duration.seconds)
        let start = min(max(0, effect.start.seconds), max(0, timelineDuration - TimelineEffect.minimumLength))
        effect.start = MediaTime(seconds: start)
        effect.duration = MediaTime(seconds: min(length, max(TimelineEffect.minimumLength, timelineDuration - start)))
        if effect.background != project.effects[index].background { failedBackgrounds.removeAll() }
        project.effects[index] = effect
        project.updatedAt = .now
    }

    public func updateBackground(_ id: TimelineEffect.ID, coalescing key: String = "look", _ change: (inout BackgroundSettings) -> Void) {
        updateEffect(id, coalescing: key) { effect in
            guard var settings = effect.background else { return }
            change(&settings)
            settings.strength = min(max(settings.strength, 0), 1)
            settings.feather = min(max(settings.feather, 0), 1)
            effect.kind = .background(settings)
        }
    }

    /// Moves one edge of an effect, keeping the other where it is.
    public func setEffectEdge(_ id: TimelineEffect.ID, start: Double? = nil, end: Double? = nil, coalescing key: String = "edge") {
        guard let effect = project.effects.first(where: { $0.id == id }) else { return }
        let oldEnd = effect.end
        updateEffect(id, coalescing: key) {
            if let start {
                let clamped = min(max(0, start), oldEnd - TimelineEffect.minimumLength)
                $0.start = MediaTime(seconds: clamped)
                $0.duration = MediaTime(seconds: oldEnd - clamped)
            }
            if let end {
                let clamped = max(end, $0.start.seconds + TimelineEffect.minimumLength)
                $0.duration = MediaTime(seconds: clamped - $0.start.seconds)
            }
        }
    }

    public func removeEffect(_ id: TimelineEffect.ID) {
        guard let index = project.effects.firstIndex(where: { $0.id == id }) else { return }
        record("editor.change.effectRemoved", symbol: "trash")
        project.effects.remove(at: index)
        if selectedEffect == id { selectedEffect = nil }
        project.updatedAt = .now
    }

    // MARK: - Playback over a stretch

    /// Changes speed, reverse or freeze for part of a clip.
    ///
    /// Speed belongs to footage, so a stretch in the middle of a clip becomes a clip of its own —
    /// split at both ends, the change made to the middle — the way every phone editor does it, as
    /// one undo step. The whole clip, a frozen clip or a reversed one is changed as it is: a
    /// reversed clip's playhead does not map to a place in its footage, so it is never cut.
    ///
    /// - Parameter range: seconds into the clip, on the finished video. Nil for the whole clip.
    public func updatePlayback(at index: Int, range: ClosedRange<Double>?, _ change: (inout ClipPlayback) -> Void) {
        guard project.segments.indices.contains(index) else { return }
        let segment = project.segments[index]
        let length = segment.barWeight
        guard let range,
              segment.playback.freeze == nil,
              range.lowerBound > 0.15 || length - range.upperBound > 0.15,
              range.upperBound - range.lowerBound > 0.2
        else {
            updatePlayback(at: index, change)
            return
        }

        let before = project
        let clipStart = start(at: index)
        let returnTo = playhead
        beginBatch()
        var target = index
        if length - range.upperBound > 0.15 {
            seek(to: clipStart + range.upperBound)
            splitAtPlayhead(snapToWords: false)
        }
        if range.lowerBound > 0.15 {
            seek(to: clipStart + range.lowerBound)
            splitAtPlayhead(snapToWords: false)
            target = index + 1
        }
        updatePlayback(at: target, change)
        endBatch(startingFrom: before, label: "editor.change.playbackRange", symbol: "gauge.with.dots.needle.67percent")
        inspectedSegment = project.segments.indices.contains(target) ? project.segments[target].id : inspectedSegment
        seek(to: min(returnTo, duration))
    }

    // MARK: - Cutting at the playhead

    public func canSplitEffect(_ id: TimelineEffect.ID) -> Bool {
        guard let effect = project.effects.first(where: { $0.id == id }) else { return false }
        return playhead - effect.start.seconds > TimelineEffect.minimumLength && effect.end - playhead > TimelineEffect.minimumLength
    }

    /// Cuts an effect in two at the playhead, so each half can be moved, stretched or changed.
    public func splitEffect(_ id: TimelineEffect.ID) {
        guard canSplitEffect(id), let index = project.effects.firstIndex(where: { $0.id == id }) else { return }
        record("editor.change.split", symbol: "scissors")
        let effect = project.effects[index]
        var left = effect
        left.duration = MediaTime(seconds: playhead - effect.start.seconds)
        let right = TimelineEffect(start: MediaTime(seconds: playhead), duration: MediaTime(seconds: effect.end - playhead), kind: effect.kind)
        project.effects[index] = left
        project.effects.insert(right, at: index + 1)
        project.updatedAt = .now
        select(effect: right.id)
    }

    public func canSplitOverlay(_ id: Overlay.ID) -> Bool {
        guard let overlay = project.overlays.first(where: { $0.id == id }) else { return false }
        let end = overlay.start.seconds + overlay.duration.seconds
        return playhead - overlay.start.seconds > Overlay.shortest && end - playhead > Overlay.shortest
    }

    /// Cuts a text or picture in two at the playhead.
    public func splitOverlay(_ id: Overlay.ID) {
        guard canSplitOverlay(id), let index = project.overlays.firstIndex(where: { $0.id == id }) else { return }
        record("editor.change.split", symbol: "scissors")
        let overlay = project.overlays[index]
        let end = overlay.start.seconds + overlay.duration.seconds
        var left = overlay
        left.duration = MediaTime(seconds: playhead - overlay.start.seconds)
        var right = Overlay(content: overlay.content, start: MediaTime(seconds: playhead))
        right.duration = MediaTime(seconds: end - playhead)
        right.transform = overlay.transform
        right.animation = overlay.animation
        project.overlays[index] = left
        project.overlays.insert(right, at: index + 1)
        project.updatedAt = .now
        select(overlay: right.id)
    }
}
