import CoreTransferable
import DesignSystem
import Domain
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// After the stage: what happened, in a form the brand can be sent.
///
/// Without listening during the stream there are two kinds of evidence. What the speaker ticked
/// on stage, with the second they did; and — stronger — the saved recording of the stream,
/// listened to on this phone, with the second and the sentence each item was said in and a frame
/// from that moment. The PDF says which kind each line is.
struct SuflorReportView: View {
    @Bindable var model: SuflorModel
    let onClose: () -> Void

    @State private var pickedRecording: PhotosPickerItem?
    @State private var files: SuflorReportFiles?
    @State private var shown = false
    @FocusState private var editingName: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            if let session = model.session {
                VStack(alignment: .leading, spacing: 0) {
                    header(session)
                    stats(session).padding(.top, 24)
                    checklist(session).padding(.top, 28)
                    proofCard(session).padding(.top, 20)
                    nameField.padding(.top, 20)
                    actions(session).padding(.top, 26)
                }
                .padding(.horizontal, 22)
                .padding(.top, 64)
                .padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.screen)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DS.Motion.settle.delay(0.15)) { shown = true }
        }
        .task(id: model.session) { await renderFiles() }
        .onChange(of: pickedRecording) { _, item in
            guard let item else { return }
            pickedRecording = nil
            Task {
                guard let movie = try? await item.loadTransferable(type: SuflorMovie.self) else {
                    model.verifyError = String(localized: "suflor.verify.failed", bundle: .module)
                    return
                }
                await model.verify(recording: movie.url)
                try? FileManager.default.removeItem(at: movie.url)
            }
        }
    }

    // MARK: - Pieces

    private func header(_ session: SuflorSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                DSKicker(String(localized: "suflor.report.kicker \(session.reportID)", bundle: .module), size: 11, tracking: 0.16)
                Spacer(minLength: 0)
                DSCircleButton("✕", size: 44, fontSize: 15) { onClose() }
                    .accessibilityLabel(Text("suflor.report.close", bundle: .module))
            }
            DSHeadline(String(localized: "suflor.report.title", bundle: .module), size: 34)
                .padding(.top, 10)
            Text(session.plan.brief.brand.isEmpty ? session.plan.brief.product : "\(session.plan.brief.brand) · \(session.plan.brief.product)")
                .dsFont(.sans, .medium, 15)
                .foregroundStyle(DS.Palette.ink(0.66))
                .padding(.top, 8)
        }
    }

    private func stats(_ session: SuflorSession) -> some View {
        HStack(spacing: 10) {
            stat(value: SuflorSession.clock(session.duration), label: String(localized: "suflor.report.stat.length", bundle: .module), tint: DS.Palette.ink)
            stat(value: session.adStartedAt.map { SuflorSession.clock($0) } ?? "—", label: String(localized: "suflor.report.stat.adAt", bundle: .module), tint: DS.Palette.amber)
            stat(value: session.adDuration.map { SuflorSession.clock($0) } ?? "—", label: String(localized: "suflor.report.stat.adLength", bundle: .module), tint: DS.Palette.accent)
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 16)
    }

    private func stat(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .dsFont(.archivo, .extrabold, 24)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.56))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .dsCard(radius: 18)
        .accessibilityElement(children: .combine)
    }

    private func checklist(_ session: SuflorSession) -> some View {
        let items = session.plan.brief.mustSay
        return VStack(alignment: .leading, spacing: 10) {
            DSKicker(String(localized: "suflor.report.said", bundle: .module))
            if items.isEmpty {
                Text("suflor.report.said.none", bundle: .module)
                    .dsFont(.sans, .regular, 14)
                    .foregroundStyle(DS.Palette.ink(0.56))
            }
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                EvidenceRow(item: item, evidence: session.evidence(for: item), shown: shown)
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : DS.Motion.bloom.delay(0.25 + Double(index) * 0.12), value: shown)
            }
        }
    }

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
                    Text("suflor.report.proof.title", bundle: .module)
                        .dsFont(.sans, .semibold, 16)
                        .foregroundStyle(DS.Palette.ink)
                    Text("suflor.report.proof.detail", bundle: .module)
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
            if model.verifier != nil {
                PhotosPicker(selection: $pickedRecording, matching: .videos) {
                    HStack(spacing: 8) {
                        if model.isVerifying {
                            ProgressView().tint(DS.Palette.inkInverse)
                            Text("suflor.report.proof.listening", bundle: .module)
                        } else if session.proofs.isEmpty {
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
                .disabled(model.isVerifying)
            }
        }
        .padding(16)
        .dsCard(radius: 22)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSKicker(String(localized: "suflor.report.creator", bundle: .module))
            TextField(String(localized: "suflor.report.creator.placeholder", bundle: .module), text: $model.creator)
                .focused($editingName)
                .dsFont(.sans, .semibold, 16)
                .foregroundStyle(DS.Palette.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .dsCard(radius: 16, border: editingName ? DS.Palette.lime(0.6) : DS.Palette.hairline(0.07))
                .submitLabel(.done)
        }
    }

    private func actions(_ session: SuflorSession) -> some View {
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
                            SweepShine()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .shadow(color: DS.Palette.accent(0.35), radius: 22, y: 12)
                }
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
            } else {
                ProgressView().tint(DS.Palette.ink).frame(minHeight: 56)
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
    }

    private func renderFiles() async {
        guard let session = model.session else { return }
        // A moment's pause lets typing in the name settle before the page is drawn again.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        files = SuflorReportFiles.make(for: session)
    }
}

/// One item the brand asked for, with how we know.
private struct EvidenceRow: View {
    let item: String
    let evidence: SuflorSession.Evidence
    let shown: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(fill)
                switch evidence {
                case .missing:
                    Image(systemName: "exclamationmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(DS.Palette.inkInverse)
                default:
                    DrawnCheck(progress: shown ? 1 : 0)
                        .stroke(DS.Palette.inkInverse, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .padding(6)
                }
            }
            .frame(width: 26, height: 26)
            .scaleEffect(shown ? 1 : 0.3)

            VStack(alignment: .leading, spacing: 4) {
                Text(item)
                    .dsFont(.sans, .semibold, 16)
                    .foregroundStyle(DS.Palette.ink)
                Group {
                    switch evidence {
                    case .heard(let proof):
                        Text("suflor.report.heard \(SuflorSession.clock(proof.seconds)) \(proof.quote)", bundle: .module)
                    case .ticked(let second):
                        Text("suflor.report.ticked \(SuflorSession.clock(second))", bundle: .module)
                    case .missing:
                        Text("suflor.report.missing", bundle: .module)
                    }
                }
                .dsFont(.sans, .regular, 13, lineHeight: 1.3)
                .foregroundStyle(DS.Palette.ink(0.6))
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .dsCard(radius: 18)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 14)
        .accessibilityElement(children: .combine)
    }

    private var fill: Color {
        switch evidence {
        case .heard: DS.Palette.lime
        case .ticked: DS.Palette.ink(0.86)
        case .missing: DS.Palette.amber
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
