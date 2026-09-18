import DesignSystem
import Domain
import Observation
import SwiftUI

/// Render progress as four staged cards, then the share sheet.
@MainActor
@Observable
public final class ExportModel {
    /// 0 = not started, 1...4 = the stage currently running, 4 = finished.
    public private(set) var stage = 0

    /// 0...1 while the file is being written. Nil before and after.
    public private(set) var progress: Double?
    /// Where the finished file landed, once there is one.
    public private(set) var outputURL: URL?
    /// Set when the export could not finish. Shown instead of pretending it did.
    public private(set) var failure: String?
    /// Where the finished video went, said on the finished screen.
    public enum Destination: Sendable, Equatable {
        case photos
        /// Photos access was refused; the file is still here to share or save.
        case photosRefused
        case fileOnly
    }
    public private(set) var destination: Destination?
    /// The system's own words for the last failure, for anyone reporting it.
    public private(set) var failureDetail: String?
    /// The captions and overlays could not be burned in; the video was written without them.
    public private(set) var droppedCaptions = false
    /// How big the finished file is.
    public private(set) var fileBytes: Int64?
    /// What the finished file is, in one line: size, frame rate, codec.
    public private(set) var summary: String?

    public init() {}

    /// Nothing under way: the format can be changed and a render started, including after a
    /// failure — the button used to disappear with the error, leaving nothing to try again with.
    public var isIdle: Bool { stage == 0 }
    public var hasFailed: Bool { failure != nil }
    public var isDone: Bool { stage >= 4 }
    public var isRunning: Bool { stage > 0 && stage < 4 }

    // The stages used to be a timer, because there was nothing to time. They are now driven by the
    // work itself: the screen does not know how to compose a video and should not learn, so
    // whoever does the composing moves this along.

    public func begin() {
        failure = nil
        failureDetail = nil
        droppedCaptions = false
        outputURL = nil
        fileBytes = nil
        summary = nil
        destination = nil
        progress = nil
        stage = 1
    }

    public func report(_ value: Double) {
        progress = min(max(0, value), 1)
    }

    public func advance(to next: Int) {
        guard next > stage, next < 4 else { return }
        stage = next
    }

    public func succeed(
        url: URL,
        destination: Destination = .fileOnly,
        format: VideoFormat? = nil,
        droppedCaptions: Bool = false
    ) {
        outputURL = url
        self.destination = destination
        self.droppedCaptions = droppedCaptions
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        fileBytes = bytes
        if let format {
            let size = format.renderSize
            var parts = ["\(size.width)×\(size.height)", "\(format.frameRate) fps", format.resolution.prefersHEVC ? "HEVC" : "H.264"]
            if let bytes { parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
            summary = parts.joined(separator: " · ")
        }
        progress = nil
        stage = 4
    }

    public func fail(_ reason: String, detail: String? = nil) {
        failure = reason
        failureDetail = detail
        progress = nil
        stage = 0
    }

    /// Nothing ticks here any more; the export runs where the work is. Kept so navigation can
    /// treat every model the same way.
    public func stopTimers() {}

    public func reset() {
        stage = 0
        destination = nil
        outputURL = nil
        failure = nil
        failureDetail = nil
        droppedCaptions = false
        fileBytes = nil
        summary = nil
        progress = nil
    }
}

public struct ExportScreen: View {
    @Bindable private var model: ExportModel
    /// Bound to the project, not to a copy: the format chosen here is what the project *is*, and
    /// an export screen that quietly renders at something other than what the editor previewed
    /// is the oldest lie in video software.
    @Binding private var format: VideoFormat
    private let captionStyleName: String
    private let onRender: () -> Void
    private let onBack: () -> Void
    private let onDone: () -> Void

    public init(
        model: ExportModel,
        format: Binding<VideoFormat>,
        captionStyleName: String = "pop",
        onRender: @escaping () -> Void,
        onBack: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.model = model
        self._format = format
        self.captionStyleName = captionStyleName
        self.onRender = onRender
        self.onBack = onBack
        self.onDone = onDone
    }

    private struct Stage {
        var titleKey: String.LocalizationValue
        var note: String
    }

