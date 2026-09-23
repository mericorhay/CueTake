import DesignSystem
import Domain
import SwiftUI

/// How each tool and section is named and drawn. Domain owns what the tools *are*; this module
/// owns what they are called on screen.
enum StudioCatalog {
    struct Tool: Identifiable {
        var id: String { type }
        var type: String
        var symbol: String
        var title: String.LocalizationValue
        var note: String.LocalizationValue
        var category: WorkflowToolCategory
    }

    /// Every tool the palette offers, in the order they usually run.
    static let tools: [Tool] = [
        Tool(type: "generateVideo", symbol: "wand.and.stars", title: "tool.generateVideo", note: "tool.generateVideo.note", category: .generate),
        Tool(type: "assembleSections", symbol: "square.stack.3d.up", title: "tool.assembleSections", note: "tool.assembleSections.note", category: .structure),
        Tool(type: "analyzeSpeech", symbol: "waveform.and.person.filled", title: "tool.analyzeSpeech", note: "tool.analyzeSpeech.note", category: .words),
        Tool(type: "stockBroll", symbol: "photo.stack", title: "tool.stockBroll", note: "tool.stockBroll.note", category: .generate),
        Tool(type: "aiEdit", symbol: "sparkles", title: "tool.aiEdit", note: "tool.aiEdit.note", category: .generate),
        Tool(type: "cleanup", symbol: "wand.and.stars", title: "tool.cleanup", note: "tool.cleanup.note", category: .cut),
        Tool(type: "bestTakes", symbol: "film.stack", title: "tool.bestTakes", note: "tool.bestTakes.note", category: .cut),
        Tool(type: "trimSilences", symbol: "arrow.right.and.line.vertical.and.arrow.left", title: "tool.trimSilences", note: "tool.trimSilences.note", category: .cut),
        Tool(type: "cutWords", symbol: "text.badge.minus", title: "tool.cutWords", note: "tool.cutWords.note", category: .cut),
        Tool(type: "setSpeed", symbol: "gauge.with.dots.needle.67percent", title: "tool.setSpeed", note: "tool.setSpeed.note", category: .cut),
        Tool(type: "cleanAudio", symbol: "wind", title: "tool.cleanAudio", note: "tool.cleanAudio.note", category: .sound),
        Tool(type: "musicBed", symbol: "music.note", title: "tool.musicBed", note: "tool.musicBed.note", category: .sound),
        Tool(type: "soundDesign", symbol: "speaker.wave.3.fill", title: "tool.soundDesign", note: "tool.soundDesign.note", category: .sound),
        Tool(type: "voiceEffect", symbol: "waveform.badge.plus", title: "tool.voiceEffect", note: "tool.voiceEffect.note", category: .sound),
        Tool(type: "generateCaptions", symbol: "captions.bubble", title: "tool.generateCaptions", note: "tool.generateCaptions.note", category: .words),
        Tool(type: "applyCaptionStyle", symbol: "textformat.size", title: "tool.applyCaptionStyle", note: "tool.applyCaptionStyle.note", category: .words),
        Tool(type: "filter", symbol: "camera.filters", title: "tool.filter", note: "tool.filter.note", category: .look),
        Tool(type: "background", symbol: "person.crop.rectangle", title: "tool.background", note: "tool.background.note", category: .look),
        Tool(type: "trackFace", symbol: "viewfinder", title: "tool.trackFace", note: "tool.trackFace.note", category: .look),
        Tool(type: "autoZoom", symbol: "plus.magnifyingglass", title: "tool.autoZoom", note: "tool.autoZoom.note", category: .look),
        Tool(type: "beatSync", symbol: "metronome", title: "tool.beatSync", note: "tool.beatSync.note", category: .look),
        Tool(type: "transitions", symbol: "square.on.square.intersection.dashed", title: "tool.transitions", note: "tool.transitions.note", category: .look),
        Tool(type: "videoLayout", symbol: "rectangle.split.2x1", title: "tool.videoLayout", note: "tool.videoLayout.note", category: .look),
        Tool(type: "applyStyle", symbol: "wand.and.rays", title: "tool.applyStyle", note: "tool.applyStyle.note", category: .brand),
        Tool(type: "addTitle", symbol: "textformat", title: "tool.addTitle", note: "tool.addTitle.note", category: .brand),
        Tool(type: "brandTemplate", symbol: "sparkles.rectangle.stack", title: "tool.brandTemplate", note: "tool.brandTemplate.note", category: .brand),
        Tool(type: "brandKit", symbol: "paintpalette", title: "tool.brandKit", note: "tool.brandKit.note", category: .brand),
        Tool(type: "export", symbol: "square.and.arrow.up", title: "tool.export", note: "tool.export.note", category: .deliver),
    ]

    /// What can be added: the closing export is always there already.
    static var addable: [Tool] { tools.filter { $0.type != "export" } }

    static func tool(for type: String) -> Tool {
        tools.first { $0.type == type }
            ?? Tool(type: type, symbol: "questionmark.square.dashed", title: "tool.unknown", note: "tool.unknown.note", category: .deliver)
    }

