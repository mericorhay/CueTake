import DesignSystem
import MediaEngine
import SwiftUI
import UniformTypeIdentifiers

/// A small format converter, kept where the other small utilities live.
///
/// It is here because of a real and very ordinary problem: someone has a file the thing they are
/// uploading to will not take. A .heic where a site wants a .jpg, a .mov where something wants an
/// .mp4, a video someone needs the sound out of. None of that is editing, so it does not belong in
/// the studio — but it is a five minute search for a sketchy website every single time, and the
/// phone can already do all of it.
struct ConverterSheet: View {
    let onClose: () -> Void

    @State private var source: URL?
    @State private var target: FileConverter.Target = .jpg
    @State private var result: URL?
    @State private var isWorking = false
    @State private var failure: String?
    @State private var isPicking = false

    private var targets: [FileConverter.Target] {
        source.map { FileConverter.targets(for: $0) } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            picker

            if let source {
                formats(for: source)
                convert
            }

            if let result {
                finished(result)
            }

            if let failure {
                Text(failure)
                    .dsFont(.sans, .regular, 12)
                    .foregroundStyle(DS.Palette.accent)
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.screen)
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.item]) { outcome in
            guard case .success(let url) = outcome else { return }
            source = url
            result = nil
            failure = nil
            target = FileConverter.targets(for: url).first ?? .jpg
        }
        .animation(DS.Motion.settle, value: source)
        .animation(DS.Motion.settle, value: result)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                DSKicker(String(localized: "converter.title", bundle: .module))
                Text("converter.note", bundle: .module)
                    .dsFont(.sans, .regular, 12, lineHeight: 1.4)
                    .foregroundStyle(DS.Palette.ink(0.56))
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .dsActionName("xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Palette.ink(0.6))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Palette.hairline(0.08)))
            }
            .buttonStyle(.dsPressIcon)
        }
        .padding(.bottom, 18)
    }

    private var picker: some View {
        Button {
            isPicking = true
        } label: {
            HStack(spacing: 11) {
                Image(systemName: source == nil ? "doc.badge.plus" : "doc")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.Palette.lime)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source?.lastPathComponent ?? String(localized: "converter.pick", bundle: .module))
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("converter.pick.note", bundle: .module)
                        .dsFont(.sans, .regular, 11)
                        .foregroundStyle(DS.Palette.ink(0.52))
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard(radius: DS.Radius.card, border: DS.Palette.hairline(0.09))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: DS.Radius.card))
    }

    private func formats(for source: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("converter.to", bundle: .module)
                .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.52))

            HStack(spacing: 6) {
                ForEach(targets, id: \.self) { option in
                    let isOn = target == option
                    Button {
                        target = option
                        result = nil
                    } label: {
                        Text(option.label)
                            .dsFont(.mono, .medium, 12)
                            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07))
                            )
                    }
                    .buttonStyle(.dsPress(radius: 12))
                }
            }

            // Said once, here, where it saves someone a pointless conversion.
            if source.pathExtension.lowercased() == "jpeg", target == .jpg {
                Text("converter.jpegNote", bundle: .module)
                    .dsFont(.sans, .regular, 11, lineHeight: 1.4)
                    .foregroundStyle(DS.Palette.ink(0.56))
            }
        }
        .padding(.top, 18)
    }

    private var convert: some View {
        DSPrimaryButton(
            String(localized: isWorking ? "converter.working" : "converter.run", bundle: .module),
            radius: DS.Radius.cardLarge,
            verticalPadding: 17,
            fontSize: 15
        ) {
            guard let source, !isWorking else { return }
            isWorking = true
            failure = nil
            let chosen = target
            Task {
                do {
                    result = try await FileConverter().convert(
                        source,
                        to: chosen,
                        in: FileManager.default.temporaryDirectory.appending(
                            path: "converted",
                            directoryHint: .isDirectory
                        )
                    )
                } catch {
                    failure = String(localized: "converter.failed", bundle: .module)
                }
                isWorking = false
            }
        }
        .padding(.top, 18)
        .disabled(isWorking)
    }

    /// The converted file is handed over through the share sheet rather than dropped somewhere.
    ///
    /// A file written into the app's own container is a file the user cannot reach; sharing is
    /// where they say what it was for — save it to Files, send it, upload it.
    private func finished(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(DS.Palette.lime)
                Text(url.lastPathComponent)
                    .dsFont(.sans, .semibold, 13)
                    .foregroundStyle(DS.Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            ShareLink(item: url) {
                Text("converter.share", bundle: .module)
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(DS.Palette.ink)
                    )
            }
        }
        .padding(.top, 18)
        .dsEnter(.rise(duration: 0.35))
    }
}
