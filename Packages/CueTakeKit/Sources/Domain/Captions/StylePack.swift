import Foundation

/// A whole look in one tap: how captions read, how clips hand over, and the colour of the picture.
///
/// Applied as ordinary edits — a caption style, a transition on each cut, a filter over the video —
/// so every part of it stays visible on the timeline and can be changed or undone on its own.
public struct StylePack: Identifiable, Hashable, Sendable {
    public var id: String
    public var captionPreset: String
    /// Put on every cut. Nil leaves the cuts as they are.
    public var transition: ClipTransition.Kind?
    /// Laid over the whole video. Nil removes a look a pack put there.
    public var look: FilterSettings.Look?

    public init(id: String, captionPreset: String, transition: ClipTransition.Kind?, look: FilterSettings.Look?) {
        self.id = id
        self.captionPreset = captionPreset
        self.transition = transition
        self.look = look
    }

    public static let all: [StylePack] = [
        StylePack(id: "viral", captionPreset: "punch", transition: .zoomIn, look: .vivid),
        StylePack(id: "energy", captionPreset: "beast", transition: .slideLeft, look: .dramatic),
        StylePack(id: "clean", captionPreset: "subtle", transition: .crossfade, look: nil),
        StylePack(id: "talk", captionPreset: "podcast", transition: nil, look: nil),
        StylePack(id: "story", captionPreset: "story", transition: .pushLeft, look: .warm),
        StylePack(id: "cinema", captionPreset: "typewriter", transition: .fadeBlack, look: .cinematic),
    ]

    public static func named(_ id: String) -> StylePack? {
        all.first { $0.id == id }
    }
}

extension Project {
    /// The pack's caption preset, keeping where captions sit; its transition on every cut; its
    /// look over the whole video, replacing a whole-video look already there.
    public mutating func apply(_ pack: StylePack) {
        let previous = captionStyle
        captionStyle = CaptionStyle.preset(pack.captionPreset, position: previous.position)
        if previous.maxWordsPerCue != captionStyle.maxWordsPerCue {
            for index in segments.indices {
                guard segments[index].selectedTake?.transcript?.words.isEmpty == false,
                      !segments[index].captions.contains(where: \.isUserEdited)
                else { continue }
                segments[index].refreshCaptions(maxWordsPerCue: captionStyle.maxWordsPerCue)
            }
        }

        if let kind = pack.transition {
            for index in segments.indices.dropLast() {
                let incoming = segments[index + 1].barWeight
                let outgoing = segments[index].barWeight
                let seconds = ClipTransition.usableDuration(kind.defaultDuration, outgoing: outgoing, incoming: incoming)
                guard seconds >= ClipTransition.durationRange.lowerBound else { continue }
                setTransition(after: segments[index].id, kind: kind, duration: seconds)
            }
        }

        let total = segments.reduce(0) { $0 + $1.barWeight }
        effects.removeAll { effect in
            effect.filter != nil && effect.start.seconds < 0.05 && effect.end >= total * 0.95
        }
        if let look = pack.look, total > 0 {
            effects.append(TimelineEffect(
                start: .zero,
                duration: MediaTime(seconds: total),
                kind: .filter(FilterSettings(look: look))
            ))
        }
        updatedAt = .now
    }
}
