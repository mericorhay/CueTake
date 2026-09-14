import AVFoundation
import Domain
import MediaEngine
import SwiftUI

/// Filters and sound effects: adding them over a stretch, changing them, and the names they go by.
extension EditorModel {
    /// Lays any effect over a stretch of the video and selects it.
    @discardableResult
    public func addEffect(_ kind: TimelineEffect.Kind, from: Double, to: Double) -> TimelineEffect.ID {
        let symbol = switch kind {
        case .background: "person.crop.rectangle"
        case .filter: "camera.filters"
        case .sound: "waveform"
        }
        record("editor.change.effectAdded", symbol: symbol)
        let start = min(max(0, from), max(0, duration - TimelineEffect.minimumLength))
        let end = min(max(to, start + TimelineEffect.minimumLength), max(duration, start + TimelineEffect.minimumLength))
        let effect = TimelineEffect(start: MediaTime(seconds: start), duration: MediaTime(seconds: end - start), kind: kind)
        project.effects.append(effect)
        project.updatedAt = .now
        pulse(.speed)
        select(effect: effect.id)
        syncLiveFilters()
        return effect.id
    }

    public func updateFilter(_ id: TimelineEffect.ID, coalescing key: String = "filter", _ change: (inout FilterSettings) -> Void) {
        updateEffect(id, coalescing: key) { effect in
            guard var settings = effect.filter else { return }
            change(&settings)
            effect.kind = .filter(settings.clamped)
        }
        syncLiveFilters()
    }

    public func updateSound(_ id: TimelineEffect.ID, coalescing key: String = "sound", _ change: (inout SoundSettings) -> Void) {
        updateEffect(id, coalescing: key) { effect in
            guard var settings = effect.sound else { return }
            change(&settings)
            effect.kind = .sound(settings.clamped)
        }
    }

    /// Hands the compositor the filters as they are now, and redraws a paused picture with them.
    public func syncLiveFilters() {
        liveFilters.update(project.effects)
        guard let player, !isPlaying else { return }
        let time = player.currentTime()
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
    }
}

/// The looks, by name, and a swatch that shows each one.
enum FilterPresets {
    static let looks: [FilterSettings.Look] = [.natural, .vivid, .cinematic, .warm, .cool, .vintage, .fade, .chrome, .instant, .dramatic, .mono, .noir]

    static func label(_ look: FilterSettings.Look) -> String {
        switch look {
        case .natural: String(localized: "editor.filter.natural", bundle: .module)
        case .vivid: String(localized: "editor.filter.vivid", bundle: .module)
        case .cinematic: String(localized: "editor.filter.cinematic", bundle: .module)
        case .warm: String(localized: "editor.filter.warm", bundle: .module)
        case .cool: String(localized: "editor.filter.cool", bundle: .module)
        case .vintage: String(localized: "editor.filter.vintage", bundle: .module)
        case .fade: String(localized: "editor.filter.fade", bundle: .module)
        case .chrome: String(localized: "editor.filter.chrome", bundle: .module)
        case .instant: String(localized: "editor.filter.instant", bundle: .module)
        case .dramatic: String(localized: "editor.filter.dramatic", bundle: .module)
        case .mono: String(localized: "editor.filter.mono", bundle: .module)
        case .noir: String(localized: "editor.filter.noir", bundle: .module)
        }
    }

    /// Two colours that say what a look does to a picture.
    static func swatch(_ look: FilterSettings.Look) -> LinearGradient {
        let colors: [Color] = switch look {
        case .natural: [Color(red: 0.45, green: 0.55, blue: 0.62), Color(red: 0.85, green: 0.72, blue: 0.6)]
        case .vivid: [Color(red: 0.1, green: 0.6, blue: 1), Color(red: 1, green: 0.4, blue: 0.3)]
        case .cinematic: [Color(red: 0.08, green: 0.32, blue: 0.4), Color(red: 0.95, green: 0.6, blue: 0.35)]
        case .warm: [Color(red: 0.95, green: 0.62, blue: 0.3), Color(red: 1, green: 0.85, blue: 0.55)]
        case .cool: [Color(red: 0.3, green: 0.55, blue: 0.85), Color(red: 0.7, green: 0.85, blue: 0.95)]
        case .vintage: [Color(red: 0.55, green: 0.45, blue: 0.3), Color(red: 0.85, green: 0.75, blue: 0.55)]
        case .fade: [Color(red: 0.6, green: 0.62, blue: 0.62), Color(red: 0.85, green: 0.82, blue: 0.78)]
        case .chrome: [Color(red: 0.2, green: 0.45, blue: 0.9), Color(red: 1, green: 0.8, blue: 0.2)]
        case .instant: [Color(red: 0.7, green: 0.55, blue: 0.45), Color(red: 0.55, green: 0.75, blue: 0.7)]
        case .dramatic: [Color(red: 0.05, green: 0.05, blue: 0.08), Color(red: 0.6, green: 0.45, blue: 0.35)]
        case .mono: [Color(white: 0.25), Color(white: 0.8)]
        case .noir: [Color(white: 0.02), Color(white: 0.6)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The sound effects, by name and symbol.
enum SoundPresets {
    static let presets: [SoundSettings.Preset] = [.echo, .hall, .room, .telephone, .radio, .megaphone, .robot, .underwater, .deep, .chipmunk, .clean]

    static func label(_ preset: SoundSettings.Preset) -> String {
        switch preset {
        case .clean: String(localized: "editor.sound.clean", bundle: .module)
        case .echo: String(localized: "editor.sound.echo", bundle: .module)
        case .hall: String(localized: "editor.sound.hall", bundle: .module)
        case .room: String(localized: "editor.sound.room", bundle: .module)
        case .telephone: String(localized: "editor.sound.telephone", bundle: .module)
        case .radio: String(localized: "editor.sound.radio", bundle: .module)
        case .megaphone: String(localized: "editor.sound.megaphone", bundle: .module)
        case .robot: String(localized: "editor.sound.robot", bundle: .module)
        case .underwater: String(localized: "editor.sound.underwater", bundle: .module)
        case .deep: String(localized: "editor.sound.deep", bundle: .module)
        case .chipmunk: String(localized: "editor.sound.chipmunk", bundle: .module)
        }
    }

    static func symbol(_ preset: SoundSettings.Preset) -> String {
        switch preset {
        case .clean: "speaker.wave.2"
        case .echo: "dot.radiowaves.right"
        case .hall: "building.columns"
        case .room: "house"
        case .telephone: "phone"
        case .radio: "radio"
        case .megaphone: "megaphone"
        case .robot: "cpu"
        case .underwater: "drop"
        case .deep: "arrow.down.to.line"
        case .chipmunk: "arrow.up.to.line"
        }
    }
}
