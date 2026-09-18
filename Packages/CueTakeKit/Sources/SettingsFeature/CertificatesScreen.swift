import CoreImage
import CoreImage.CIFilterBuiltins
import DesignSystem
import Domain
import SwiftUI
import UIKit

/// The three public certificates: how far along each one is, what is left, and the certificate
/// itself once it is earned — signed, shareable, and checkable by anyone from its QR code.
public struct CertificatesScreen: View {
    private let progress: CertificationProgress
    private let canSign: Bool
    private let onName: (String) -> Void
    /// Has the server sign a certificate. Nil on success, otherwise the words to show.
    private let onSign: (CertificationLevel) async -> String?
    private let onClose: () -> Void

    @State private var shown: CertificationLevel?
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        progress: CertificationProgress,
        canSign: Bool,
        onName: @escaping (String) -> Void,
        onSign: @escaping (CertificationLevel) async -> String?,
        onClose: @escaping () -> Void
    ) {
        self.progress = progress
        self.canSign = canSign
        self.onName = onName
        self.onSign = onSign
        self.onClose = onClose
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                topBar
                hero
                stats
                ForEach(CertificationLevel.allCases, id: \.self) { level in
                    LevelCard(
                        standing: progress.standing(for: level),
                        earned: progress.earned[level],
                        isNext: progress.next == level,
                        appeared: appeared,
                        onShow: { shown = level }
                    )
                }
                honesty
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .background(DS.Palette.screen.ignoresSafeArea())
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 1.1, bounce: 0.15).delay(0.15)) {
                appeared = true
            }
        }
        .sheet(item: $shown) { level in
            CertificateSheet(
                level: level,
                progress: progress,
                canSign: canSign,
                onName: onName,
                onSign: onSign
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Top

    private var topBar: some View {
        HStack {
            DSKicker(String(localized: "cert.kicker", bundle: .module), size: 11)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .dsActionName("xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Palette.ink(0.75))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DS.Palette.hairline(0.08)))
            }
            .buttonStyle(.dsPressIcon)
        }
    }

    /// The ring toward the next certificate, with the hours in the middle.
    private var hero: some View {
        let target = progress.next ?? .workflowSpecialist
        let standing = progress.standing(for: target)
        return HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(DS.Palette.hairline(0.08), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: appeared ? standing.fraction : 0)
                    .stroke(
                        AngularGradient(colors: [target.tint.opacity(0.55), target.tint], center: .center),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(Self.hours(progress.activeHours))
                        .dsFont(.archivo, .extrabold, 30)
                        .foregroundStyle(DS.Palette.ink)
                        .contentTransition(.numericText())
                    Text("cert.hours.unit", bundle: .module)
                        .dsFont(.mono, .medium, 10, letterSpacing: 0.1)
                        .foregroundStyle(DS.Palette.ink(0.6))
                }
            }
            .frame(width: 128, height: 128)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("cert.hero.a11y \(Self.hours(progress.activeHours)) \(Int((standing.fraction * 100).rounded()))", bundle: .module))

            VStack(alignment: .leading, spacing: 6) {
                if let highest = progress.highest {
                    Text("cert.hero.holding", bundle: .module)
                        .dsFont(.sans, .medium, 12)
                        .foregroundStyle(DS.Palette.ink(0.6))
                    Text(highest.title)
                        .dsFont(.archivo, .bold, 19)
                        .foregroundStyle(highest.tint)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("cert.hero.first", bundle: .module)
                        .dsFont(.archivo, .bold, 19)
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let next = progress.next {
                    Text("cert.hero.next \(next.title) \(Int((standing.fraction * 100).rounded()))", bundle: .module)
                        .dsFont(.sans, .regular, 13)
                        .foregroundStyle(DS.Palette.ink(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous)
                .fill(LinearGradient(colors: [target.tint.opacity(0.14), DS.Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.hero, style: .continuous)
                .strokeBorder(target.tint.opacity(0.25), lineWidth: 1)
        )
    }

    private var stats: some View {
        HStack(spacing: 10) {
            stat(Self.hours(progress.activeHours), "cert.stat.hours", symbol: "clock")
            stat("\(progress.finishedProjects.count)", "cert.stat.projects", symbol: "film.stack")
            stat("\(progress.workflowRuns)", "cert.stat.workflows", symbol: "point.3.connected.trianglepath.dotted")
        }
    }

    private func stat(_ value: String, _ key: String.LocalizationValue, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.ink(0.6))
                .accessibilityHidden(true)
            Text(verbatim: value)
                .dsFont(.archivo, .bold, 20)
                .foregroundStyle(DS.Palette.ink)
                .contentTransition(.numericText())
            Text(String(localized: key, bundle: .module))
                .dsFont(.sans, .medium, 11)
                .foregroundStyle(DS.Palette.ink(0.6))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .dsCard(radius: 18)
        .accessibilityElement(children: .combine)
    }

    private var honesty: some View {
        Label {
            Text("cert.honesty", bundle: .module)
                .dsFont(.sans, .regular, 12, lineHeight: 1.4)
                .foregroundStyle(DS.Palette.ink(0.6))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(DS.Palette.ink(0.6))
        }
        .padding(.top, 4)
    }

    static func hours(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))
    }
}

// MARK: - Level card

private struct LevelCard: View {
    let standing: CertificationProgress.Standing
    let earned: Date?
    let isNext: Bool
    let appeared: Bool
    let onShow: () -> Void

    private var level: CertificationLevel { standing.level }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Medal(level: level, fraction: earned != nil ? 1 : (appeared ? standing.fraction : 0), earned: earned != nil)
                    .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.title)
                        .dsFont(.archivo, .bold, 17)
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    stateChip
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 12) {
                requirement(
                    "cert.req.hours \(CertificatesScreen.hours(standing.hours)) \(Int(level.requiredHours))",
                    fraction: standing.hoursFraction
                )
                requirement(
                    "cert.req.projects \(min(standing.projects, level.requiredProjects)) \(level.requiredProjects)",
                    fraction: standing.projectsFraction
                )
                if level.requiredWorkflowRuns > 0 {
                    requirement(
                        "cert.req.workflows \(min(standing.workflowRuns, level.requiredWorkflowRuns)) \(level.requiredWorkflowRuns)",
                        fraction: min(1, Double(standing.workflowRuns) / Double(level.requiredWorkflowRuns))
                    )
                }
                if let previous = level.previous {
                    check(String(localized: "cert.req.previous \(previous.title)", bundle: .module), done: standing.holdsPrevious)
                }
            }

            if !level.requiredTasks.isEmpty {
                tasks
            }

            if level.requiresReview {
                review
            }

            if earned != nil {
                Button(action: onShow) {
                    Label(String(localized: "cert.show", bundle: .module), systemImage: "rosette")
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(level.tint))
                }
                .buttonStyle(.dsPress(radius: 22))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(isNext || earned != nil ? level.tint.opacity(0.45) : DS.Palette.hairline(0.07), lineWidth: isNext ? 1.5 : 1)
        )
        .opacity(standing.holdsPrevious || earned != nil ? 1 : 0.72)
    }

    @ViewBuilder
    private var stateChip: some View {
        let label: String = if earned != nil {
            String(localized: "cert.state.earned", bundle: .module)
        } else if !standing.holdsPrevious {
            String(localized: "cert.state.locked", bundle: .module)
        } else {
            String(localized: "cert.state.progress \(Int((standing.fraction * 100).rounded()))", bundle: .module)
        }
        let symbol = earned != nil ? "checkmark.seal.fill" : (standing.holdsPrevious ? "hourglass" : "lock.fill")
        Label(label, systemImage: symbol)
            .dsFont(.mono, .medium, 10, letterSpacing: 0.06)
            .foregroundStyle(earned != nil ? level.tint : DS.Palette.ink(0.62))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(earned != nil ? level.tint.opacity(0.14) : DS.Palette.hairline(0.07)))
    }

    private func requirement(_ key: String.LocalizationValue, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: key, bundle: .module))
                    .dsFont(.sans, .medium, 13)
                    .foregroundStyle(DS.Palette.ink(0.85))
                Spacer(minLength: 0)
                if fraction >= 1 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(level.tint)
                        .accessibilityHidden(true)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Palette.hairline(0.08))
                    Capsule()
                        .fill(level.tint)
                        .frame(width: proxy.size.width * (appeared ? fraction : 0))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: "\(Int((fraction * 100).rounded()))%"))
    }

    private func check(_ text: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? level.tint : DS.Palette.ink(0.45))
                .accessibilityHidden(true)
            Text(verbatim: text)
                .dsFont(.sans, .medium, 13)
                .foregroundStyle(DS.Palette.ink(done ? 0.85 : 0.62))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(done ? .isSelected : [])
    }

    private var tasks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("cert.tasks \(level.requiredTasks.count - standing.tasksLeft.count) \(level.requiredTasks.count)", bundle: .module)
                .dsFont(.sans, .semibold, 13)
                .foregroundStyle(DS.Palette.ink(0.85))
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(level.requiredTasks, id: \.self) { task in
                    let done = !standing.tasksLeft.contains(task)
                    HStack(spacing: 5) {
                        Image(systemName: done ? "checkmark" : task.symbol)
                            .font(.system(size: 10, weight: .bold))
                            .accessibilityHidden(true)
                        Text(task.title)
                            .dsFont(.sans, .medium, 12)
                    }
                    .foregroundStyle(done ? DS.Palette.inkInverse : DS.Palette.ink(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(done ? level.tint : DS.Palette.hairline(0.07)))
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(done ? .isSelected : [])
                }
            }
        }
    }

    private var review: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.rectangle.badge.checkmark")
                .font(.system(size: 16))
                .foregroundStyle(DS.Palette.ink(0.62))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("cert.review.title", bundle: .module)
                    .dsFont(.sans, .semibold, 13)
                    .foregroundStyle(DS.Palette.ink(0.85))
                Text("cert.review.soon", bundle: .module)
                    .dsFont(.sans, .regular, 12, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.ink(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.05)))
    }
}

