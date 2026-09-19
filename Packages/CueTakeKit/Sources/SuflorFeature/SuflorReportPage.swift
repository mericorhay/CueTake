import DesignSystem
import Domain
import SwiftUI
import UIKit

/// The language the brand reads the report in, whatever language the app is in.
public enum SuflorReportLanguage: String, CaseIterable, Identifiable, Sendable {
    case tr, en, es

    public var id: String { rawValue }

    /// Each language names itself.
    var name: String {
        switch self {
        case .tr: "Türkçe"
        case .en: "English"
        case .es: "Español"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    /// The app's language when the report has it, English otherwise.
    static var preferred: SuflorReportLanguage {
        let code = Locale.preferredLanguages.first.map { Locale(identifier: $0).language.languageCode?.identifier ?? "" } ?? ""
        return SuflorReportLanguage(rawValue: code) ?? .en
    }

    private var bundle: Bundle {
        Bundle.module.path(forResource: rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module
    }

    func text(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    func text(_ key: String, _ argument: String) -> String {
        String(format: text(key), locale: locale, argument)
    }
}

/// The report as files: a one-page PDF for the brand's inbox, a picture of it for a chat.
struct SuflorReportFiles {
    let pdf: URL
    let image: URL
    let thumbnail: UIImage

    static let pageSize = CGSize(width: 595, height: 842)

    static func make(for session: SuflorSession, language: SuflorReportLanguage) -> SuflorReportFiles? {
        let page = SuflorReportPage(session: session, language: language)
            .frame(width: pageSize.width, height: pageSize.height)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.locale, language.locale)
        let folder = FileManager.default.temporaryDirectory.appending(path: "suflor-report", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let brand = session.plan.brief.brand.filter { $0.isLetter || $0.isNumber }
        let name = "CueTake-\(brand.isEmpty ? "Report" : brand)-\(session.reportID)-\(language.rawValue.uppercased())"
        let pdf = folder.appending(path: name + ".pdf")
        let png = folder.appending(path: name + ".png")

        let renderer = ImageRenderer(content: page)
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            let info: [CFString: Any] = [
                kCGPDFContextTitle: language.text("suflor.pdf.title"),
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

/// One page for the brand: a dark masthead with the verdict stamped on it, the numbers, the
/// stream as a line with the ad and each proof on it, then every item with its evidence.
struct SuflorReportPage: View {
    let session: SuflorSession
    let language: SuflorReportLanguage

    private let paper = Color.white
    private let ink = Color(hex: 0x0B0B0D)
    private let muted = Color(hex: 0x0B0B0D, alpha: 0.56)
    private let faint = Color(hex: 0x0B0B0D, alpha: 0.06)
    private let rule = Color(hex: 0x0B0B0D, alpha: 0.1)
    private let accent = DS.Palette.accent
    /// Lime is for dark grounds; on paper the verified mark is a deep green that prints.
    private let verified = Color(hex: 0x2E7D32)
    private let amber = Color(hex: 0xC77800)

    private var brief: SuflorBrief { session.plan.brief }
    private func t(_ key: String) -> String { language.text(key) }

    private var delivered: Int {
        brief.mustSay.filter { session.evidence(for: $0) != .missing }.count
    }

    /// Delivered: every item heard, and — once the recording was listened to — the ad disclosed,
    /// the link given when there is one, and nothing said that must not be.
    private var isComplete: Bool {
        let items = brief.mustSay.isEmpty ? session.adStartedAt != nil : delivered == brief.mustSay.count
        guard session.listened else { return items }
        return items && session.disclosure != nil && session.avoidHits.isEmpty && (brief.link.isEmpty || session.linkProof != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            masthead
            VStack(alignment: .leading, spacing: 0) {
                metrics
                timeline.padding(.top, 22)
                items.padding(.top, 22)
                script.padding(.top, 18)
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 40)
            .padding(.top, 22)
            .padding(.bottom, 26)
        }
        .frame(width: SuflorReportFiles.pageSize.width, height: SuflorReportFiles.pageSize.height, alignment: .topLeading)
        .background(paper)
    }

    // MARK: - Masthead

    private var masthead: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(ink)
            // A soft coral glow in the corner: the brand's colour of the stage, not a decoration.
            RadialGradient(colors: [accent.opacity(0.35), .clear], center: .topTrailing, startRadius: 0, endRadius: 320)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: "CueTake")
                        .font(DS.fixed(.archivo, .extrabold, 16))
                        .foregroundStyle(Color.white)
                    Text(t("suflor.pdf.kicker"))
                        .font(DS.fixed(.mono, .medium, 8.5))
                        .tracking(1.8)
                        .foregroundStyle(DS.Palette.lime)
                    Spacer(minLength: 0)
                    Text(verbatim: session.reportID)
                        .font(DS.fixed(.mono, .medium, 9))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                Text(t("suflor.pdf.title"))
                    .font(DS.fixed(.sans, .semibold, 11))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .padding(.top, 26)
                Text(verbatim: brandName)
                    .font(DS.fixed(.archivo, .extrabold, 34))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 4)
                if !brief.product.isEmpty, !brief.brand.isEmpty {
                    Text(verbatim: brief.product)
                        .font(DS.fixed(.sans, .semibold, 14))
                        .foregroundStyle(DS.Palette.lime)
                        .padding(.top, 2)
                }
                Text(verbatim: metaLine)
                    .font(DS.fixed(.sans, .regular, 10.5))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .padding(.top, 12)
            }
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .padding(.trailing, 130)

            stamp
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 40)
                .padding(.top, 70)
        }
        .frame(height: 214)
    }

    private var brandName: String {
        brief.brand.isEmpty ? brief.product : brief.brand
    }

    private var metaLine: String {
        let kind = brief.kind == .live ? t("suflor.pdf.live") : t("suflor.pdf.video")
        let platform = brief.platform == .other ? t("suflor.pdf.other") : brief.platform.title
        let date = session.startedAt.formatted(Date.FormatStyle(date: .long, time: .shortened).locale(language.locale))
        var parts = [kind, platform, date]
        if !session.creator.isEmpty { parts.insert(session.creator, at: 0) }
        return parts.joined(separator: "   ·   ")
    }

    /// The verdict as a rubber stamp: delivered, or partly.
    private var stamp: some View {
        let color = isComplete ? DS.Palette.lime : Color(hex: 0xFFB840)
        return VStack(spacing: 2) {
            Image(systemName: isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .bold))
            Text(isComplete ? t("suflor.pdf.stamp.done") : t("suflor.pdf.stamp.partial"))
                .font(DS.fixed(.mono, .medium, 9))
                .tracking(1.6)
            if !brief.mustSay.isEmpty {
                Text(verbatim: "\(delivered)/\(brief.mustSay.count)")
                    .font(DS.fixed(.archivo, .extrabold, 18))
            }
        }
        .foregroundStyle(color)
        .frame(width: 104, height: 104)
        .overlay(Circle().stroke(color, lineWidth: 2))
        .overlay(Circle().stroke(color.opacity(0.5), lineWidth: 1).padding(5))
        .rotationEffect(.degrees(-9))
    }

