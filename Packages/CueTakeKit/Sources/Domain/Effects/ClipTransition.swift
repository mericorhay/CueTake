import Foundation

/// How one clip hands over to the next.
///
/// Centred on the cut and made from the clips' own handles: half the transition plays before the
/// cut and half after it, with footage from just past each clip's trimmed end (or its edge frame
/// held, when there is none). The video therefore stays exactly as long as it was — captions,
/// sounds and texts keep their moments — which is why a transition can be added, changed and
/// removed without anything else on the timeline moving.
public struct ClipTransition: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case crossfade
        case fadeBlack
        case fadeWhite
        case slideLeft, slideRight, slideUp, slideDown
        case pushLeft, pushRight
        case wipeLeft, wipeRight, wipeUp, wipeDown
        case zoomIn, zoomOut

        public enum Family: String, CaseIterable, Sendable {
            case blend, slide, wipe, zoom
        }

        public var family: Family {
            switch self {
            case .crossfade, .fadeBlack, .fadeWhite: .blend
            case .slideLeft, .slideRight, .slideUp, .slideDown, .pushLeft, .pushRight: .slide
            case .wipeLeft, .wipeRight, .wipeUp, .wipeDown: .wipe
            case .zoomIn, .zoomOut: .zoom
            }
        }

        /// What the transition is usually as long as.
        public var defaultDuration: Double {
            switch self {
            case .fadeBlack, .fadeWhite: 0.8
            case .zoomIn, .zoomOut: 0.45
            case .slideLeft, .slideRight, .slideUp, .slideDown, .pushLeft, .pushRight: 0.4
            default: 0.5
            }
        }

        /// Names a model may use.
        public init?(loose name: String) {
            let key = name.lowercased().filter { $0.isLetter }
            if let exact = Kind.allCases.first(where: { $0.rawValue.lowercased() == key }) {
                self = exact
                return
            }
            switch key {
            case "dissolve", "fade", "cross", "blend", "mix": self = .crossfade
            case "dip", "diptoblack", "black", "fadetoblack": self = .fadeBlack
            case "white", "flash", "diptowhite", "fadetowhite": self = .fadeWhite
            case "slide", "cover": self = .slideLeft
            case "push": self = .pushLeft
            case "wipe": self = .wipeLeft
            case "zoom", "punch": self = .zoomIn
            default: return nil
            }
        }
    }

    public var id: UUID
    /// The clip the transition leaves; it plays into whichever clip follows it.
    public var after: Segment.ID
    public var kind: Kind
    /// Seconds, centred on the cut.
    public var duration: Double

    public static let durationRange: ClosedRange<Double> = 0.2...2.0

    public init(id: UUID = UUID(), after: Segment.ID, kind: Kind, duration: Double? = nil) {
        self.id = id
        self.after = after
        self.kind = kind
        self.duration = min(max(duration ?? kind.defaultDuration, Self.durationRange.lowerBound), Self.durationRange.upperBound)
    }

    private enum CodingKeys: String, CodingKey { case id, after, kind, duration }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        after = try c.decode(Segment.ID.self, forKey: .after)
        let name = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil
        kind = name.flatMap { Kind(loose: $0) } ?? .crossfade
        let seconds = (try? c.decodeIfPresent(Double.self, forKey: .duration)) ?? nil
        duration = min(max(seconds ?? kind.defaultDuration, Self.durationRange.lowerBound), Self.durationRange.upperBound)
    }

    /// The longest this transition can be between clips of these lengths: each clip gives at
    /// most 45% of itself, so two neighbouring transitions never meet.
    public static func usableDuration(_ wanted: Double, outgoing: Double, incoming: Double) -> Double {
        min(wanted, 0.9 * outgoing, 0.9 * incoming)
    }
}

