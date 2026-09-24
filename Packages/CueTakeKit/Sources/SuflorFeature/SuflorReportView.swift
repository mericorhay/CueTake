import CoreTransferable
import DesignSystem
import Domain
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// After the stage: the page the brand will get, shown as the hero, and what is needed to send it.
///
/// Without listening during the stream there are two kinds of evidence. What the speaker ticked
/// on stage, with the second they did; and — stronger — the saved recording of the stream,
/// listened to on this phone, with the second and the sentence each item was said in and a frame
/// from that moment. The page says which kind each line is.
struct SuflorReportView: View {
    @Bindable var model: SuflorModel
    let onClose: () -> Void

    @State private var pickedRecording: PhotosPickerItem?
    @State private var files: SuflorReportFiles?
    @State private var language = SuflorReportLanguage.preferred
    @State private var shown = false
    @State private var zoomed = false
    @FocusState private var editingName: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct RenderKey: Hashable {
        var session: SuflorSession?
        var language: SuflorReportLanguage
    }

    var body: some View {
        ScrollView {
            if model.session == nil {
                reading
            }
            if let session = model.session {
                VStack(alignment: .leading, spacing: 0) {
                    header(session)
                    hero.padding(.top, 22)
                    languagePicker.padding(.top, 24)
                    nameField.padding(.top, 20)
                    proofCard(session).padding(.top, 20)
                    actions.padding(.top, 24)
                }
                .padding(.horizontal, 22)
                .padding(.top, 64)
                .padding(.bottom, 40)
                .blur(radius: model.reportLocked ? 16 : 0)
                .allowsHitTesting(!model.reportLocked)
                .accessibilityHidden(model.reportLocked)
            }
        }
        .scrollDisabled(model.reportLocked && model.session != nil)
        .overlay {
            if model.reportLocked, model.session != nil {
                ReportLock(onUnlock: { model.onUnlockReport?() }, onClose: onClose)
                    .transition(.opacity)
            }
        }
        .animation(DS.Motion.settle, value: model.reportLocked)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.screen)
        // The page tilts up into place once there is a page: a studio take is read first.
        .onAppear { if model.session != nil { reveal() } }
        .onChange(of: model.session != nil) { _, hasPage in
            if hasPage { reveal() } else { shown = false }
        }
        .task(id: RenderKey(session: model.session, language: language)) { await renderFiles() }
        .fullScreenCover(isPresented: $zoomed) {
            if let files {
                ZoomedPage(image: files.thumbnail) { zoomed = false }
            }
        }
        .onChange(of: pickedRecording) { _, item in
            guard let item else { return }
            pickedRecording = nil
            Task {
                guard let movie = try? await item.loadTransferable(type: SuflorMovie.self) else {
                    model.verifyError = AppLocalization.string("suflor.verify.failed", bundle: .module)
                    return
                }
                await model.verify(recording: movie.url)
                try? FileManager.default.removeItem(at: movie.url)
            }
        }
    }

    // MARK: - Header

    private func header(_ session: SuflorSession) -> some View {
        let items = session.plan.brief.mustSay
        let delivered = items.filter { session.evidence(for: $0) != .missing }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                DSKicker(AppLocalization.string("suflor.report.kicker \(session.reportID)", bundle: .module), size: 11, tracking: 0.16)
                Spacer(minLength: 0)
                DSCircleButton("✕", size: 44, fontSize: 15) { onClose() }
                    .accessibilityLabel(Text("suflor.report.close", bundle: .module))
            }
            DSHeadline(AppLocalization.string("suflor.report.title", bundle: .module), size: 34)
                .padding(.top, 10)
            HStack(spacing: 8) {
                if !items.isEmpty {
                    summaryChip(
                        AppLocalization.string("suflor.report.summary.items \(delivered) \(items.count)", bundle: .module),
                        tint: delivered == items.count ? DS.Palette.lime : DS.Palette.amber
                    )
                }
                if let ad = session.adDuration {
                    summaryChip(AppLocalization.string("suflor.report.summary.ad \(SuflorSession.clock(ad))", bundle: .module), tint: DS.Palette.accent)
                }
            }
            .padding(.top, 12)
        }
    }

    private func summaryChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .dsFont(.mono, .medium, 11, letterSpacing: 0.08)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    // MARK: - The page

    /// The page itself, as the brand will see it: it tilts up into place, and a tap opens it large.
    private var hero: some View {
        Button {
            if files != nil { zoomed = true }
        } label: {
            ZStack {
                if let files {
                    Image(uiImage: files.thumbnail)
                        .resizable()
                        .scaledToFit()
                        .transition(.opacity)
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.92))
                        .aspectRatio(SuflorReportFiles.pageSize.width / SuflorReportFiles.pageSize.height, contentMode: .fit)
                        .overlay(ProgressView().tint(DS.Palette.inkInverse))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 36, height: 36)
                    .dsGlass(tint: DS.Palette.glass(0.7), in: Circle())
                    .padding(10)
            }
            .shadow(color: .black.opacity(0.55), radius: 30, y: 22)
            .background {
                RadialGradient(colors: [DS.Palette.lime(0.18), .clear], center: .center, startRadius: 10, endRadius: 260)
                    .blur(radius: 20)
            }
        }
        .buttonStyle(.dsPressCard)
        .padding(.horizontal, 26)
        .rotation3DEffect(.degrees(shown ? 0 : 24), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
        .scaleEffect(shown ? 1 : 0.88)
        .opacity(shown ? 1 : 0)
        .animation(DS.Motion.settle, value: files?.pdf)
        .accessibilityLabel(Text("suflor.report.preview", bundle: .module))
    }

    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSKicker(AppLocalization.string("suflor.report.language", bundle: .module))
            HStack(spacing: 8) {
                ForEach(SuflorReportLanguage.allCases) { option in
                    SuflorChip(title: option.name, isOn: language == option) {
                        withAnimation(DS.Motion.snap) { language = option }
                    }
                }
            }
        }
    }

    // MARK: - Name

    private var nameMissing: Bool {
        model.creator.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var nameBorder: Color {
        if editingName { return DS.Palette.lime(0.6) }
        return nameMissing ? DS.Palette.amber.opacity(0.6) : DS.Palette.hairline(0.07)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                DSKicker(AppLocalization.string("suflor.report.creator", bundle: .module))
                Text("suflor.report.required", bundle: .module)
                    .dsFont(.mono, .medium, 9, letterSpacing: 0.12)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(nameMissing ? DS.Palette.amber : DS.Palette.lime))
            }
            TextField(AppLocalization.string("suflor.report.creator.placeholder", bundle: .module), text: $model.creator)
                .focused($editingName)
                .dsFont(.sans, .semibold, 16)
                .foregroundStyle(DS.Palette.ink)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .onTapGesture { editingName = true }
                .dsCard(radius: 16, border: nameBorder)
            if nameMissing {
                Text("suflor.report.creator.needed", bundle: .module)
                    .dsFont(.sans, .regular, 12)
                    .foregroundStyle(DS.Palette.amber)
                    .transition(.opacity)
            }
        }
        .animation(DS.Motion.snap, value: nameMissing)
    }

    private func reveal() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.9, dampingFraction: 0.78).delay(0.1)) {
            shown = true
        }
    }

    /// While a studio take is read, or when it could not be.
    private var reading: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer(minLength: 0)
                DSCircleButton("✕", size: 44, fontSize: 15) { onClose() }
                    .accessibilityLabel(Text("suflor.report.close", bundle: .module))
            }
            Spacer(minLength: 120)
            if model.isVerifying {
                Image(systemName: "waveform.and.magnifyingglass")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(DS.Palette.lime)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                Text("suflor.report.take.listening", bundle: .module)
                    .dsFont(.sans, .semibold, 16)
                    .foregroundStyle(DS.Palette.ink)
            } else if let error = model.verifyError {
                Text(error)
                    .dsFont(.sans, .medium, 15, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.amber)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await model.readTake() }
                } label: {
                    Text("suflor.report.take.again", bundle: .module)
                        .dsFont(.sans, .semibold, 15)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 48)
                        .background(Capsule().fill(DS.Palette.lime))
                }
                .buttonStyle(.dsPress)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.top, 64)
    }

    // MARK: - Proof

    private func proofCard(_ session: SuflorSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.and.magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.Palette.lime)
                    .symbolEffect(.variableColor.iterative, isActive: model.isVerifying)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(DS.Palette.lime(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Group {
                        if model.reportSource == .take {
                            Text("suflor.report.take.title", bundle: .module)
                        } else {
                            Text("suflor.report.proof.title", bundle: .module)
                        }
                    }
                    .dsFont(.sans, .semibold, 16)
                    .foregroundStyle(DS.Palette.ink)
                    Group {
                        if model.reportSource == .take {
                            Text("suflor.report.take.detail", bundle: .module)
                        } else {
                            Text("suflor.report.proof.detail", bundle: .module)
                        }
                    }
                    .dsFont(.sans, .regular, 13, lineHeight: 1.3)
                    .foregroundStyle(DS.Palette.ink(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let error = model.verifyError {
                Text(error)
                    .dsFont(.sans, .medium, 13)
                    .foregroundStyle(DS.Palette.amber)
            }
            if !session.proofs.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(session.proofs) { proof in
                            ProofTile(proof: proof)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            if model.reportSource == .take {
                // The take is ours and already heard: listening again is one tap, no picking.
                Button {
                    Task { await model.readTake() }
                } label: {
                    HStack(spacing: 8) {
                        if model.isVerifying {
                            ProgressView().tint(DS.Palette.ink)
                            Text("suflor.report.take.listening", bundle: .module)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("suflor.report.take.again", bundle: .module)
                        }
                    }
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.ink(0.8))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Capsule().fill(DS.Palette.hairline(0.08)))
                }
                .buttonStyle(.dsPress)
                .disabled(model.isVerifying)
            } else if model.verifier != nil {
                let isVerifying = model.isVerifying
                let hasProofs = !session.proofs.isEmpty
                PhotosPicker(selection: $pickedRecording, matching: .videos) {
                    RecordingPickerLabel(isVerifying: isVerifying, hasProofs: hasProofs)
                }
                .disabled(model.isVerifying)
            }
        }
        .padding(16)
        .dsCard(radius: 22)
    }

    // MARK: - Sending

    private var actions: some View {
        VStack(spacing: 12) {
            if let files {
                ShareLink(item: files.pdf, preview: SharePreview(Text("suflor.report.share.pdfTitle", bundle: .module), image: Image(uiImage: files.thumbnail))) {
                    HStack(spacing: 10) {
                        Image(systemName: "paperplane.fill")
                        Text("suflor.report.share.pdf", bundle: .module)
                    }
                    .dsFont(.sans, .semibold, 16)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background {
                        ZStack {
                            DS.gradient(150, [DS.Palette.accent, DS.Palette.accentWarm])
                            if !nameMissing { SweepShine() }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .shadow(color: DS.Palette.accent(nameMissing ? 0 : 0.35), radius: 22, y: 12)
                }
                .disabled(nameMissing)
                .opacity(nameMissing ? 0.4 : 1)
                ShareLink(item: files.image, preview: SharePreview(Text("suflor.report.share.imageTitle", bundle: .module), image: Image(uiImage: files.thumbnail))) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo")
                        Text("suflor.report.share.image", bundle: .module)
                    }
                    .dsFont(.sans, .semibold, 15)
                    .foregroundStyle(DS.Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .dsCard(radius: DS.Radius.card)
                }
                .disabled(nameMissing)
                .opacity(nameMissing ? 0.4 : 1)
            }
            Button {
                model.leaveReport()
            } label: {
                Text("suflor.report.again", bundle: .module)
                    .dsFont(.sans, .medium, 14)
                    .foregroundStyle(DS.Palette.ink(0.66))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.dsPress)
        }
        .animation(DS.Motion.snap, value: nameMissing)
    }

    private func renderFiles() async {
        guard let session = model.session else { return }
        // A moment's pause lets typing in the name settle before the page is drawn again.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        let made = SuflorReportFiles.make(for: session, language: language)
        withAnimation(DS.Motion.settle) { files = made }
    }
}

/// The page full screen, to read every line before sending it.
private struct ZoomedPage: View {
    let image: UIImage
    let onClose: () -> Void
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DS.Palette.page.ignoresSafeArea()
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 380 * scale)
                    .padding(.vertical, 90)
                    .padding(.horizontal, 12)
            }
            .simultaneousGesture(MagnifyGesture().onChanged { value in scale = min(3, max(1, value.magnification)) })
            DSCircleButton("✕", size: 44, fontSize: 15, style: .glass, action: onClose)
                .padding(.top, 58)
                .padding(.trailing, 18)
                .accessibilityLabel(Text("suflor.report.close", bundle: .module))
        }
    }
}