    // MARK: - Numbers

    private var metrics: some View {
        HStack(spacing: 10) {
            metric(SuflorSession.clock(session.duration), t("suflor.pdf.stat.length"), ink)
            metric(session.adStartedAt.map { SuflorSession.clock($0) } ?? "—", t("suflor.pdf.stat.adAt"), ink)
            metric(session.adDuration.map { SuflorSession.clock($0) } ?? "—", t("suflor.pdf.stat.adLength"), accent)
            metric(brief.mustSay.isEmpty ? "—" : "\(delivered)/\(brief.mustSay.count)", t("suflor.pdf.stat.score"), isComplete ? verified : amber)
        }
    }

    private func metric(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: value)
                .font(DS.fixed(.archivo, .extrabold, 22))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: label.uppercased())
                .font(DS.fixed(.mono, .medium, 7))
                .tracking(0.9)
                .foregroundStyle(muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(faint))
    }

    // MARK: - The stream as a line

    private var timeline: some View {
        let total = max(1, session.duration)
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(t("suflor.pdf.timeline"))
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(faint).frame(height: 10)
                    if let start = session.adStartedAt {
                        let end = session.adEndedAt ?? min(total, start + (session.adDuration ?? 0))
                        let x = width * min(1, start / total)
                        let w = max(6, width * min(1, max(0, end - start) / total))
                        Capsule()
                            .fill(DS.gradient(90, [accent, DS.Palette.accentWarm]))
                            .frame(width: min(w, width - x), height: 10)
                            .offset(x: x)
                        Text(verbatim: t("suflor.pdf.timeline.ad"))
                            .font(DS.fixed(.mono, .medium, 7.5))
                            .foregroundStyle(accent)
                            .offset(x: x, y: -14)
                    }
                    ForEach(marks, id: \.id) { mark in
                        Circle()
                            .fill(mark.heard ? verified : ink)
                            .overlay(Circle().stroke(paper, lineWidth: 1.5))
                            .frame(width: 9, height: 9)
                            .offset(x: max(0, min(width - 9, width * min(1, mark.second / total) - 4.5)))
                    }
                }
                .frame(height: 30, alignment: .center)
            }
            .frame(height: 30)
            HStack {
                Text(verbatim: "0:00")
                Spacer()
                Text(verbatim: SuflorSession.clock(total))
            }
            .font(DS.fixed(.mono, .medium, 7.5))
            .foregroundStyle(muted)
        }
    }

    private struct Mark {
        var id: String
        var second: Double
        var heard: Bool
    }

    private var marks: [Mark] {
        brief.mustSay.compactMap { item in
            switch session.evidence(for: item) {
            case .heard(let proof): Mark(id: item, second: proof.seconds, heard: true)
            case .ticked(let second): Mark(id: item, second: second, heard: false)
            case .missing: nil
            }
        }
    }

    // MARK: - Evidence

    private var items: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(t("suflor.pdf.items"))
                .padding(.bottom, 8)
            checkRow(t("suflor.pdf.check.disclosure"), proof: session.disclosure)
            Rectangle().fill(rule).frame(height: 1)
            if !brief.link.isEmpty {
                checkRow(t("suflor.pdf.check.link") + " · " + brief.link, proof: session.linkProof)
                Rectangle().fill(rule).frame(height: 1)
            }
            if brief.mustSay.isEmpty {
                Text(verbatim: t("suflor.pdf.items.none"))
                    .font(DS.fixed(.sans, .regular, 10.5))
                    .foregroundStyle(muted)
                    .padding(.vertical, 6)
            }
            ForEach(brief.mustSay.prefix(brief.link.isEmpty ? 5 : 4), id: \.self) { item in
                row(item)
                Rectangle().fill(rule).frame(height: 1)
            }
            if !brief.avoid.isEmpty {
                avoidLine.padding(.top, 8)
            }
        }
    }

    /// A check the app makes on its own: said, with when and a frame; or not heard.
    private func checkRow(_ title: String, proof: SuflorProof?) -> some View {
        let evidence: SuflorSession.Evidence = proof.map { .heard($0) } ?? .missing
        return HStack(alignment: .center, spacing: 12) {
            if session.listened || proof != nil {
                badge(evidence)
            } else {
                Text(verbatim: t("suflor.pdf.badge.notChecked"))
                    .font(DS.fixed(.mono, .medium, 7))
                    .tracking(0.8)
                    .foregroundStyle(muted)
                    .frame(width: 74, height: 20)
                    .background(Capsule().fill(faint))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(DS.fixed(.sans, .semibold, 12.5))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                if let proof {
                    Text(verbatim: language.text("suflor.pdf.heard", SuflorSession.clock(proof.seconds)))
                        .font(DS.fixed(.sans, .medium, 9.5))
                        .foregroundStyle(verified)
                    Text(verbatim: "“" + proof.quote + "”")
                        .font(DS.fixed(.sans, .regular, 9))
                        .italic()
                        .foregroundStyle(muted)
                        .lineLimit(1)
                } else {
                    Text(verbatim: session.listened ? t("suflor.pdf.missing") : t("suflor.pdf.notChecked"))
                        .font(DS.fixed(.sans, .medium, 9.5))
                        .foregroundStyle(session.listened ? amber : muted)
                }
            }
            Spacer(minLength: 0)
            if let data = proof?.frame, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.vertical, 7)
    }

    /// What must not be said: clean, or each time it was.
    private var avoidLine: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: session.avoidHits.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(session.avoidHits.isEmpty ? verified : accent)
            Text(verbatim: avoidText)
                .font(DS.fixed(.sans, .medium, 9.5))
                .foregroundStyle(session.avoidHits.isEmpty ? ink.opacity(0.75) : accent)
                .lineLimit(2)
        }
    }

    private var avoidText: String {
        guard session.listened else { return t("suflor.pdf.avoid.notChecked") }
        guard !session.avoidHits.isEmpty else { return t("suflor.pdf.avoid.clean") }
        let hits = session.avoidHits.prefix(4).map { "\($0.item) \(SuflorSession.clock($0.seconds))" }.joined(separator: ", ")
        return language.text("suflor.pdf.avoid.hit", hits)
    }

    private func row(_ item: String) -> some View {
        let evidence = session.evidence(for: item)
        return HStack(alignment: .center, spacing: 12) {
            badge(evidence)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item)
                    .font(DS.fixed(.sans, .semibold, 12.5))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                switch evidence {
                case .heard(let proof):
                    Text(verbatim: language.text("suflor.pdf.heard", SuflorSession.clock(proof.seconds)))
                        .font(DS.fixed(.sans, .medium, 9.5))
                        .foregroundStyle(verified)
                    Text(verbatim: "“" + proof.quote + "”")
                        .font(DS.fixed(.sans, .regular, 9))
                        .italic()
                        .foregroundStyle(muted)
                        .lineLimit(1)
                case .ticked(let second):
                    Text(verbatim: language.text("suflor.pdf.ticked", SuflorSession.clock(second)))
                        .font(DS.fixed(.sans, .medium, 9.5))
                        .foregroundStyle(ink.opacity(0.75))
                case .missing:
                    Text(verbatim: t("suflor.pdf.missing"))
                        .font(DS.fixed(.sans, .medium, 9.5))
                        .foregroundStyle(amber)
                }
            }
            Spacer(minLength: 0)
            if case .heard(let proof) = evidence, let data = proof.frame, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.vertical, 8)
    }

    private func badge(_ evidence: SuflorSession.Evidence) -> some View {
        let (label, color): (String, Color) = switch evidence {
        case .heard: (t("suflor.pdf.badge.heard"), verified)
        case .ticked: (t("suflor.pdf.badge.ticked"), ink)
        case .missing: (t("suflor.pdf.badge.missing"), amber)
        }
        return Text(verbatim: label)
            .font(DS.fixed(.mono, .medium, 7))
            .tracking(0.8)
            .foregroundStyle(color)
            .frame(width: 74, height: 20)
            .background(Capsule().fill(color.opacity(0.1)))
            .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 0.8))
    }

    // MARK: - Script and footer

    private var script: some View {
        let ad = session.plan.cues.filter { $0.role == .bridge || $0.role == .ad || $0.role == .cta }.map(\.text).joined(separator: " ")
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle(t("suflor.pdf.script"))
            HStack(alignment: .top, spacing: 10) {
                Text(verbatim: "“")
                    .font(DS.fixed(.archivo, .extrabold, 30))
                    .foregroundStyle(accent)
                    .frame(height: 24, alignment: .top)
                Text(verbatim: ad)
                    .font(DS.fixed(.sans, .regular, 9.5))
                    .foregroundStyle(ink.opacity(0.78))
                    .lineSpacing(2)
                    .lineLimit(4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(faint))
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 16) {
            Text(verbatim: t("suflor.pdf.footer"))
                .font(DS.fixed(.sans, .regular, 7.5))
                .foregroundStyle(muted)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: t("suflor.pdf.madeWith"))
                    .font(DS.fixed(.mono, .medium, 7))
                    .foregroundStyle(muted)
                Text(verbatim: "CueTake")
                    .font(DS.fixed(.archivo, .extrabold, 13))
                    .foregroundStyle(ink)
            }
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Rectangle().fill(rule).frame(height: 1) }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(verbatim: text)
            .font(DS.fixed(.mono, .medium, 8))
            .tracking(1.6)
            .foregroundStyle(muted)
    }
}
