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
        Tool(type: "assembleSections", symbol: "square.stack.3d.up", title: "tool.assembleSections", note: "tool.assembleSections.note", category: .structure),
        Tool(type: "analyzeSpeech", symbol: "waveform.and.person.filled", title: "tool.analyzeSpeech", note: "tool.analyzeSpeech.note", category: .words),
        Tool(type: "trimSilences", symbol: "arrow.right.and.line.vertical.and.arrow.left", title: "tool.trimSilences", note: "tool.trimSilences.note", category: .cut),
        Tool(type: "cutWords", symbol: "text.badge.minus", title: "tool.cutWords", note: "tool.cutWords.note", category: .cut),
        Tool(type: "setSpeed", symbol: "gauge.with.dots.needle.67percent", title: "tool.setSpeed", note: "tool.setSpeed.note", category: .cut),
        Tool(type: "cleanAudio", symbol: "wind", title: "tool.cleanAudio", note: "tool.cleanAudio.note", category: .sound),
        Tool(type: "musicBed", symbol: "music.note", title: "tool.musicBed", note: "tool.musicBed.note", category: .sound),
        Tool(type: "generateCaptions", symbol: "captions.bubble", title: "tool.generateCaptions", note: "tool.generateCaptions.note", category: .words),
        Tool(type: "applyCaptionStyle", symbol: "textformat.size", title: "tool.applyCaptionStyle", note: "tool.applyCaptionStyle.note", category: .words),
        Tool(type: "export", symbol: "square.and.arrow.up", title: "tool.export", note: "tool.export.note", category: .deliver),
    ]

    static func tool(for type: String) -> Tool {
        tools.first { $0.type == type }
            ?? Tool(type: type, symbol: "questionmark.square.dashed", title: "tool.unknown", note: "tool.unknown.note", category: .deliver)
    }

    static func categoryTitle(_ category: WorkflowToolCategory) -> String.LocalizationValue {
        switch category {
        case .structure: "category.structure"
        case .cut: "category.cut"
        case .sound: "category.sound"
        case .words: "category.words"
        case .deliver: "category.deliver"
        }
    }

    static func tint(_ category: WorkflowToolCategory) -> Color {
        switch category {
        case .structure: DS.Palette.ink(0.75)
        case .cut: DS.Palette.accent
        case .sound: DS.Palette.accentWarm
        case .words: DS.Palette.lime
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
        case .export(let preset):
            return preset.format.label
        default:
            return ""
        }
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
