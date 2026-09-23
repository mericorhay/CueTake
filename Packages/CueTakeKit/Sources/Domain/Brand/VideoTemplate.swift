import Foundation

/// A video someone already made, kept as the way they make videos.
///
/// Not a stock design: a template is taken from a finished project — its shape, its caption look
/// and position, its colour grade, the transition it cuts with — so the second video in a series
/// starts where the first one ended up instead of at the defaults.
public struct VideoTemplate: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var format: VideoFormat
    /// The caption look by its preset name, and where captions sit.
    public var captionPreset: String
    public var captionPosition: CaptionPosition
    public var captionMaxWords: Int
    /// The grade over the whole video, when it had one.
    public var look: FilterSettings?
    /// What it cuts with, when every cut used the same thing.
    public var transition: ClipTransition.Kind?
    public var transitionSeconds: Double?
    /// Whether applying it also paints the brand's colours on.
    public var usesBrand: Bool
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        format: VideoFormat,
        captionPreset: String,
        captionPosition: CaptionPosition,
        captionMaxWords: Int,
        look: FilterSettings? = nil,
        transition: ClipTransition.Kind? = nil,
        transitionSeconds: Double? = nil,
        usesBrand: Bool = true,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.captionPreset = captionPreset
        self.captionPosition = captionPosition
        self.captionMaxWords = captionMaxWords
        self.look = look
        self.transition = transition
        self.transitionSeconds = transitionSeconds
        self.usesBrand = usesBrand
        self.updatedAt = updatedAt
    }

    /// Everything about how a project looks, taken from the project itself.
    public init(name: String, from project: Project, usesBrand: Bool = true) {
        let total = project.segments.reduce(0) { $0 + $1.barWeight }
        // A grade that covers the whole video is the video's look; a graded moment is not.
        let look = project.effects.first { effect in
            effect.filter != nil && effect.start.seconds < 0.05 && effect.end >= total * 0.95
        }?.filter
        // One transition used at every cut is how this video cuts; a mixture is not a rule.
        let kinds = Set(project.transitions.map(\.kind))
        let everywhere = project.segments.count > 1 && project.transitions.count >= project.segments.count - 1
        self.init(
            name: name,
            format: project.format,
            captionPreset: project.captionStyle.presetID,
            captionPosition: project.captionStyle.position,
            captionMaxWords: project.captionStyle.maxWordsPerCue,
            look: look,
            transition: kinds.count == 1 && everywhere ? kinds.first : nil,
            transitionSeconds: kinds.count == 1 && everywhere ? project.transitions.first?.duration : nil,
            usesBrand: usesBrand
        )
    }

    /// A name from the project's own title, for a template saved without one. Empty when the
    /// project has no title either: the screen offering to save it can ask.
    public static func name(for project: Project) -> String {
        project.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Project {
    /// Makes this project look like the template.
    ///
    /// The footage, the words and the cuts are the user's and are never touched. What changes is
    /// how it is presented: shape, captions, grade, and the transition on cuts that have none.
    ///
    /// - Parameter brand: applied after the template when the template asks for it.
    public mutating func apply(_ template: VideoTemplate, brand: BrandKit? = nil) {
        format = template.format.deliveryCompatible
        let position = template.captionPosition
        captionStyle = CaptionStyle.preset(template.captionPreset, position: position)
        captionStyle.maxWordsPerCue = template.captionMaxWords
        for index in segments.indices where !segments[index].captions.contains(where: \.isUserEdited) {
            guard segments[index].selectedTake?.transcript?.words.isEmpty == false else { continue }
            segments[index].refreshCaptions(maxWordsPerCue: captionStyle.maxWordsPerCue)
        }

        let total = segments.reduce(0) { $0 + $1.barWeight }
        effects.removeAll { effect in
            effect.filter != nil && effect.start.seconds < 0.05 && effect.end >= total * 0.95
        }
        if let look = template.look, total > 0.2 {
            effects.append(
                TimelineEffect(start: .zero, duration: MediaTime(seconds: total), kind: .filter(look))
            )
        }

        if let kind = template.transition {
            let already = Set(transitions.map(\.after))
            for index in segments.indices.dropLast() where !already.contains(segments[index].id) {
                let seconds = ClipTransition.usableDuration(
                    template.transitionSeconds ?? kind.defaultDuration,
                    outgoing: segments[index].barWeight,
                    incoming: segments[index + 1].barWeight
                )
                guard seconds >= ClipTransition.durationRange.lowerBound else { continue }
                setTransition(after: segments[index].id, kind: kind, duration: seconds)
            }
        }

        if template.usesBrand, let brand {
            apply(brand)
        }
        updatedAt = .now
    }
}