/// One moment of a transition, described without any video framework: how each of the two
/// clips is drawn, as fractions of the frame.
public struct TransitionLook: Hashable, Sendable {
    /// A part of the frame, as fractions of its width and height.
    public struct Region: Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public struct Layer: Hashable, Sendable {
        public var opacity: Double = 1
        /// Offset as a fraction of the frame's width and height.
        public var dx: Double = 0
        public var dy: Double = 0
        /// Around the frame's centre.
        public var scale: Double = 1
        /// The part of the frame this clip may draw in; nil is all of it.
        public var visible: Region?

        public init() {}
    }

    public var outgoing = Layer()
    public var incoming = Layer()
    /// Which clip is drawn over the other.
    public var incomingOnTop = false
    /// Seen where neither clip draws: black, or white for a dip to white.
    public var whiteBackground = false

    public init() {}

    /// Ease in and out: transitions that move at a constant speed look mechanical.
    public static func eased(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The look at `progress` (0 = all outgoing, 1 = all incoming).
    public static func at(_ progress: Double, kind: ClipTransition.Kind) -> TransitionLook {
        let p = min(max(progress, 0), 1)
        var look = TransitionLook()
        switch kind {
        case .crossfade:
            look.outgoing.opacity = 1 - p
        case .fadeBlack, .fadeWhite:
            look.whiteBackground = kind == .fadeWhite
            look.outgoing.opacity = p < 0.5 ? 1 - p * 2 : 0
            look.incoming.opacity = p < 0.5 ? 0 : (p - 0.5) * 2
            look.incomingOnTop = p >= 0.5
        case .slideLeft:
            look.incomingOnTop = true
            look.incoming.dx = 1 - p
        case .slideRight:
            look.incomingOnTop = true
            look.incoming.dx = -(1 - p)
        case .slideUp:
            look.incomingOnTop = true
            look.incoming.dy = 1 - p
        case .slideDown:
            look.incomingOnTop = true
            look.incoming.dy = -(1 - p)
        case .pushLeft:
            look.outgoing.dx = -p
            look.incoming.dx = 1 - p
        case .pushRight:
            look.outgoing.dx = p
            look.incoming.dx = -(1 - p)
        case .wipeLeft:
            // The edge travels right to left, uncovering the next clip underneath.
            look.outgoing.visible = Region(0, 0, 1 - p, 1)
        case .wipeRight:
            look.outgoing.visible = Region(p, 0, 1 - p, 1)
        case .wipeUp:
            look.outgoing.visible = Region(0, 0, 1, 1 - p)
        case .wipeDown:
            look.outgoing.visible = Region(0, p, 1, 1 - p)
        case .zoomIn:
            look.outgoing.scale = 1 + 0.35 * p
            look.outgoing.opacity = 1 - p
            look.incoming.scale = 1.12 - 0.12 * p
        case .zoomOut:
            look.outgoing.scale = 1 - 0.2 * p
            look.outgoing.opacity = 1 - p
            look.incoming.scale = 1.25 - 0.25 * p
        }
        return look
    }
}

extension Project {
    /// The transition after a clip, if it has one.
    public func transition(after segment: Segment.ID) -> ClipTransition? {
        transitions.last { $0.after == segment }
    }

    /// Sets the transition out of a clip, replacing any it had. Nil removes it.
    public mutating func setTransition(after segment: Segment.ID, kind: ClipTransition.Kind?, duration: Double? = nil) {
        let existing = transition(after: segment)
        transitions.removeAll { $0.after == segment }
        guard let kind else { return }
        let seconds = duration ?? (existing?.kind == kind ? existing?.duration : nil)
        transitions.append(ClipTransition(id: existing?.id ?? UUID(), after: segment, kind: kind, duration: seconds))
    }

    /// Transitions whose clip is gone, or which sit after the last clip, removed.
    public mutating func pruneTransitions() {
        let ids = segments.dropLast().map(\.id)
        let allowed = Set(ids)
        transitions.removeAll { !allowed.contains($0.after) }
    }
}