// MARK: - Medal

/// A medal for the level: a ring filling toward it, and once earned, a struck face with a sheen.
private struct Medal: View {
    let level: CertificationLevel
    let fraction: Double
    let earned: Bool
    @State private var shine = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(DS.Palette.hairline(0.1), lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(level.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(
                    earned
                        ? AnyShapeStyle(LinearGradient(colors: [level.tint, level.tint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(DS.Palette.hairline(0.06))
                )
                .padding(7)
                .overlay {
                    if earned && !reduceMotion {
                        LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 18)
                            .rotationEffect(.degrees(20))
                            .offset(x: shine ? 40 : -40)
                            .mask(Circle().padding(7))
                    }
                }
            Image(systemName: level.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(earned ? DS.Palette.inkInverse : DS.Palette.ink(0.55))
        }
        .accessibilityHidden(true)
        .onAppear {
            guard earned, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false).delay(0.6)) { shine = true }
        }
    }
}

// MARK: - The certificate

private struct CertificateSheet: View {
    let level: CertificationLevel
    let progress: CertificationProgress
    let canSign: Bool
    let onName: (String) -> Void
    let onSign: (CertificationLevel) async -> String?

    @State private var name = ""
    @State private var signing = false
    @State private var problem: String?
    @Environment(\.displayScale) private var displayScale

