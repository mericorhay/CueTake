import Foundation

/// A finished look for a short video, in one tap: the captions, the pace, the camera, the colour,
/// the titles and the sound, chosen together so they fit each other.
///
/// Tools on their own leave taste to the creator — "filter intensity 0.7" — and each one set
/// alone comes out average. A style is the taste: every value below was picked for the style as a
/// whole. It runs the same steps a workflow runs, so a style in the editor, a style inside a
/// workflow and a workflow built by hand can never disagree.
public enum VideoStyle: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    /// Big yellow-keyword captions, a punch-in every few sentences, tight pace, loud sound design.
    case boldBusiness
    /// Warm colour, soft transitions, calm captions, slow pushes.
    case vlog
    /// Face kept centred, readable subtitles, a cinematic grade, almost no effects.
    case podcast
    /// A sponsored video: brand colours and logo, a title on the hook, clear captions, energy.
    case ugcAd
    /// Muted colour, small captions, dissolves, barely any sound design.
    case minimal
    /// Fast cuts, zoom transitions on every cut, punchy captions, bold sound.
    case energetic

    public var id: String { rawValue }

    /// The caption look the style is built around.
    public var captionPreset: String {
        switch self {
        case .boldBusiness: "punch"
        case .vlog: "clean"
        case .podcast: "podcast"
        case .ugcAd: "bold"
        case .minimal: "minimal"
        case .energetic: "beast"
        }
    }

    /// Where captions sit: middle for the loud looks, low for the calm ones.
    public var captionPosition: String {
        switch self {
        case .boldBusiness, .energetic: "middle"
        default: "bottom"
        }
    }

    /// Two colours that say what the style feels like, for its card: `#RRGGBB`.
    public var swatch: (String, String) {
        switch self {
        case .boldBusiness: ("#FFD400", "#111111")
        case .vlog: ("#F2A65A", "#6B4E3D")
        case .podcast: ("#3A506B", "#0B132B")
        case .ugcAd: ("#FF4F7B", "#2B2D42")
        case .minimal: ("#D9D4CC", "#8C8A85")
        case .energetic: ("#00E5FF", "#7A00FF")
        }
    }

    /// The steps, in the order they run. The spoken words come first, because cleanup, captions,
    /// titles and camera moves all find their places in them.
    public var steps: [WorkflowStepKind] {
        let listen: [WorkflowStepKind] = [.analyzeSpeech]
        let captions: [WorkflowStepKind] = [.generateCaptions, .applyCaptionStyle(presetID: captionPreset)]
        switch self {
        case .boldBusiness:
            return listen + [
                .cleanup(CleanupStepOptions()),
                .trimSilences(TrimSilencesOptions(minPause: 0.35, padding: 0.06)),
            ] + captions + [
                .filter(FilterStepOptions(look: "vivid", intensity: 0.35)),
                .trackFace(TrackFaceOptions(closeness: 0.12)),
                .autoZoom(ZoomStepOptions(style: .mixed, amount: 0.16, spacing: 3.5)),
                .addTitle(TitleStepOptions(moment: .start, duration: 2.2, y: 0.2, scale: 1.8, animation: "pop")),
                .soundDesign(SoundDesignOptions(intensity: .bold, keywords: true)),
            ]
        case .vlog:
            return listen + [
                .cleanup(CleanupStepOptions(repeats: true, restarts: true)),
                .trimSilences(TrimSilencesOptions(minPause: 0.6, padding: 0.14)),
            ] + captions + [
                .filter(FilterStepOptions(look: "warm", intensity: 0.55)),
                .autoZoom(ZoomStepOptions(style: .push, amount: 0.08, spacing: 7)),
                .transitions(TransitionStepOptions(kind: "crossfade", seconds: 0.5, placement: .sections)),
                .soundDesign(SoundDesignOptions(intensity: .subtle, impacts: false)),
            ]
        case .podcast:
            return listen + [
                .cleanup(CleanupStepOptions(pauses: true, fillers: true, repeats: false, restarts: false)),
                .trimSilences(TrimSilencesOptions(minPause: 0.8, padding: 0.15)),
                .cleanAudio(CleanAudioOptions()),
            ] + captions + [
                .filter(FilterStepOptions(look: "cinematic", intensity: 0.4)),
                .trackFace(TrackFaceOptions(closeness: 0.14)),
                .soundDesign(SoundDesignOptions(intensity: .subtle, pops: false, impacts: false)),
            ]
        case .ugcAd:
            return listen + [
                .cleanup(CleanupStepOptions()),
                .trimSilences(TrimSilencesOptions(minPause: 0.4, padding: 0.08)),
            ] + captions + [
                .filter(FilterStepOptions(look: "vivid", intensity: 0.3)),
                .autoZoom(ZoomStepOptions(style: .mixed, amount: 0.14, spacing: 4)),
                .transitions(TransitionStepOptions(kind: "slideLeft", seconds: 0.35, placement: .sections)),
                .addTitle(TitleStepOptions(moment: .start, duration: 2.4, y: 0.2, scale: 1.7, animation: "pop")),
                .brandKit(BrandStepOptions()),
                .soundDesign(SoundDesignOptions(intensity: .normal, keywords: true)),
            ]
        case .minimal:
            return listen + [
                .cleanup(CleanupStepOptions(pauses: true, fillers: true, repeats: true, restarts: false)),
                .trimSilences(TrimSilencesOptions(minPause: 0.7, padding: 0.16)),
            ] + captions + [
                .filter(FilterStepOptions(look: "fade", intensity: 0.45)),
                .transitions(TransitionStepOptions(kind: "crossfade", seconds: 0.7, placement: .sections)),
                .soundDesign(SoundDesignOptions(intensity: .subtle, pops: false, impacts: false, dings: false)),
            ]
        case .energetic:
            return listen + [
                .cleanup(CleanupStepOptions()),
                .trimSilences(TrimSilencesOptions(minPause: 0.3, padding: 0.05)),
                .setSpeed(SpeedOptions(target: "hook", speed: 1.1)),
            ] + captions + [
                .filter(FilterStepOptions(look: "vivid", intensity: 0.5)),
                .trackFace(TrackFaceOptions(closeness: 0.12)),
                .autoZoom(ZoomStepOptions(style: .punch, amount: 0.15, spacing: 2.5)),
                .transitions(TransitionStepOptions(kind: "zoomIn", seconds: 0.35, placement: .everyCut)),
                .addTitle(TitleStepOptions(moment: .start, duration: 1.8, y: 0.22, scale: 1.9, animation: "pop")),
                .soundDesign(SoundDesignOptions(intensity: .bold)),
            ]
        }
    }

    /// The style as a workflow of its own, for running and for copying into the library.
    public func workflow(name: String, summary: String? = nil) -> WorkflowDefinition {
        WorkflowDefinition(
            id: Self.workflowID(self),
            name: name,
            summary: summary,
            origin: .builtIn,
            style: WorkflowStyle(captionPreset: captionPreset, captionPosition: captionPosition),
            steps: steps.map { WorkflowStep(kind: $0) }
        )
    }

    static func workflowID(_ style: VideoStyle) -> UUID {
        let index = allCases.firstIndex(of: style) ?? 0
        return UUID(uuidString: String(format: "7C2A4E10-5B1D-4E7A-9F3C-5A1E57%06d", index)) ?? UUID()
    }
}

public struct ApplyStyleOptions: Hashable, Sendable, Codable {
    public var style: VideoStyle

    public init(style: VideoStyle = .boldBusiness) {
        self.style = style
    }

    private enum CodingKeys: String, CodingKey { case style }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = c.value(.style, or: .boldBusiness)
    }
}
