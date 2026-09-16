import Foundation

/// One thing in a project that an edit touched: a clip, a clip's captions, the caption look, an
/// overlay, a sound, the voice repair.
///
/// The unit of "show me what changed" and of "take just that back". Coarse on purpose — a clip
/// rather than a clip's third word — because the restore has to be exact: putting back a whole
/// clip from before the edit is always a valid project, putting back half of one might not be.
public enum AITarget: Hashable, Sendable {
    case clip(UUID)
    /// The order of the clips.
    case clipOrder
    /// Every caption of one clip.
    case captions(UUID)
    case captionStyle
    case captionWindow
    case overlay(UUID)
    /// A tool laid over a stretch of the video.
    case effect(UUID)
    /// An added video playing over the main one.
    case videoLayer(UUID)
    /// Where the main video sits in the frame, and how loud it is.
    case mainVideo
    /// A recorded or imported file: which listener's words it uses.
    case recording(UUID)
    case audio(UUID)
    case voice
    case title
    /// Every transition between clips, as one.
    case transitions

    /// Clips go back before their order does: the order can only be restored among clips that exist.
    var restoreRank: Int {
        switch self {
        case .clip: 0
        case .clipOrder: 1
        default: 2
        }
    }
}

extension Project {
    /// This project with `targets` put back the way they are in `source`, everything else left alone.
    ///
    /// The same call reverts an AI change (source: the project before it) and re-applies one
    /// (source: the project after it). Something in `source` but missing here comes back at its old
    /// place; something here but not in `source` — a clip a split made, a title the AI added — goes.
    public func restoring(_ targets: [AITarget], from source: Project) -> Project {
        var result = self
        var seen = Set<AITarget>()
        let ordered = targets.filter { seen.insert($0).inserted }.sorted { $0.restoreRank < $1.restoreRank }

        for target in ordered {
            switch target {
            case .clip(let id):
                Self.restore(id, in: &result.segments, from: source.segments, keepingAtLeastOne: true)
            case .clipOrder:
                let rank = Dictionary(source.segments.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
                let known = result.segments.filter { rank[$0.id] != nil }.sorted { rank[$0.id]! < rank[$1.id]! }
                var reordered = known
                for (index, segment) in result.segments.enumerated() where rank[segment.id] == nil {
                    reordered.insert(segment, at: min(index, reordered.count))
                }
                result.segments = reordered
            case .captions(let id):
                if let old = source.segments.first(where: { $0.id == id }),
                   let now = result.segments.firstIndex(where: { $0.id == id }) {
                    result.segments[now].captions = old.captions
                }
            case .captionStyle:
                result.captionStyle = source.captionStyle
            case .captionWindow:
                result.captionWindow = source.captionWindow
            case .overlay(let id):
                Self.restore(id, in: &result.overlays, from: source.overlays)
            case .effect(let id):
                Self.restore(id, in: &result.effects, from: source.effects)
            case .videoLayer(let id):
                Self.restore(id, in: &result.videoLayers, from: source.videoLayers)
            case .mainVideo:
                result.mainVideoPlacement = source.mainVideoPlacement
                result.mainVideoVolume = source.mainVideoVolume
            case .recording(let id):
                // A file comes back, never goes: takes elsewhere may still point at it.
                if let old = source.recordings.first(where: { $0.id == id }) {
                    if let now = result.recordings.firstIndex(where: { $0.id == id }) {
                        result.recordings[now] = old
                    } else {
                        result.recordings.append(old)
                    }
                }
            case .audio(let id):
                Self.restore(id, in: &result.audio, from: source.audio)
            case .voice:
                result.voiceEffects = source.voiceEffects
            case .title:
                result.title = source.title
            case .transitions:
                result.transitions = source.transitions
            }
        }
        result.updatedAt = .now
        return result
    }

    /// Whether the targeted things are the same here as in `other`.
    public func matches(_ targets: [AITarget], in other: Project) -> Bool {
        targets.allSatisfy { target in
            switch target {
            case .clip(let id):
                segments.first(where: { $0.id == id }) == other.segments.first(where: { $0.id == id })
            case .clipOrder:
                segments.map(\.id) == other.segments.map(\.id)
            case .captions(let id):
                segments.first(where: { $0.id == id })?.captions == other.segments.first(where: { $0.id == id })?.captions
            case .captionStyle:
                captionStyle == other.captionStyle
            case .captionWindow:
                captionWindow == other.captionWindow
            case .overlay(let id):
                overlays.first(where: { $0.id == id }) == other.overlays.first(where: { $0.id == id })
            case .effect(let id):
                effects.first(where: { $0.id == id }) == other.effects.first(where: { $0.id == id })
            case .videoLayer(let id):
                videoLayers.first(where: { $0.id == id }) == other.videoLayers.first(where: { $0.id == id })
            case .mainVideo:
                mainVideoPlacement == other.mainVideoPlacement && mainVideoVolume == other.mainVideoVolume
            case .recording(let id):
                recordings.first(where: { $0.id == id }) == other.recordings.first(where: { $0.id == id })
            case .audio(let id):
                audio.first(where: { $0.id == id }) == other.audio.first(where: { $0.id == id })
            case .voice:
                voiceEffects == other.voiceEffects
            case .title:
                title == other.title
            case .transitions:
                transitions == other.transitions
            }
        }
    }

    private static func restore<Item: Identifiable>(
        _ id: Item.ID,
        in current: inout [Item],
        from source: [Item],
        keepingAtLeastOne: Bool = false
    ) {
        let old = source.firstIndex { $0.id == id }
        let now = current.firstIndex { $0.id == id }
        switch (old, now) {
        case let (old?, now?):
            current[now] = source[old]
        case let (old?, nil):
            current.insert(source[old], at: min(old, current.count))
        case let (nil, now?):
            if !keepingAtLeastOne || current.count > 1 { current.remove(at: now) }
        case (nil, nil):
            break
        }
    }
}

extension Project {
    /// Everything that differs between this project and `before`, as the things a restore puts back.
    ///
    /// What makes taking back one edit out of many possible: the edit's own before and after say
    /// which clips, captions, texts, sounds or settings it touched, and only those are restored —
    /// the edits made after it elsewhere stay.
    public func changedTargets(since before: Project) -> [AITarget] {
        var targets: [AITarget] = []

        func diff<Item: Identifiable & Equatable>(_ now: [Item], _ then: [Item], _ make: (Item.ID) -> AITarget) {
            let old = Dictionary(then.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let new = Dictionary(now.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for item in then where new[item.id] != item { targets.append(make(item.id)) }
            for item in now where old[item.id] == nil { targets.append(make(item.id)) }
        }

        diff(segments, before.segments) { .clip($0) }
        let commonNow = segments.map(\.id).filter { id in before.segments.contains { $0.id == id } }
        let commonThen = before.segments.map(\.id).filter { id in segments.contains { $0.id == id } }
        if commonNow != commonThen || segments.count != before.segments.count {
            targets.append(.clipOrder)
        }
        diff(overlays, before.overlays) { .overlay($0) }
        diff(effects, before.effects) { .effect($0) }
        diff(audio, before.audio) { .audio($0) }
        diff(videoLayers, before.videoLayers) { .videoLayer($0) }
        for recording in before.recordings {
            if recordings.first(where: { $0.id == recording.id }) != recording { targets.append(.recording(recording.id)) }
        }
        if captionStyle != before.captionStyle { targets.append(.captionStyle) }
        if captionWindow != before.captionWindow { targets.append(.captionWindow) }
        if voiceEffects != before.voiceEffects { targets.append(.voice) }
        if title != before.title { targets.append(.title) }
        if transitions != before.transitions { targets.append(.transitions) }
        if mainVideoPlacement != before.mainVideoPlacement || mainVideoVolume != before.mainVideoVolume {
            targets.append(.mainVideo)
        }
        return targets
    }
}
