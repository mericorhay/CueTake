import DesignSystem
import Domain
import SwiftUI
import UIKit

/// Everything needed to post the finished video, ready to paste: the hook's score and a stronger
/// opening, a cover line to save as the cover image, a title, and the text and hashtags for each
/// platform. Each piece copies with one tap, because the next thing the creator does is switch to
/// TikTok and paste.
struct PostKitSheet: View {
    @Bindable var model: ExportModel
    let onRetry: () -> Void
    let onSaveCover: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var platform: String?
    @State private var copied: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch model.postKitState {
                    case .idle, .loading:
                        loading
                    case .failed(let reason):
                        failed(reason)
                    case .ready(let kit):
                        hookCard(kit.hook)
                        coverCard(kit)
                        copyCard(title: AppLocalization.string("postKit.title", bundle: .module), text: kit.title, id: "title")
                        postsCard(kit)
                        if !kit.bestTime.isEmpty {
                            Label {
                                Text(verbatim: kit.bestTime)
                            } icon: {
                                Image(systemName: "clock")
                            }
                            .dsFont(.sans, .regular, 13)
                            .foregroundStyle(DS.Palette.ink(0.6))
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(DS.Palette.screen)
            .navigationTitle(Text("export.postKit", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("postKit.done", bundle: .module) }
                }
            }
        }
        .sensoryFeedback(.success, trigger: copied)
        .animation(reduceMotion ? nil : DS.Motion.settle, value: model.postKitState)
    }

    // MARK: - States

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView().tint(DS.Palette.lime)
            Text("postKit.loading", bundle: .module)
                .dsFont(.sans, .medium, 14)
                .foregroundStyle(DS.Palette.ink(0.65))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func failed(_ reason: String) -> some View {
        VStack(spacing: 14) {
            Label {
                Text(verbatim: reason)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .dsFont(.sans, .medium, 14)
            .foregroundStyle(DS.Palette.accent)
            .multilineTextAlignment(.center)
            Button(action: onRetry) {
                Text("export.retry", bundle: .module)
                    .dsFont(.sans, .semibold, 15)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 46)
                    .background(Capsule().fill(DS.Palette.ink))
            }
            .buttonStyle(.dsPress(radius: 23))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    // MARK: - Hook

    private func hookCard(_ hook: PostKit.Hook) -> some View {
        let strong = hook.score >= 8
        let color = strong ? DS.Palette.lime : hook.score >= 5 ? DS.Palette.accentWarm : DS.Palette.accent
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().stroke(DS.Palette.hairline(0.1), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(hook.score) / 10)
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(verbatim: "\(hook.score)")
                        .dsFont(.sans, .bold, 22)
                        .foregroundStyle(DS.Palette.ink)
                }
                .frame(width: 62, height: 62)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("postKit.hook.score \(hook.score)", bundle: .module))

                VStack(alignment: .leading, spacing: 4) {
                    DSKicker(AppLocalization.string("postKit.hook", bundle: .module), size: 10, color: DS.Palette.ink(0.5))
                    Text(verbatim: hook.issue.isEmpty ? AppLocalization.string("postKit.hook.strong", bundle: .module) : hook.issue)
                        .dsFont(.sans, .semibold, 15)
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !hook.better.isEmpty, !strong {
                VStack(alignment: .leading, spacing: 6) {
                    Text("postKit.hook.better", bundle: .module)
                        .dsFont(.mono, .medium, 10, letterSpacing: 0.1)
                        .foregroundStyle(DS.Palette.ink(0.5))
                    Text(verbatim: "“\(hook.better)”")
                        .dsFont(.sans, .medium, 15)
                        .foregroundStyle(DS.Palette.lime)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("postKit.hook.retake", bundle: .module)
                        .dsFont(.sans, .regular, 12)
                        .foregroundStyle(DS.Palette.ink(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(radius: DS.Radius.cardLarge)
    }

    // MARK: - Cover

    private func coverCard(_ kit: PostKit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DSKicker(AppLocalization.string("postKit.cover", bundle: .module), size: 10, color: DS.Palette.ink(0.5))
            Text(verbatim: kit.cover)
                .font(.custom("Archivo-ExtraBold", size: 26))
                .foregroundStyle(DS.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                copyButton(kit.cover, id: "cover")
                if let onSaveCover {
                    Button {
                        onSaveCover(kit.cover)
                    } label: {
                        Label {
                            Text(LocalizedStringKey(model.coverSaved == true ? "postKit.cover.saved" : "postKit.cover.save"), bundle: .module)
                        } icon: {
                            Image(systemName: model.coverSaved == true ? "checkmark" : "photo.badge.plus")
                        }
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(Capsule().fill(DS.Palette.lime))
                    }
                    .buttonStyle(.dsPress(radius: 20))
                    .disabled(model.coverSaved == true)
                }
            }
            if model.coverSaved == false {
                Text("postKit.cover.failed", bundle: .module)
                    .dsFont(.sans, .regular, 12)
                    .foregroundStyle(DS.Palette.accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(radius: DS.Radius.cardLarge)
    }

    // MARK: - Text

    private func copyCard(title: String, text: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DSKicker(title, size: 10, color: DS.Palette.ink(0.5))
                Spacer(minLength: 0)
                copyButton(text, id: id)
            }
            Text(verbatim: text)
                .dsFont(.sans, .medium, 15)
                .foregroundStyle(DS.Palette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(radius: DS.Radius.cardLarge)
    }

    private func postsCard(_ kit: PostKit) -> some View {
        let selected = kit.posts.first { $0.platform == platform } ?? kit.posts.first
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(kit.posts) { post in
                    let isOn = post.platform == selected?.platform
                    Button {
                        platform = post.platform
                    } label: {
                        Text(verbatim: Self.platformName(post.platform))
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.65))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.06)))
                    }
                    .buttonStyle(.dsPress(radius: 17))
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            if let selected {
                Text(verbatim: selected.text)
                    .dsFont(.sans, .regular, 15, lineHeight: 1.4)
                    .foregroundStyle(DS.Palette.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !selected.hashtags.isEmpty {
                    Text(verbatim: selected.hashtags.map { "#" + $0 }.joined(separator: " "))
                        .dsFont(.sans, .medium, 14)
                        .foregroundStyle(DS.Palette.lime)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                copyButton(selected.pasteable, id: "post-" + selected.platform, wide: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(radius: DS.Radius.cardLarge)
    }

    private func copyButton(_ text: String, id: String, wide: Bool = false) -> some View {
        let done = copied == id
        return Button {
            UIPasteboard.general.string = text
            copied = id
        } label: {
            Label {
                Text(LocalizedStringKey(done ? "postKit.copied" : "postKit.copy"), bundle: .module)
            } icon: {
                Image(systemName: done ? "checkmark" : "doc.on.doc")
            }
            .dsFont(.sans, .semibold, 13)
            .foregroundStyle(done ? DS.Palette.inkInverse : DS.Palette.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: 40)
            .background(Capsule().fill(done ? DS.Palette.lime : DS.Palette.hairline(0.08)))
        }
        .buttonStyle(.dsPress(radius: 20))
    }

    static func platformName(_ platform: String) -> String {
        switch platform {
        case "tiktok": "TikTok"
        case "instagram": "Instagram"
        case "youtube": "YouTube"
        case "linkedin": "LinkedIn"
        default: platform.capitalized
        }
    }
}