    private var signed: SignedCertificate? { progress.signed[level] }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                CertificateCard(
                    level: level,
                    name: name,
                    id: progress.certificateID(for: level) ?? "",
                    issued: progress.earned[level] ?? .now,
                    hours: progress.activeHours,
                    projects: progress.finishedProjects.count,
                    verifyURL: signed?.verifyURL
                )
                .padding(.top, 24)

                TextField(String(localized: "cert.name.placeholder", bundle: .module), text: $name)
                    .dsFont(.sans, .regular, 15)
                    .foregroundStyle(DS.Palette.ink)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.06)))
                    .onSubmit { onName(name) }
                    .disabled(signed != nil)
                    .accessibilityLabel(Text("cert.name.label", bundle: .module))

                if let signed {
                    Label(String(localized: "cert.signed", bundle: .module), systemImage: "checkmark.seal.fill")
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(level.tint)
                    ShareLink(item: signed.verifyURL) {
                        Label(String(localized: "cert.shareLink", bundle: .module), systemImage: "link")
                            .dsFont(.sans, .semibold, 14)
                            .foregroundStyle(DS.Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(DS.Palette.hairline(0.1)))
                    }
                } else {
                    Button {
                        Task { await sign() }
                    } label: {
                        HStack(spacing: 8) {
                            if signing { ProgressView().tint(DS.Palette.inkInverse) }
                            Text("cert.sign", bundle: .module)
                        }
                        .dsFont(.sans, .semibold, 15)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Capsule().fill(level.tint))
                    }
                    .buttonStyle(.dsPress(radius: 24))
                    .disabled(signing || !canSign)
                    Group {
                        if canSign {
                            Text("cert.sign.note", bundle: .module)
                        } else {
                            Text("cert.sign.unavailable", bundle: .module)
                        }
                    }
                        .dsFont(.sans, .regular, 12, lineHeight: 1.35)
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let problem {
                    Text(verbatim: problem)
                        .dsFont(.sans, .medium, 12)
                        .foregroundStyle(DS.Palette.accent)
                        .multilineTextAlignment(.center)
                }

                if let image = renderedCard {
                    ShareLink(
                        item: image,
                        preview: SharePreview(level.title, image: image)
                    ) {
                        Label(String(localized: "cert.shareImage", bundle: .module), systemImage: "square.and.arrow.up")
                            .dsFont(.sans, .semibold, 14)
                            .foregroundStyle(DS.Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(DS.Palette.hairline(0.1)))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.screen.ignoresSafeArea())
        .onAppear { name = progress.holderName ?? "" }
    }

    /// The card as a picture, for sharing where a link is not enough.
    private var renderedCard: Image? {
        let renderer = ImageRenderer(content:
            CertificateCard(
                level: level,
                name: name,
                id: progress.certificateID(for: level) ?? "",
                issued: progress.earned[level] ?? .now,
                hours: progress.activeHours,
                projects: progress.finishedProjects.count,
                verifyURL: signed?.verifyURL
            )
            .frame(width: 360)
            .padding(20)
            .background(DS.Palette.screen)
            .environment(\.colorScheme, .dark)
        )
        renderer.scale = displayScale
        return renderer.uiImage.map { Image(uiImage: $0) }
    }

    private func sign() async {
        onName(name)
        signing = true
        problem = await onSign(level)
        signing = false
    }
}

