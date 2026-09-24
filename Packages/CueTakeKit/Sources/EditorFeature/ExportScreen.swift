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
    /// Where the video is going. Empty renders the project as it is; otherwise one file per
    /// platform, each fitted to it.
    public var platforms: [SocialPlatform] = []
    /// The platform being rendered, and which of how many, while a batch runs.
    public private(set) var batch: (index: Int, total: Int, platform: SocialPlatform)?
    /// The platforms rendered so far in this batch, and their files.
    public private(set) var finishedPlatforms: [SocialPlatform] = []
    public private(set) var batchFiles: [URL] = []

    /// The post kit for the finished video: asked for from the finished screen.
    public enum PostKitState: Equatable, Sendable {
        case idle
        case loading
        case ready(PostKit)
        case failed(String)
    }
    public var postKitState: PostKitState = .idle
    /// Whether the cover image was saved, said under its button.
    public var coverSaved: Bool?

    public init() {}

    public func togglePlatform(_ platform: SocialPlatform) {
        if let index = platforms.firstIndex(of: platform) {
            platforms.remove(at: index)
        } else {
            platforms.append(platform)
        }
    }

    public func startBatch() {
        finishedPlatforms = []
        batchFiles = []
    }

    public func setBatch(_ index: Int, of total: Int, platform: SocialPlatform) {
        batch = (index, total, platform)
    }

    public func finishBatchItem(_ platform: SocialPlatform) {
        finishedPlatforms.append(platform)
        if let outputURL { batchFiles.append(outputURL) }
    }

    public func endBatch() {
        batch = nil
    }

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
        postKitState = .idle
        coverSaved = nil
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
    /// What is worth saying before rendering for a platform: too long, footage of another shape.
    private let warnings: (SocialPlatform) -> [SocialPlatform.Warning]
    private let onRender: () -> Void
    private let onBack: () -> Void
    private let onDone: () -> Void
    /// Makes the post kit; nil hides the button.
    private let onPostKit: (() -> Void)?
    /// Saves a cover image with this line on it to Photos.
    private let onSaveCover: ((String) -> Void)?
    @State private var showsPostKit = false

    public init(
        model: ExportModel,
        format: Binding<VideoFormat>,
        captionStyleName: String = "pop",
        warnings: @escaping (SocialPlatform) -> [SocialPlatform.Warning] = { _ in [] },
        onRender: @escaping () -> Void,
        onBack: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onPostKit: (() -> Void)? = nil,
        onSaveCover: ((String) -> Void)? = nil
    ) {
        self.onPostKit = onPostKit
        self.onSaveCover = onSaveCover
        self.model = model
        self._format = format
        self.captionStyleName = captionStyleName
        self.warnings = warnings
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
            Stage(titleKey: "export.stage.timeline", note: AppLocalization.string("export.stage.timeline.note", bundle: .module)),
            Stage(titleKey: "export.stage.render", note: AppLocalization.string("export.stage.render.note", bundle: .module)),
            Stage(titleKey: "export.stage.captions", note: AppLocalization.string("export.stage.captions.note \(captionStyleName)", bundle: .module)),
            Stage(titleKey: "export.stage.final", note: AppLocalization.string("export.stage.final.note", bundle: .module)),
        ]
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            if model.isIdle {
                platformPicker
                    .padding(.top, 14)
                formatPicker
                    .padding(.top, 14)
            } else if let batch = model.batch {
                Text("export.platform.batch \(batch.index + 1) \(batch.total) \(Self.platformName(batch.platform))", bundle: .module)
                    .dsFont(.mono, .medium, 11)
                    .foregroundStyle(DS.Palette.lime)
                    .padding(.top, 12)
                    .contentTransition(.numericText())
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
                    model.platforms.count > 1 && !model.hasFailed
                        ? AppLocalization.string("export.render.platforms \(model.platforms.count)", bundle: .module)
                        : AppLocalization.string(model.hasFailed ? "export.retry" : "export.render", bundle: .module),
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
        .onAppear {
            let compatible = format.deliveryCompatible
            if compatible != format { format = compatible }
        }
        .sheet(isPresented: $showsPostKit) {
            PostKitSheet(model: model, onRetry: { onPostKit?() }, onSaveCover: onSaveCover)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack {
            DSBackButton(size: 34, fontSize: 15, action: onBack)
            Spacer(minLength: 0)
            DSKicker(AppLocalization.string("export.kicker", bundle: .module))
            Spacer(minLength: 0)
            Color.clear.frame(width: 34, height: 34)
        }
    }

    // MARK: - Platforms

    /// Where it is going, as the shape it will be: tap one or several. Each gets its own file,
    /// cut to its shape, with captions and titles moved out from under its buttons.
    private var platformPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DSKicker(AppLocalization.string("export.platform", bundle: .module), size: 10, color: DS.Palette.ink(0.52))
                Spacer(minLength: 0)
                if !model.platforms.isEmpty {
                    Button {
                        withAnimation(DS.Motion.snap) { model.platforms = [] }
                    } label: {
                        Text("export.platform.asIs", bundle: .module)
                            .dsFont(.sans, .medium, 11)
                            .foregroundStyle(DS.Palette.ink(0.6))
                    }
                    .buttonStyle(.dsPress(radius: 8))
                }
            }

            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(SocialPlatform.allCases) { platform in
                        platformCard(platform)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

            let notes = model.platforms.flatMap { platform in warnings(platform).map { (platform, $0) } }
            if model.platforms.isEmpty {
                Text("export.platform.hint", bundle: .module)
                    .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.ink(0.5))
            } else {
                Text("export.platform.fitted", bundle: .module)
                    .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.ink(0.56))
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    Label(Self.warningText(note.1, platform: note.0), systemImage: "exclamationmark.triangle.fill")
                        .dsFont(.sans, .medium, 11)
                        .foregroundStyle(DS.Palette.accentWarm)
                }
            }
        }
        .animation(DS.Motion.snap, value: model.platforms)
    }

    private func platformCard(_ platform: SocialPlatform) -> some View {
        let isOn = model.platforms.contains(platform)
        let size = platform.aspectRatio == .landscape16x9 ? CGSize(width: 64, height: 36)
            : platform.aspectRatio == .square1x1 ? CGSize(width: 44, height: 44)
            : platform.aspectRatio == .portrait4x5 ? CGSize(width: 40, height: 50)
            : CGSize(width: 32, height: 57)
        let zone = platform.safeArea
        return Button {
            withAnimation(DS.Motion.snap) { model.togglePlatform(platform) }
        } label: {
            VStack(spacing: 7) {
                // The frame's shape, with the platform's own buttons shaded where they cover it.
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn ? DS.Palette.lime.opacity(0.22) : DS.Palette.hairline(0.07))
                    VStack(spacing: 0) {
                        Rectangle().fill(DS.Palette.ink(0.12)).frame(height: size.height * zone.top)
                        Spacer(minLength: 0)
                        Rectangle().fill(DS.Palette.ink(0.12)).frame(height: size.height * zone.bottom)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(isOn ? DS.Palette.lime : DS.Palette.hairline(0.2), lineWidth: isOn ? 2 : 1)
                }
                .frame(width: size.width, height: size.height)
                .frame(height: 60, alignment: .bottom)

                VStack(spacing: 1) {
                    Text(verbatim: Self.platformName(platform))
                        .dsFont(.sans, .semibold, 11)
                        .foregroundStyle(isOn ? DS.Palette.ink : DS.Palette.ink(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: Self.ratio(platform.aspectRatio))
                        .dsFont(.mono, .medium, 9)
                        .foregroundStyle(DS.Palette.ink(0.45))
                }
            }
            .frame(width: 78)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? DS.Palette.hairline(0.1) : Color.clear)
            )
        }
        .buttonStyle(.dsPress(radius: 14))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    static func platformName(_ platform: SocialPlatform) -> String {
        AppLocalization.string(String.LocalizationValue(stringLiteral: "export.platform." + platform.rawValue), bundle: .module)
    }

    static func ratio(_ aspect: VideoFormat.AspectRatio) -> String {
        switch aspect {
        case .portrait9x16: "9:16"
        case .landscape16x9: "16:9"
        case .square1x1: "1:1"
        case .portrait4x5: "4:5"
        }
    }

    static func warningText(_ warning: SocialPlatform.Warning, platform: SocialPlatform) -> String {
        let name = platformName(platform)
        switch warning {
        case .tooLong(let maximum, let over):
            return AppLocalization.string("export.platform.tooLong \(name) \(Int(maximum)) \(Int(over.rounded(.up)))", bundle: .module)
        case .letterboxed:
            return AppLocalization.string("export.platform.letterboxed \(name)", bundle: .module)
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
                DSKicker(AppLocalization.string("export.format", bundle: .module), size: 10, color: DS.Palette.ink(0.52))
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
                        // Keep the pair inside the tested delivery envelope.
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
    /// point of showing it is to make the storage cost clear before it fills a phone.
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
                Text(AppLocalization.string(stage.titleKey, bundle: .module))
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
            DSHeadline(AppLocalization.string("export.ready", bundle: .module), size: 28)
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
                .padding(.bottom, model.finishedPlatforms.isEmpty ? 14 : 6)

            if !model.finishedPlatforms.isEmpty {
                Text(verbatim: model.finishedPlatforms.map { Self.platformName($0) }.joined(separator: " · "))
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.lime)
                    .padding(.bottom, 14)
            }

            if model.batchFiles.count > 1 {
                ShareLink(items: model.batchFiles) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up.on.square")
                            .font(.system(size: 15, weight: .semibold))
                        Text("export.share.all \(model.batchFiles.count)", bundle: .module)
                            .dsFont(.sans, .semibold, 16)
                    }
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(DS.Palette.accent))
                }
            } else if let url = model.outputURL {
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

            if onPostKit != nil {
                Button {
                    switch model.postKitState {
                    case .idle, .failed: onPostKit?()
                    case .loading, .ready: break
                    }
                    showsPostKit = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("export.postKit", bundle: .module)
                            .dsFont(.sans, .semibold, 15)
                        Spacer(minLength: 0)
                        Text("export.postKit.detail", bundle: .module)
                            .dsFont(.sans, .regular, 11)
                            .foregroundStyle(DS.Palette.ink(0.5))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DS.Palette.ink(0.4))
                    }
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(DS.Palette.lime(0.1)))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .strokeBorder(DS.Palette.lime(0.35), lineWidth: 1)
                    }
                }
                .buttonStyle(.dsPress(radius: DS.Radius.card))
                .padding(.top, 10)
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
                DSSecondaryButton(AppLocalization.string("export.done", bundle: .module), verticalPadding: 15, fontSize: 14, action: onDone)
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
