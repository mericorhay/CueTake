import Foundation

/// The small sounds that make a short video feel finished: a whoosh on a transition, a pop when a
/// title lands, a hit on a punch-in, a ding on the call to action.
///
/// Every sound is made on the phone (`SoundDesignSynth`), so there is nothing licensed to clear.
/// The plan only says *which* sound goes *where*; placing them follows what the video already has
/// — its cuts, titles and camera moves — so the sound always answers something on screen.
public enum SoundCueKind: String, Hashable, Sendable, Codable, CaseIterable {
    case whoosh
    case pop
    case impact
    case ding
    case click
    case riser

    /// How long the made sound lasts, in seconds.
    public var seconds: Double {
        switch self {
        case .whoosh: 0.6
        case .pop: 0.16
        case .impact: 0.8
        case .ding: 1.1
        case .click: 0.06
        case .riser: 1.4
        }
    }

    /// Where the sound's own peak sits from its start: a whoosh peaks at the cut, not before it.
    public var peak: Double {
        switch self {
        case .whoosh: 0.36
        case .riser: 1.3
        default: 0
        }
    }

    /// The level it sits at under a voice on the normal setting, in dB.
    var baseDecibels: Double {
        switch self {
        case .whoosh: -13
        case .pop: -11
        case .impact: -9
        case .ding: -14
        case .click: -15
        case .riser: -16
        }
    }

    /// The file the sound is written to, inside the project's media folder. Versioned, so a
    /// better-sounding synth never plays an old file.
    public var fileName: String { "\(SoundDesign.filePrefix)\(rawValue)-v1.wav" }
}

public struct SoundCue: Hashable, Sendable {
    public var kind: SoundCueKind
    /// When the sound starts on the finished video.
    public var start: Double
    public var decibels: Double

    public init(kind: SoundCueKind, start: Double, decibels: Double) {
        self.kind = kind
        self.start = start
        self.decibels = decibels
    }
}

public struct SoundDesignOptions: Hashable, Sendable, Codable {
    public enum Intensity: String, Hashable, Sendable, Codable, CaseIterable {
        case subtle
        case normal
        case bold
    }

    public var intensity: Intensity
    public var whooshes: Bool
    public var pops: Bool
    public var impacts: Bool
    public var dings: Bool
    /// A light tick on the words captions colour — numbers, money, "free", "never" — so the eye
    /// and the ear land on the same word.
    public var keywords: Bool

    public init(
        intensity: Intensity = .normal, whooshes: Bool = true, pops: Bool = true, impacts: Bool = true,
        dings: Bool = true, keywords: Bool = false
    ) {
        self.intensity = intensity
        self.whooshes = whooshes
        self.pops = pops
        self.impacts = impacts
        self.dings = dings
        self.keywords = keywords
    }

    private enum CodingKeys: String, CodingKey { case intensity, whooshes, pops, impacts, dings, keywords }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intensity = c.value(.intensity, or: .normal)
        whooshes = c.value(.whooshes, or: true)
        pops = c.value(.pops, or: true)
        impacts = c.value(.impacts, or: true)
        dings = c.value(.dings, or: true)
        keywords = c.value(.keywords, or: false)
    }
}

public enum SoundDesign {
    /// Every file the automatic sound design writes starts with this, which is how its sounds are
    /// told apart from the ones a person added: running it again replaces only its own.
    public static let filePrefix = "cue-sfx-"

    public static func isAutomatic(_ clip: AudioClip) -> Bool {
        (clip.relativePath as NSString).lastPathComponent.hasPrefix(filePrefix)
    }

    /// The sounds for a video, in time order.
    public static func plan(_ options: SoundDesignOptions, for document: EditDocument) -> [SoundCue] {
        let total = document.duration
        guard total > 1 else { return [] }
        let offset: Double = switch options.intensity {
        case .subtle: -4
        case .normal: 0
        case .bold: 2.5
        }
        // The least time between two sounds: fewer, further apart, on the subtle setting.
        let gap: Double = switch options.intensity {
        case .subtle: 2.5
        case .normal: 1.2
        case .bold: 0.6
        }

        var wanted: [(kind: SoundCueKind, moment: Double, priority: Int)] = []

        if options.whooshes {
            let clips = document.clips
            for index in clips.indices.dropLast() {
                let cut = clips[index].at + clips[index].length
                let hasTransition = clips[index].transition != nil
                let sectionChange = clips[index].role.lowercased() != clips[index + 1].role.lowercased()
                if hasTransition || (sectionChange && options.intensity != .subtle) || options.intensity == .bold {
                    wanted.append((.whoosh, cut, hasTransition ? 3 : 1))
                }
            }
        }

        if options.pops {
            for overlay in document.overlays ?? [] where overlay.kind == "text" || overlay.template != nil {
                // A designed card pops; plain words get a lighter click when the mix is quiet.
                let kind: SoundCueKind = overlay.template == nil && options.intensity == .subtle ? .click : .pop
                wanted.append((kind, overlay.at, 2))
            }
        }

        if options.impacts {
            for move in document.cameraMoves ?? [] where move.kind == "punch" {
                wanted.append((.impact, move.at, 2))
            }
            if options.intensity == .bold, let hook = document.clips.first, document.clips.count > 1 {
                // The hook's last moment: a riser into the first cut.
                let cut = hook.at + hook.length
                if cut > SoundCueKind.riser.peak + 0.2 { wanted.append((.riser, cut, 1)) }
            }
        }

        if options.keywords {
            let locale = Locale(identifier: document.language)
            var last = -Double.infinity
            for clip in document.clips {
                let speed = max(clip.speed ?? 1, 0.05)
                for word in clip.words where CaptionKeywords.isKeyword(word.text, locale: locale) {
                    let moment = clip.at + word.start / speed
                    // Never more than one every two seconds: a tick on every word is noise.
                    guard moment - last >= 2, moment < clip.at + clip.length else { continue }
                    wanted.append((options.intensity == .bold ? .pop : .click, moment, 0))
                    last = moment
                }
            }
        }

        if options.dings, let cta = document.clips.first(where: { $0.role.lowercased() == "cta" }) {
            wanted.append((.ding, cta.at + 0.15, 2))
        }

        // Keep the more important sound when two want the same moment.
        var placed: [SoundCue] = []
        var moments: [Double] = []
        for item in wanted.sorted(by: { $0.priority != $1.priority ? $0.priority > $1.priority : $0.moment < $1.moment }) {
            guard item.moment >= 0, item.moment < total else { continue }
            // A riser leads into its cut rather than sitting on it, so it shares the cut's moment.
            let leads = item.kind == .riser
            guard leads || !moments.contains(where: { abs($0 - item.moment) < gap }) else { continue }
            let start = max(0, item.moment - item.kind.peak)
            if !leads { moments.append(item.moment) }
            placed.append(SoundCue(kind: item.kind, start: start, decibels: item.kind.baseDecibels + offset))
        }
        return placed.sorted { $0.start < $1.start }
    }
}
