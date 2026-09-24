import DesignSystem
import Domain
import SwiftUI

/// What the last run made, and what it could not do.
///
/// A run used to end with one line in the run bar — "6 done, 2 skipped" — and the reasons hidden
/// in the subtitles of cards further down. This says it at the top: the video, where it went, what
/// the API answered, and each step that was skipped with why.
struct StudioRunResultCard: View {
    @Bindable var model: WorkflowStudioModel
    let summary: StudioRunSummary
    let onOpen: () -> Void
    let onResend: () -> Void
    let onDismiss: () -> Void
    /// The post kit for the video the run wrote; nil hides the button.
    var onPostKit: (() -> Void)? = nil

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: summary.video != nil ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(summary.video != nil ? DS.Palette.lime : DS.Palette.accentWarm)
                    .symbolEffect(.bounce, value: shown)
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.video != nil ? "studio.result.ready" : "studio.result.noVideo", bundle: .module)
                        .dsFont(.archivo, .bold, 16)
                        .foregroundStyle(DS.Palette.ink)
                    Text("studio.run.result \(summary.completed) \(summary.skipped)", bundle: .module)
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.56))
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Palette.ink(0.55))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(DS.Palette.hairline(0.08)))
                }
                .buttonStyle(.dsPressIcon)
                .accessibilityLabel(Text("studio.result.dismiss", bundle: .module))
            }

            if let delivery = summary.delivery {
                deliveryLine(delivery)
            }

            let skipped = model.skippedReasons
            if !skipped.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(skipped.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DS.Palette.accentWarm)
                            Text(AppLocalization.string(StudioCatalog.tool(for: item.title).title, bundle: .module))
                                .dsFont(.sans, .semibold, 11)
                                .foregroundStyle(DS.Palette.ink(0.8))
                            Text(item.reason)
                                .dsFont(.sans, .regular, 11)
                                .foregroundStyle(DS.Palette.ink(0.5))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .opacity(shown ? 1 : 0)
                        .offset(y: shown || reduceMotion ? 0 : 6)
                        .animation(reduceMotion ? nil : DS.Motion.settle.delay(0.05 * Double(index)), value: shown)
                    }
                }
            }

            HStack(spacing: 8) {
                if let video = summary.video {
                    ShareLink(item: video) {
                        Label(AppLocalization.string("studio.result.share", bundle: .module), systemImage: "square.and.arrow.up")
                            .dsFont(.sans, .semibold, 13)
                            .foregroundStyle(DS.Palette.inkInverse)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(Capsule().fill(DS.Palette.accent))
                    }
                    .buttonStyle(.dsPress(radius: 21))
                }
                Button(action: onOpen) {
                    Label(AppLocalization.string("studio.result.open", bundle: .module), systemImage: "slider.horizontal.below.rectangle")
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Capsule().fill(DS.Palette.hairline(0.1)))
                }
                .buttonStyle(.dsPress(radius: 21))
            }
            if summary.video != nil, let onPostKit {
                Button(action: onPostKit) {
                    Label(AppLocalization.string("studio.result.postKit", bundle: .module), systemImage: "text.bubble.fill")
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Capsule().fill(DS.Palette.lime))
                }
                .buttonStyle(.dsPress(radius: 21))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS.Palette.hairline(0.06)))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(summary.video != nil ? DS.Palette.lime(0.4) : DS.Palette.accentWarm.opacity(0.4), lineWidth: 1)
        }
        .onAppear { shown = true }
    }

    @ViewBuilder
    private func deliveryLine(_ delivery: StudioDeliveryResult) -> some View {
        HStack(spacing: 8) {
            switch delivery {
            case .sending:
                ProgressView().controlSize(.small)
                Text("studio.delivery.sending", bundle: .module)
                    .foregroundStyle(DS.Palette.ink(0.7))
            case .sent(let status):
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(DS.Palette.lime)
                    .symbolEffect(.bounce.up, value: status)
                Text("studio.delivery.ok \(status)", bundle: .module)
                    .foregroundStyle(DS.Palette.ink(0.8))
            case .failed(let reason):
                Image(systemName: "paperplane")
                    .foregroundStyle(DS.Palette.accent)
                Text(reason)
                    .foregroundStyle(DS.Palette.accent)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if summary.video != nil {
                    Button(action: onResend) {
                        Text("studio.delivery.resend", bundle: .module)
                            .dsFont(.sans, .semibold, 11)
                            .foregroundStyle(DS.Palette.inkInverse)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Capsule().fill(DS.Palette.ink))
                    }
                    .buttonStyle(.dsPress(radius: 15))
                }
            }
        }
        .dsFont(.sans, .medium, 12)
        .transition(.blurReplace)
        .animation(DS.Motion.snap, value: delivery)
    }
}