    static func categoryTitle(_ category: WorkflowToolCategory) -> String.LocalizationValue {
        switch category {
        case .structure: "category.structure"
        case .generate: "category.generate"
        case .cut: "category.cut"
        case .sound: "category.sound"
        case .words: "category.words"
        case .look: "category.look"
        case .brand: "category.brand"
        case .deliver: "category.deliver"
        }
    }

    static func tint(_ category: WorkflowToolCategory) -> Color {
        switch category {
        case .structure: DS.Palette.ink(0.75)
        case .generate: DS.Palette.lime
        case .cut: DS.Palette.accent
        case .sound: DS.Palette.accentWarm
        case .words: DS.Palette.lime
        case .look: DS.Palette.accent
        case .brand: DS.Palette.accentWarm
        case .deliver: DS.Palette.ink
        }
    }

    /// The parameters of a step, as a line someone can read at a glance on a collapsed card.
    static func summary(of kind: WorkflowStepKind) -> String {
        switch kind {
        case .trimSilences(let o):
            return String(format: "> %.2g s · %.2g s", o.minPause, o.padding)
        case .cutWords(let o):
            return o.words.prefix(4).joined(separator: ", ") + (o.words.count > 4 ? "…" : "")
        case .setSpeed(let o):
            return "\(o.target.uppercased()) · \(String(format: "%.2g", o.speed))×"
        case .cleanAudio(let o):
            return [o.denoise ? "denoise" : nil, o.enhanceVoice ? "voice" : nil, o.removeRumble ? "rumble" : nil]
                .compactMap { $0 }.joined(separator: " · ")
        case .musicBed(let o):
            return String(format: "%.0f dB", o.levelDB) + (o.ducking ? " · duck" : "")
        case .applyCaptionStyle(let preset):
            return preset
        case .cleanup(let o):
            return [o.pauses ? "pause" : nil, o.fillers ? "filler" : nil, o.repeats ? "repeat" : nil, o.restarts ? "restart" : nil]
                .compactMap { $0 }.joined(separator: " · ")
        case .brandKit(let o):
            return [o.colors ? "colors" : nil, o.logo ? "logo" : nil].compactMap { $0 }.joined(separator: " · ")
        case .addTitle(let o):
            let text = o.text.isEmpty ? "“…”" : "“\(o.text.prefix(24))”"
            return "\(text) · \(o.moment.rawValue) · \(String(format: "%.1f", o.duration)) s"
        case .brandTemplate(let o):
            return "\(o.style) · \(o.moment.rawValue) · \(String(format: "%.0f", o.duration)) s"
        case .filter(let o):
            return "\(o.look) · \(Int(o.intensity * 100))% · \(targetLabel(o.target))"
        case .background(let o):
            return "\(o.style) · \(Int(o.strength * 100))% · \(targetLabel(o.target))"
        case .autoZoom(let o):
            return "\(o.style.rawValue) · \(Int(o.amount * 100))% · \(String(format: "%.0f", o.spacing)) s"
        case .trackFace(let o):
            return "\(Int(o.closeness * 100))%"
        case .transitions(let o):
            return "\(o.kind) · \(String(format: "%.1f", o.seconds)) s · \(o.placement.rawValue)"
        case .voiceEffect(let o):
            return "\(o.preset) · \(Int(o.amount * 100))% · \(targetLabel(o.target))"
        case .videoLayout(let o):
            return o.layout
        case .stockBroll(let o):
            return "\(o.count)×"
        case .beatSync(let o):
            return "\(o.pulse.rawValue) · \(Int(o.amount * 100))%"
        case .applyStyle(let o):
            return AppLocalization.string(String.LocalizationValue(stringLiteral: "style." + o.style.rawValue), bundle: .module)
        case .soundDesign(let o):
            return [o.intensity.rawValue, o.whooshes ? "whoosh" : nil, o.pops ? "pop" : nil, o.impacts ? "hit" : nil, o.dings ? "ding" : nil]
                .compactMap { $0 }.joined(separator: " · ")
        case .aiEdit(let o):
            return o.instruction.isEmpty ? "" : "“\(o.instruction.prefix(40))”"
        case .generateVideo(let o):
            let name = o.modelPreset.isCustom && !o.customModel.isEmpty ? o.customModel : o.modelPreset.title
            let count = o.prompts.isEmpty ? "§" : "\(o.prompts.count)×"
            return "\(name) · \(count) · \(Int(o.seconds)) s · \(o.aspect)"
        case .export(let preset):
            var parts = [preset.format.label]
            if let delivery = preset.delivery, delivery.isEnabled {
                parts.append("API → " + (delivery.url?.host() ?? "?"))
            }
            return parts.joined(separator: " · ")
        default:
            return ""
        }
    }

    /// The whole video, or a section's role.
    static func targetLabel(_ target: String) -> String {
        target == WorkflowTarget.all ? AppLocalization.string("studio.param.all", bundle: .module) : roleLabel(target)
    }

    // MARK: - Sections

    static func roleLabel(_ role: String) -> String {
        switch role.lowercased() {
        case "cta": "CTA"
        default: role.uppercased()
        }
    }

    static func roleTint(_ role: String) -> Color {
        DS.Palette.segment(at: WorkflowSection(role: role).segmentRole.paletteIndex)
    }
}
