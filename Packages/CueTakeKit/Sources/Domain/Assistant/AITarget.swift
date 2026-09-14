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
    case audio(UUID)
    case voice
    case title

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
            case .audio(let id):
                Self.restore(id, in: &result.audio, from: source.audio)
            case .voice:
                result.voiceEffects = source.voiceEffects
            case .title:
                result.title = source.title
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
            case .audio(let id):
                audio.first(where: { $0.id == id }) == other.audio.first(where: { $0.id == id })
            case .voice:
                voiceEffects == other.voiceEffects
            case .title:
                title == other.title
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