    private var stages: [Stage] {
        [
            Stage(titleKey: "export.stage.timeline", note: String(localized: "export.stage.timeline.note", bundle: .module)),
            Stage(titleKey: "export.stage.render", note: String(localized: "export.stage.render.note", bundle: .module)),
            Stage(titleKey: "export.stage.captions", note: String(localized: "export.stage.captions.note \(captionStyleName)", bundle: .module)),
            Stage(titleKey: "export.stage.final", note: String(localized: "export.stage.final.note", bundle: .module)),
        ]
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            if model.isIdle {
                formatPicker
                    .padding(.top, 16)
            }

            VStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    stageCard(stage, at: index)
                }
            }
            .frame(maxHeight: .infinity)

            if model.isDone {
                finished
            } else if model.isIdle {
                DSPrimaryButton(
                    String(localized: model.hasFailed ? "export.retry" : "export.render", bundle: .module),
                    radius: DS.Radius.cardLarge,
                    verticalPadding: 19,
                    fontSize: 16
                ) {
                    onRender()
                }
            }

            if let progress = model.progress {
                // A real bar, moving at the pace of the write. The stages above say what is
                // happening; this says how much of it is left.
                VStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.Palette.hairline(0.1))
                        GeometryReader { proxy in
                            Capsule()
                                .fill(DS.Palette.accent)
                                .frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 3)