private struct ProofTile: View {
    let proof: SuflorProof

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let data = proof.frame, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    DS.Palette.camera
                }
            }
            .frame(width: 120, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(SuflorSession.clock(proof.seconds))
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(DS.Palette.lime))
                    .padding(6)
            }
            Text(proof.item)
                .dsFont(.sans, .semibold, 12)
                .foregroundStyle(DS.Palette.ink(0.8))
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The picker's label. Nonisolated because PhotosPicker builds its label off the main actor;
/// the body is still drawn on it.
private nonisolated struct RecordingPickerLabel: View {
    let isVerifying: Bool
    let hasProofs: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isVerifying {
                ProgressView().tint(DS.Palette.inkInverse)
                Text("suflor.report.proof.listening", bundle: .module)
            } else if !hasProofs {
                Image(systemName: "plus")
                Text("suflor.report.proof.add", bundle: .module)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("suflor.report.proof.again", bundle: .module)
            }
        }
        .dsFont(.sans, .semibold, 15)
        .foregroundStyle(DS.Palette.inkInverse)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Capsule().fill(DS.Palette.lime))
    }
}

/// A video picked from Photos, copied where it can be read.
nonisolated struct SuflorMovie: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appending(path: "suflor-\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return SuflorMovie(url: copy)
        }
    }
}
