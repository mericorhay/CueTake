import DesignSystem
import Domain
import SwiftUI
import UIKit

/// The report as files: a one-page PDF for the brand's inbox, a picture of it for a chat.
struct SuflorReportFiles {
    let pdf: URL
    let image: URL
    let thumbnail: UIImage

    static let pageSize = CGSize(width: 595, height: 842)

    static func make(for session: SuflorSession) -> SuflorReportFiles? {
        let page = SuflorReportPage(session: session)
            .frame(width: pageSize.width, height: pageSize.height)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
        let folder = FileManager.default.temporaryDirectory.appending(path: "suflor-report", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "CueTake-\(session.reportID)"
        let pdf = folder.appending(path: name + ".pdf")
        let png = folder.appending(path: name + ".png")

        let renderer = ImageRenderer(content: page)
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            let info: [CFString: Any] = [
                kCGPDFContextTitle: String(localized: "suflor.page.title", bundle: .module),
                kCGPDFContextCreator: "CueTake",
            ]
            guard let context = CGContext(pdf as CFURL, mediaBox: &box, info as CFDictionary) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        do {
            try data.write(to: png, options: .atomic)
        } catch {
            return nil
        }
        return SuflorReportFiles(pdf: pdf, image: png, thumbnail: image)
    }
}

/// One page, printed light: the brand reads it on a laptop or prints it, not on a dark phone.
struct SuflorReportPage: View {
    let session: SuflorSession

    private let paper = Color.white
    private let ink = Color(hex: 0x0B0B0D)
    private let muted = Color(hex: 0x0B0B0D, alpha: 0.58)
    private let rule = Color(hex: 0x0B0B0D, alpha: 0.1)
    private let accent = DS.Palette.accent
    private let verified = Color(hex: 0x2F7A1F)

    private var brief: SuflorBrief { session.plan.brief }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            masthead
            Rectangle().fill(ink).frame(height: 2).padding(.top, 14)

            Text("suflor.page.title", bundle: .module)
                .font(DS.fixed(.archivo, .extrabold, 30))
                .foregroundStyle(ink)
                .padding(.top, 22)
            Text(brandLine)
                .font(DS.fixed(.sans, .semibold, 15))
                .foregroundStyle(ink)
                .padding(.top, 6)
            Text(metaLine)
                .font(DS.fixed(.sans, .regular, 11))
                .foregroundStyle(muted)
                .padding(.top, 4)

            stats.padding(.top, 20)
            items.padding(.top, 22)
            frames.padding(.top, 16)
            script.padding(.top, 16)

            Spacer(minLength: 0)
            footer
        }
        .padding(44)
        .frame(width: SuflorReportFiles.pageSize.width, height: SuflorReportFiles.pageSize.height, alignment: .topLeading)
        .background(paper)
    }

    private var masthead: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: "CueTake")
                .font(DS.fixed(.archivo, .extrabold, 18))
                .foregroundStyle(ink)
            Text("suflor.page.kicker", bundle: .module)
                .font(DS.fixed(.mono, .medium, 9))
                .tracking(1.6)
                .foregroundStyle(accent)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.reportID)
                    .font(DS.fixed(.mono, .medium, 10))
                    .foregroundStyle(ink)
                Text(session.startedAt.formatted(date: .long, time: .shortened))
                    .font(DS.fixed(.sans, .regular, 9))
                    .foregroundStyle(muted)
            }
        }
    }

    private var brandLine: String {
        [brief.brand, brief.product].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var metaLine: String {
        var parts = [brief.platform.title]
        parts.append(brief.kind == .live ? String(localized: "suflor.kind.live", bundle: .module) : String(localized: "suflor.kind.video", bundle: .module))
        if !session.creator.isEmpty { parts.append(session.creator) }
        return parts.joined(separator: "  ·  ")
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat(SuflorSession.clock(session.duration), String(localized: "suflor.report.stat.length", bundle: .module))
            divider
            stat(session.adStartedAt.map { SuflorSession.clock($0) } ?? "—", String(localized: "suflor.report.stat.adAt", bundle: .module))
            divider
            stat(session.adDuration.map { SuflorSession.clock($0) } ?? "—", String(localized: "suflor.report.stat.adLength", bundle: .module))
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(rule).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(rule).frame(height: 1) }
    }

    private var divider: some View {
        Rectangle().fill(rule).frame(width: 1, height: 34).padding(.horizontal, 14)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(DS.fixed(.archivo, .bold, 20))
                .foregroundStyle(ink)
                .monospacedDigit()
            Text(label.uppercased())
                .font(DS.fixed(.mono, .medium, 7.5))
                .tracking(0.8)
                .foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var items: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("suflor.report.said", bundle: .module)
                .font(DS.fixed(.mono, .medium, 9))
                .tracking(1.4)
                .foregroundStyle(muted)
                .padding(.bottom, 6)
            ForEach(brief.mustSay, id: \.self) { item in
                row(item)
                Rectangle().fill(rule).frame(height: 1)
            }
            if brief.mustSay.isEmpty {
                Text("suflor.report.said.none", bundle: .module)
                    .font(DS.fixed(.sans, .regular, 11))
                    .foregroundStyle(muted)
            }
        }
    }

    private func row(_ item: String) -> some View {
        let evidence = session.evidence(for: item)
        return HStack(alignment: .top, spacing: 12) {
            Text(item)
                .font(DS.fixed(.sans, .semibold, 12))
                .foregroundStyle(ink)
                .frame(width: 140, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                switch evidence {
                case .heard(let proof):
                    Text("suflor.page.heard \(SuflorSession.clock(proof.seconds))", bundle: .module)
                        .font(DS.fixed(.sans, .semibold, 11))
                        .foregroundStyle(verified)
                    Text(verbatim: "“" + proof.quote + "”")
                        .font(DS.fixed(.sans, .regular, 10))
                        .foregroundStyle(muted)
                        .lineLimit(2)
                case .ticked(let second):
                    Text("suflor.page.ticked \(SuflorSession.clock(second))", bundle: .module)
                        .font(DS.fixed(.sans, .semibold, 11))
                        .foregroundStyle(ink)
                case .missing:
                    Text("suflor.page.missing", bundle: .module)
                        .font(DS.fixed(.sans, .semibold, 11))
                        .foregroundStyle(accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var frames: some View {
        let shots = session.proofs.filter { $0.frame != nil }.prefix(4)
        if !shots.isEmpty {
            HStack(spacing: 10) {
                ForEach(Array(shots)) { proof in
                    if let data = proof.frame, let image = UIImage(data: data) {
                        VStack(alignment: .leading, spacing: 3) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 112, height: 84)
                                .clipped()
                            Text(verbatim: SuflorSession.clock(proof.seconds) + " · " + proof.item)
                                .font(DS.fixed(.mono, .medium, 7.5))
                                .foregroundStyle(muted)
                                .lineLimit(1)
                                .frame(width: 112, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private var script: some View {
        let ad = session.plan.cues.filter { $0.role == .ad || $0.role == .cta || $0.role == .bridge }.map(\.text).joined(separator: " ")
        return VStack(alignment: .leading, spacing: 5) {
            Text("suflor.page.script", bundle: .module)
                .font(DS.fixed(.mono, .medium, 9))
                .tracking(1.4)
                .foregroundStyle(muted)
            Text(ad)
                .font(DS.fixed(.sans, .regular, 10.5))
                .foregroundStyle(ink.opacity(0.8))
                .lineSpacing(2)
                .lineLimit(7)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(rule).frame(height: 1)
            Text("suflor.page.footer", bundle: .module)
                .font(DS.fixed(.sans, .regular, 8.5))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }
}