                    Text(verbatim: "\(Int(progress * 100))%")
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.56))
                        .contentTransition(.numericText())
                }
                .padding(.top, 14)
                .animation(DS.Motion.settle, value: progress)
            }

            if let failure = model.failure {
                VStack(spacing: 4) {
                    Label {
                        Text(failure)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.accent)
                    if let detail = model.failureDetail {
                        Text(verbatim: detail)
                            .dsFont(.mono, .medium, 10)
                            .foregroundStyle(DS.Palette.ink(0.56))
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 60)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsScreenLayout()
        .background(DS.Palette.screen)
        .dsEnter(.screen())
    }

    private var header: some View {
        HStack {
            DSBackButton(size: 34, fontSize: 15, action: onBack)
            Spacer(minLength: 0)
            DSKicker(String(localized: "export.kicker", bundle: .module))
            Spacer(minLength: 0)
            Color.clear.frame(width: 34, height: 34)
        }
    }

    // MARK: - Format

    /// Resolution and frame rate, before the render rather than buried in settings.
    ///
    /// This is the last moment anybody can change it and the first moment most people think about
    /// it. Combinations no phone can write are not offered — see `isPhysicallyPlausible` — because
    /// an option that fails at the end of a four minute render is worse than no option.
    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DSKicker(String(localized: "export.format", bundle: .module), size: 10, color: DS.Palette.ink(0.52))
                Spacer(minLength: 0)
                Text(Self.sizeEstimate(for: format))
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.56))
                    .contentTransition(.numericText())
            }

            HStack(spacing: 6) {
                ForEach(VideoFormat.Resolution.allCases, id: \.self) { resolution in
                    chip(resolution.label, isOn: format.resolution == resolution) {
                        format.resolution = resolution
                        // Dropping to something the pair can actually be. Choosing 8K and keeping
                        // 120fps would leave the screen showing a format that does not exist.
                        if !format.isPhysicallyPlausible { format.frameRate = 30 }
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(VideoFormat.frameRateChoices, id: \.self) { rate in
                    let candidate = VideoFormat(
                        aspectRatio: format.aspectRatio,
                        resolution: format.resolution,
                        frameRate: rate
                    )
                    chip(
                        "\(rate)",
                        isOn: format.frameRate == rate,
                        enabled: candidate.isPhysicallyPlausible
                    ) {
                        format.frameRate = rate
                    }
                }
            }
        }
        .animation(DS.Motion.snap, value: format)
    }

    private func chip(
        _ label: String,
        isOn: Bool,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .dsFont(.mono, .medium, 12)
                .foregroundStyle(
                    enabled
                        ? (isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.6))
                        : DS.Palette.ink(0.2)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07))
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 12))
        .disabled(!enabled)
    }

    /// Roughly how big the file will be, per minute.
    ///
    /// Per minute rather than in total because the total is a number nobody can check, and the
    /// point of showing it is to make 8K120 feel like what it is before it fills a phone.
    static func sizeEstimate(for format: VideoFormat) -> String {
        let megabytesPerMinute = Double(format.suggestedBitRate) * 60 / 8 / 1_000_000
        return String(format: "~%.0f MB/min", megabytesPerMinute)
    }

    private func stageCard(_ stage: Stage, at index: Int) -> some View {
        let isDone = model.stage > index + 1
        let isActive = model.stage == index + 1
        let isIdle = model.isIdle

        let ink: Color = isIdle
            ? DS.Palette.ink(0.35)
            : (isDone ? DS.Palette.ink(0.45) : (isActive ? DS.Palette.ink : DS.Palette.ink(0.2)))

        return HStack(spacing: 13) {
            Text(isDone ? "✓" : String(index + 1))
                .dsFont(.mono, .medium, 13)
                .foregroundStyle(isDone || isActive ? DS.Palette.inkInverse : DS.Palette.ink(0.4))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .fill(isDone ? DS.Palette.accent : (isActive ? DS.Palette.lime : DS.Palette.hairline(0.07)))
                )
                .modifier(PulseIfActive(isActive: isActive))

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: stage.titleKey, bundle: .module))
                    .dsFont(.archivo, .bold, 18)
                    .foregroundStyle(ink)
                Text(stage.note)
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.ink(0.52))
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(isActive ? DS.Palette.surfaceActive : DS.Palette.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(isActive ? DS.Palette.lime(0.4) : DS.Palette.hairline(0.06), lineWidth: 1)
        }
        .scaleEffect(isActive ? 1.03 : 0.97)
        .rotation3DEffect(
            .degrees(isActive ? 0 : 6),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.4
        )
        .padding(.bottom, 10)
        .animation(DS.Easing.standard(0.55), value: model.stage)
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSHeadline(String(localized: "export.ready", bundle: .module), size: 28)
                .padding(.bottom, 6)

            if let summary = model.summary {
                Text(verbatim: summary)
                    .dsFont(.mono, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.56))
                    .padding(.bottom, model.droppedCaptions ? 6 : 18)
            }
            if model.droppedCaptions {
                Label {
                    Text("export.droppedCaptions", bundle: .module)
                } icon: {
                    Image(systemName: "captions.bubble")
                }
                .dsFont(.sans, .medium, 11)
                .foregroundStyle(DS.Palette.accent)
                .padding(.bottom, 14)
            }

            // Where it went, in a sentence. The screen used to say "ready" and show four tiles that
            // did nothing, so a video saved to Photos and a video saved nowhere looked the same.
            destinationLine
                .padding(.bottom, 14)

            if let url = model.outputURL {
                // The system share sheet: Instagram, TikTok, YouTube, Files, AirDrop, Save Video —
                // whatever this phone has, without the app pretending to know.
                ShareLink(item: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                        Text("export.share", bundle: .module)
                            .dsFont(.sans, .semibold, 16)
                    }
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(DS.Palette.accent))
                }
                .buttonStyle(.dsPress(radius: DS.Radius.card))
                .shadow(color: DS.Palette.accent(0.34), radius: 20, y: 14)
            }

            HStack(spacing: 9) {
                if model.destination == .photos, let photos = URL(string: "photos-redirect://") {
                    Link(destination: photos) {
                        Text("export.openPhotos", bundle: .module)
                            .dsFont(.sans, .semibold, 14)
                            .foregroundStyle(DS.Palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .dsGlass(tint: DS.Palette.glass(0.6), in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    }
                }
                DSSecondaryButton(String(localized: "export.done", bundle: .module), verticalPadding: 15, fontSize: 14, action: onDone)
            }
            .padding(.top, 10)
        }
        .dsEnter(.rise(duration: 0.45))
    }
}

extension ExportScreen {
    @ViewBuilder
    fileprivate var destinationLine: some View {
        let (symbol, key, color): (String, LocalizedStringKey, Color) = switch model.destination {
        case .photos: ("checkmark.circle.fill", "export.savedToPhotos", DS.Palette.lime)
        case .photosRefused: ("exclamationmark.triangle.fill", "export.photosRefused", DS.Palette.accent)
        default: ("doc.fill", "export.fileReady", DS.Palette.ink(0.7))
        }
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .symbolEffect(.bounce, value: model.destination)
            Text(key, bundle: .module)
                .dsFont(.sans, .medium, 13, lineHeight: 1.4)
                .foregroundStyle(DS.Palette.ink(0.75))
        }
    }
}

/// The active stage's badge pulses; the others hold still.
private struct PulseIfActive: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.dsPulse(duration: 1.2)
        } else {
            content
        }
    }
}
