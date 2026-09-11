import Domain
import Observation
import SwiftUI

/// Teleprompter state. Speech tracking pushes positions in; manual input always wins.
///
/// Knows nothing about audio: StudioFeature connects `ScriptTracking` output to `speakerDidReach`.
@MainActor
@Observable
public final class TeleprompterModel {
    public enum Mode: Hashable, Sendable {
        /// Follows the speaker's voice.
        case speechTracking
        /// Scrolls at a constant speed.
        case fixedSpeed
        /// Only moves when the user scrolls or taps.
        case manual
    }

    public private(set) var segments: [Segment]
    public private(set) var position: ScriptPosition?
    public var mode: Mode
    public var isPaused = false
    public var textScale = 1.0
    public var isMirrored = false

    public init(segments: [Segment], mode: Mode = .speechTracking) {
        self.segments = segments
        self.mode = mode
    }

    public func load(_ segments: [Segment]) {
        self.segments = segments
        position = nil
    }

    public func speakerDidReach(_ position: ScriptPosition) {
        guard mode == .speechTracking, !isPaused else { return }
        self.position = position
    }

    public func userDidMove(to position: ScriptPosition) {
        mode = .manual
        self.position = position
    }
}

/// Segment-level scrolling placeholder. Word highlighting arrives with speech tracking.
public struct TeleprompterView: View {
    private let model: TeleprompterModel

    public init(model: TeleprompterModel) {
        self.model = model
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                    if model.segments.isEmpty {
                        Text("teleprompter.empty", bundle: .module)
                            .font(.cfPrompter(size: 28 * model.textScale))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    ForEach(model.segments) { segment in
                        Text(segment.script)
                            .font(.cfPrompter(size: 34 * model.textScale))
                            .foregroundStyle(segment.id == model.position?.segmentID ? Palette.textPrimary : Palette.textSecondary)
                            .id(segment.id)
                    }
                }
                .padding(Spacing.xl)
            }
            .onChange(of: model.position?.segmentID) { _, segmentID in
                guard let segmentID else { return }
                withAnimation(Motion.smooth) {
                    proxy.scrollTo(segmentID, anchor: .top)
                }
            }
        }
        .scaleEffect(x: model.isMirrored ? -1 : 1, y: 1)
    }
}