/// The certificate itself: what it is, whose, when, and the code that proves it.
private struct CertificateCard: View {
    let level: CertificationLevel
    let name: String
    let id: String
    let issued: Date
    let hours: Double
    let projects: Int
    let verifyURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(verbatim: "CUETAKE")
                    .dsFont(.archivo, .extrabold, 13, letterSpacing: 0.2)
                    .foregroundStyle(DS.Palette.ink(0.7))
                Spacer(minLength: 0)
                Image(systemName: level.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(level.tint)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("cert.card.certifies", bundle: .module)
                    .dsFont(.sans, .medium, 12)
                    .foregroundStyle(DS.Palette.ink(0.6))
                if name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("cert.card.noName", bundle: .module)
                        .dsFont(.archivo, .bold, 24)
                        .foregroundStyle(DS.Palette.ink(0.45))
                } else {
                    Text(verbatim: name)
                        .dsFont(.archivo, .bold, 24)
                        .foregroundStyle(DS.Palette.ink)
                }
                Text(level.title)
                    .dsFont(.archivo, .extrabold, 20)
                    .foregroundStyle(level.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    detail("cert.card.issued", issued.formatted(date: .long, time: .omitted))
                    detail("cert.card.work", "\(CertificatesScreen.hours(hours)) · \(projects)")
                    detail("cert.card.id", id)
                }
                Spacer(minLength: 0)
                if let verifyURL, let code = QRCode.image(for: verifyURL.absoluteString) {
                    Image(uiImage: code)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 78, height: 78)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
                        .accessibilityLabel(Text("cert.card.qr", bundle: .module))
                }
            }
        }
        .padding(22)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(red: 0.07, green: 0.07, blue: 0.085))
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(RadialGradient(colors: [level.tint.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 260))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(LinearGradient(colors: [level.tint.opacity(0.7), level.tint.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
    }

    private func detail(_ key: String.LocalizationValue, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(String(localized: key, bundle: .module))
                .dsFont(.mono, .medium, 10, letterSpacing: 0.06)
                .foregroundStyle(DS.Palette.ink(0.56))
            Text(verbatim: value)
                .dsFont(.mono, .medium, 11)
                .foregroundStyle(DS.Palette.ink(0.9))
        }
    }
}

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Names and colours

extension CertificationLevel: @retroactive Identifiable {
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .creator: "CueTake Creator"
        case .advancedCreator: "CueTake Advanced Creator"
        case .workflowSpecialist: "CueTake Workflow Specialist"
        }
    }

    var tint: Color {
        switch self {
        case .creator: DS.Palette.lime
        case .advancedCreator: DS.Palette.accentWarm
        case .workflowSpecialist: Color(red: 0.45, green: 0.66, blue: 1)
        }
    }

    var symbol: String {
        switch self {
        case .creator: "video.badge.checkmark"
        case .advancedCreator: "wand.and.stars"
        case .workflowSpecialist: "point.3.connected.trianglepath.dotted"
        }
    }
}

extension CertificationTask {
    var title: String {
        switch self {
        case .prompterTake: String(localized: "cert.task.prompterTake", bundle: .module)
        case .cleanup: String(localized: "cert.task.cleanup", bundle: .module)
        case .captions: String(localized: "cert.task.captions", bundle: .module)
        case .transition: String(localized: "cert.task.transition", bundle: .module)
        case .background: String(localized: "cert.task.background", bundle: .module)
        case .colorLook: String(localized: "cert.task.colorLook", bundle: .module)
        case .textBehindPerson: String(localized: "cert.task.textBehindPerson", bundle: .module)
        case .volumeCurve: String(localized: "cert.task.volumeCurve", bundle: .module)
        case .layeredVideo: String(localized: "cert.task.layeredVideo", bundle: .module)
        case .namedVersion: String(localized: "cert.task.namedVersion", bundle: .module)
        case .workflowRun: String(localized: "cert.task.workflowRun", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .prompterTake: "text.viewfinder"
        case .cleanup: "scissors"
        case .captions: "captions.bubble"
        case .transition: "square.on.square"
        case .background: "person.crop.rectangle"
        case .colorLook: "camera.filters"
        case .textBehindPerson: "person.and.background.dotted"
        case .volumeCurve: "waveform.path.ecg"
        case .layeredVideo: "rectangle.on.rectangle"
        case .namedVersion: "clock.arrow.circlepath"
        case .workflowRun: "point.3.connected.trianglepath.dotted"
        }
    }
}
