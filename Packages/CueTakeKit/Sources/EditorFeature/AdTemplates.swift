import DesignSystem
import Domain
import SwiftUI
import UIKit

// Picture templates for a sponsored video: a discount code, a price tag, a launch stamp, a
// partnership tag — thirty of them, sorted by the kind of brand they suit. Each is filled in with
// the brand's name, a line and a detail in the brand's colour, drawn as a picture and laid on the
// timeline at the playhead like any other picture, so it can be moved, timed and sized there.

/// The kinds of brand the templates are sorted by.
enum AdCategory: String, CaseIterable, Identifiable {
    case beauty, fashion, food, tech, gaming, fitness, travel, finance, home, education, events, partnership

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beauty: String(localized: "editor.template.category.beauty", bundle: .module)
        case .fashion: String(localized: "editor.template.category.fashion", bundle: .module)
        case .food: String(localized: "editor.template.category.food", bundle: .module)
        case .tech: String(localized: "editor.template.category.tech", bundle: .module)
        case .gaming: String(localized: "editor.template.category.gaming", bundle: .module)
        case .fitness: String(localized: "editor.template.category.fitness", bundle: .module)
        case .travel: String(localized: "editor.template.category.travel", bundle: .module)
        case .finance: String(localized: "editor.template.category.finance", bundle: .module)
        case .home: String(localized: "editor.template.category.home", bundle: .module)
        case .education: String(localized: "editor.template.category.education", bundle: .module)
        case .events: String(localized: "editor.template.category.events", bundle: .module)
        case .partnership: String(localized: "editor.template.category.partnership", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .beauty: "sparkles"
        case .fashion: "tshirt"
        case .food: "fork.knife"
        case .tech: "iphone"
        case .gaming: "gamecontroller"
        case .fitness: "figure.run"
        case .travel: "airplane"
        case .finance: "creditcard"
        case .home: "sofa"
        case .education: "graduationcap"
        case .events: "ticket"
        case .partnership: "person.2"
        }
    }
}

/// How a template is drawn.
enum AdStyle: String {
    case codeCard, lowerThird, badge, priceTag, bigTitle, linkPill, review, countdown, newDrop, ticket, collab

    /// Where it lands on the frame, and how wide it is as a share of the frame's width.
    var placement: (x: Double, y: Double, width: Double) {
        switch self {
        case .codeCard: (0.5, 0.74, 0.62)
        case .lowerThird: (0.5, 0.82, 0.86)
        case .badge: (0.74, 0.24, 0.32)
        case .priceTag: (0.5, 0.72, 0.58)
        case .bigTitle: (0.5, 0.26, 0.84)
        case .linkPill: (0.5, 0.86, 0.56)
        case .review: (0.5, 0.72, 0.7)
        case .countdown: (0.5, 0.18, 0.66)
        case .newDrop: (0.5, 0.3, 0.62)
        case .ticket: (0.5, 0.72, 0.72)
        case .collab: (0.5, 0.16, 0.6)
        }
    }
}

/// One template: a style with a first draft of its words, in the viewer's language.
struct AdTemplate: Identifiable, Hashable {
    let id: String
    let category: AdCategory
    let style: AdStyle
    let headline: String
    let detail: String
    /// The colour it suggests when the brand has none of its own.
    let accent: UInt32

    private static var turkish: Bool { Locale.current.language.languageCode?.identifier == "tr" }
    private static func say(_ tr: String, _ en: String) -> String { turkish ? tr : en }

    private init(_ id: String, _ category: AdCategory, _ style: AdStyle, _ headline: String, _ detail: String, _ accent: UInt32) {
        self.id = id
        self.category = category
        self.style = style
        self.headline = headline
        self.detail = detail
        self.accent = accent
    }

    static let all: [AdTemplate] = [
        // Beauty
        AdTemplate("beauty.code", .beauty, .codeCard, say("İndirim kodu", "Discount code"), "GLOW20", 0xF7A8C4),
        AdTemplate("beauty.review", .beauty, .review, say("İki haftada fark ettim", "Two weeks in, I can tell"), say("Cildim teşekkür ediyor", "My skin says thanks"), 0xF7A8C4),
        AdTemplate("beauty.new", .beauty, .newDrop, say("Yeni serum", "New serum"), say("Şimdi raflarda", "Out now"), 0xE9C9A6),
        // Fashion
        AdTemplate("fashion.title", .fashion, .bigTitle, say("Yeni sezon", "New season"), say("Koleksiyon yayında", "The collection is live"), 0x111111),
        AdTemplate("fashion.price", .fashion, .priceTag, say("Keten gömlek", "Linen shirt"), "899 ₺", 0xD8C3A5),
        AdTemplate("fashion.countdown", .fashion, .countdown, say("Son 24 saat", "Last 24 hours"), say("Sepette %30", "30% off at checkout"), 0xFF5A4F),
        // Food & drink
        AdTemplate("food.badge", .food, .badge, "%25", say("İNDİRİM", "OFF"), 0xFFB840),
        AdTemplate("food.price", .food, .priceTag, say("Menü", "Combo"), "149 ₺", 0xFF7A3D),
        AdTemplate("food.link", .food, .linkPill, say("Sipariş linki bio'da", "Order link in bio"), "", 0x2FBF71),
        // Tech
        AdTemplate("tech.new", .tech, .newDrop, say("Yeni model", "The new model"), say("Ön siparişte", "Pre-order now"), 0x3D8BFF),
        AdTemplate("tech.review", .tech, .review, say("Pil iki gün gitti", "The battery lasted two days"), say("Bir ay kullandım", "After a month of use"), 0x3D8BFF),
        AdTemplate("tech.code", .tech, .codeCard, say("Kodla ek indirim", "Extra off with code"), "TECH15", 0x6C5CE7),
        // Gaming
        AdTemplate("gaming.collab", .gaming, .collab, say("İş birliği", "Partnership"), "", 0x9B5CFF),
        AdTemplate("gaming.code", .gaming, .codeCard, say("Oyun içi kod", "In-game code"), "LOOT2026", 0x9B5CFF),
        AdTemplate("gaming.countdown", .gaming, .countdown, say("Etkinlik bitiyor", "Event ends soon"), say("Son 3 gün", "3 days left"), 0x00E5A8),
        // Fitness
        AdTemplate("fitness.title", .fitness, .bigTitle, say("30 gün meydan okuma", "30-day challenge"), say("Benimle başla", "Start with me"), 0xC6F24A),
        AdTemplate("fitness.badge", .fitness, .badge, "%40", say("ÜYELİK", "MEMBERSHIP"), 0xC6F24A),
        // Travel
        AdTemplate("travel.ticket", .travel, .ticket, say("Kapadokya kaçamağı", "A weekend in Cappadocia"), say("3 gece · Kahvaltı dahil", "3 nights · Breakfast included"), 0x1FB5C9),
        AdTemplate("travel.title", .travel, .bigTitle, say("Nereye gidiyoruz?", "Where to next?"), say("Rota linkte", "Route in the link"), 0x1FB5C9),
        AdTemplate("travel.link", .travel, .linkPill, say("Erken rezervasyon linkte", "Early booking in the link"), "", 0xFFB840),
        // Apps & finance
        AdTemplate("finance.code", .finance, .codeCard, say("Davet kodu", "Invite code"), "HOSGELDIN", 0x2FBF71),
        AdTemplate("finance.link", .finance, .linkPill, say("Uygulamayı indir", "Get the app"), "", 0x3D8BFF),
        // Home & living
        AdTemplate("home.price", .home, .priceTag, say("Kahve makinesi", "Coffee machine"), "2.499 ₺", 0xB08968),
        AdTemplate("home.review", .home, .review, say("Sabahlarım değişti", "My mornings changed"), say("Her gün kullanıyorum", "I use it every day"), 0xB08968),
        // Education
        AdTemplate("education.ticket", .education, .ticket, say("Canlı ders", "Live class"), say("Salı 20:00 · Ücretsiz", "Tuesday 8 pm · Free"), 0x6C5CE7),
        AdTemplate("education.badge", .education, .badge, "%50", say("İLK AY", "FIRST MONTH"), 0x6C5CE7),
        // Events
        AdTemplate("events.ticket", .events, .ticket, say("Festival", "Festival"), say("12 Ekim · İstanbul", "12 October · Istanbul"), 0xFF5A4F),
        AdTemplate("events.countdown", .events, .countdown, say("Biletler tükeniyor", "Tickets selling out"), say("Son 100 bilet", "Last 100 tickets"), 0xFF5A4F),
        // Partnership
        AdTemplate("partnership.lower", .partnership, .lowerThird, say("İş birliği", "Paid partnership"), say("Bu video reklam içerir", "This video contains an ad"), 0xFF5A4F),
        AdTemplate("partnership.collab", .partnership, .collab, say("İş birliği", "Partnership"), "", 0x111111),
    ]
}

/// What the creator fills in: the same across templates, so switching keeps the brand.
struct AdTemplateFields: Equatable {
    var brand: String
    var headline: String
    var detail: String
    var accent: Color
}

// MARK: - Drawing

/// A template drawn at 360 points wide; it is rendered at three times that for the video.
struct AdTemplateArt: View {
    let style: AdStyle
    let fields: AdTemplateFields

    static let width: CGFloat = 360

    private var accent: Color { fields.accent }
    /// Text on the accent: black on light colours, white on dark ones.
    private var onAccent: Color { Self.isLight(fields.accent) ? Color(white: 0.06) : .white }
    private var brand: String { fields.brand.trimmingCharacters(in: .whitespaces).isEmpty ? "BRAND" : fields.brand }

    var body: some View {
        Group {
            switch style {
            case .codeCard: codeCard
            case .lowerThird: lowerThird
            case .badge: badge
            case .priceTag: priceTag
            case .bigTitle: bigTitle
            case .linkPill: linkPill
            case .review: review
            case .countdown: countdown
            case .newDrop: newDrop
            case .ticket: ticket
            case .collab: collab
            }
        }
        .frame(width: Self.width)
        .environment(\.colorScheme, .dark)
    }

    private func font(_ family: DS.FontFamily, _ weight: DS.FontWeight, _ size: CGFloat) -> Font {
        DS.fixed(family, weight, size)
    }

    private var codeCard: some View {
        VStack(spacing: 10) {
            Text(fields.headline.uppercased())
                .font(font(.mono, .medium, 13))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.75))
            Text(fields.detail.isEmpty ? "CODE" : fields.detail)
                .font(font(.archivo, .extrabold, 48))
                .foregroundStyle(onAccent)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5])).foregroundStyle(onAccent.opacity(0.35)).padding(5))
            Text(brand)
                .font(font(.sans, .semibold, 15))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(white: 0.07).opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(accent.opacity(0.7), lineWidth: 2))
    }

    private var lowerThird: some View {
        HStack(spacing: 0) {
            Text(brand.uppercased())
                .font(font(.archivo, .extrabold, 20))
                .foregroundStyle(onAccent)
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)
                .background(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(fields.headline)
                    .font(font(.sans, .semibold, 18))
                    .foregroundStyle(Color(white: 0.06))
                if !fields.detail.isEmpty {
                    Text(fields.detail)
                        .font(font(.sans, .regular, 13))
                        .foregroundStyle(Color(white: 0.3))
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.white)
        }
        .frame(height: 66)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var badge: some View {
        ZStack {
            StarBurst(points: 16)
                .fill(accent)
            VStack(spacing: 0) {
                Text(fields.headline)
                    .font(font(.archivo, .extrabold, 78))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(fields.detail)
                    .font(font(.mono, .medium, 18))
                    .tracking(2)
                Text(brand)
                    .font(font(.sans, .semibold, 15))
                    .opacity(0.8)
                    .padding(.top, 4)
            }
            .foregroundStyle(onAccent)
            .padding(40)
        }
        .frame(width: Self.width, height: Self.width)
        .rotationEffect(.degrees(-10))
    }

    private var priceTag: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(brand.uppercased())
                    .font(font(.mono, .medium, 12))
                    .tracking(2)
                    .foregroundStyle(Color(white: 0.4))
                Text(fields.headline)
                    .font(font(.sans, .semibold, 22))
                    .foregroundStyle(Color(white: 0.06))
                    .lineLimit(2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(fields.detail)
                .font(font(.archivo, .extrabold, 30))
                .foregroundStyle(onAccent)
                .padding(.horizontal, 18)
                .frame(maxHeight: .infinity)
                .background(accent)
        }
        .frame(height: 96)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .leading) {
            Circle().fill(Color(white: 0.85)).frame(width: 12, height: 12).padding(.leading, 6)
        }
    }

    private var bigTitle: some View {
        VStack(spacing: 6) {
            Text(brand.uppercased())
                .font(font(.mono, .medium, 14))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.85))
            Text(fields.headline)
                .font(font(.archivo, .extrabold, 54))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            Capsule().fill(accent).frame(width: 120, height: 8)
            if !fields.detail.isEmpty {
                Text(fields.detail)
                    .font(font(.sans, .semibold, 18))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 10)
    }

    private var linkPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(onAccent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(accent))
            VStack(alignment: .leading, spacing: 1) {
                Text(fields.headline)
                    .font(font(.sans, .semibold, 18))
                    .foregroundStyle(Color(white: 0.06))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(brand)
                    .font(font(.sans, .regular, 13))
                    .foregroundStyle(Color(white: 0.4))
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .padding(.trailing, 12)
        .background(Capsule().fill(Color.white))
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill").font(.system(size: 16)).foregroundStyle(accent)
                }
            }
            Text(verbatim: "“\(fields.headline)”")
                .font(font(.sans, .semibold, 22))
                .foregroundStyle(Color(white: 0.06))
                .lineLimit(3)
            HStack {
                Text(fields.detail)
                    .font(font(.sans, .regular, 14))
                    .foregroundStyle(Color(white: 0.4))
                Spacer(minLength: 0)
                Text(brand)
                    .font(font(.mono, .medium, 12))
                    .foregroundStyle(onAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accent))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white))
    }

    private var countdown: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill").font(.system(size: 18, weight: .bold))
                Text(fields.headline.uppercased())
                    .font(font(.archivo, .extrabold, 26))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(onAccent)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(accent)
            HStack {
                Text(fields.detail)
                    .font(font(.sans, .semibold, 17))
                    .foregroundStyle(Color(white: 0.06))
                Spacer(minLength: 0)
                Text(brand)
                    .font(font(.mono, .medium, 12))
                    .foregroundStyle(Color(white: 0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var newDrop: some View {
        VStack(spacing: 8) {
            Text(String(localized: "editor.template.new", bundle: .module))
                .font(font(.archivo, .extrabold, 22))
                .foregroundStyle(onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(accent))
                .rotationEffect(.degrees(-4))
            Text(fields.headline)
                .font(font(.archivo, .extrabold, 40))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
            Text(verbatim: fields.detail.isEmpty ? brand : "\(brand) · \(fields.detail)")
                .font(font(.sans, .semibold, 16))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(white: 0.06).opacity(0.85)))
    }

    private var ticket: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(brand.uppercased())
                    .font(font(.mono, .medium, 12))
                    .tracking(2)
                    .foregroundStyle(Color(white: 0.4))
                Text(fields.headline)
                    .font(font(.archivo, .extrabold, 26))
                    .foregroundStyle(Color(white: 0.06))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(fields.detail)
                    .font(font(.sans, .medium, 14))
                    .foregroundStyle(Color(white: 0.3))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            Rectangle()
                .fill(Color.white)
                .frame(width: 2)
                .overlay(Rectangle().stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 4])).foregroundStyle(Color(white: 0.7)))
            Image(systemName: "ticket.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(onAccent)
                .frame(width: 74)
                .frame(maxHeight: .infinity)
                .background(accent)
        }
        .frame(height: 118)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            // The notches of a ticket, where it would be torn.
            HStack {
                Spacer()
                VStack {
                    Circle().frame(width: 18, height: 18).offset(y: -9)
                    Spacer()
                    Circle().frame(width: 18, height: 18).offset(y: 9)
                }
                .frame(width: 18)
                .padding(.trailing, 66)
            }
            .blendMode(.destinationOut)
        }
        .compositingGroup()
    }

    private var collab: some View {
        HStack(spacing: 10) {
            Text(brand.uppercased())
                .font(font(.archivo, .extrabold, 20))
                .foregroundStyle(onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(accent))
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
            Text(fields.headline)
                .font(font(.sans, .semibold, 17))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(8)
        .padding(.trailing, 10)
        .background(Capsule().fill(Color(white: 0.06).opacity(0.8)))
        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
    }

    static func isLight(_ color: Color) -> Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.299 * red + 0.587 * green + 0.114 * blue > 0.6
    }

    /// The template as a picture with a clear background, three times its drawn size.
    static func render(_ style: AdStyle, fields: AdTemplateFields) -> Data? {
        let renderer = ImageRenderer(content: AdTemplateArt(style: style, fields: fields).padding(8))
        renderer.scale = 3
        renderer.isOpaque = false
        return renderer.uiImage?.pngData()
    }
}

/// A seal with points, for a discount badge.
private struct StarBurst: Shape {
    let points: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.86
        var path = Path()
        for index in 0..<(points * 2) {
            let angle = Double(index) * .pi / Double(points) - .pi / 2
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - The sheet

/// Pick a template, fill in the brand, put it on the timeline.
struct AdTemplateSheet: View {
    /// The brand kit's colour, offered first when there is one.
    let brandColor: Color?
    let onAdd: (Data, AdStyle) -> Void
    let onClose: () -> Void

    @State private var category: AdCategory?
    @State private var selected = AdTemplate.all[0]
    @State private var fields = AdTemplateFields(brand: "", headline: "", detail: "", accent: .red)
    @State private var loaded = false
    @AppStorage("editor.template.brand") private var savedBrand = ""

    private var swatches: [Color] {
        let presets: [UInt32] = [0xFF5A4F, 0xC6F24A, 0xFFB840, 0xF7A8C4, 0x3D8BFF, 0x9B5CFF, 0x1FB5C9, 0x2FBF71, 0x111111, 0xFFFFFF]
        return (brandColor.map { [$0] } ?? []) + presets.map { Color(hex: $0) }
    }

    private var shown: [AdTemplate] {
        guard let category else { return AdTemplate.all }
        return AdTemplate.all.filter { $0.category == category }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    preview
                    form
                    categories
                    grid
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.Palette.screen)
            .navigationTitle(String(localized: "editor.template.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "editor.template.cancel", bundle: .module), action: onClose)
                }
            }
            .safeAreaInset(edge: .bottom) { addButton }
        }
        .tint(DS.Palette.lime)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            fields.brand = savedBrand
            choose(selected)
        }
    }

    /// The template as it will look over the video.
    private var preview: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x3A2A24), Color(hex: 0x141416)], startPoint: .top, endPoint: .bottom)
            AdTemplateArt(style: selected.style, fields: fields)
                .scaleEffect(0.82)
                .padding(.vertical, 20)
        }
        .frame(height: selected.style == .badge ? 330 : 240)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(DS.Palette.hairline(0.1), lineWidth: 1))
        .animation(DS.Motion.settle, value: selected)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    private var form: some View {
        VStack(spacing: 10) {
            field("editor.template.brand", text: $fields.brand)
                .onChange(of: fields.brand) { _, brand in savedBrand = brand }
            field("editor.template.headline", text: $fields.headline)
            if selected.style != .linkPill, selected.style != .collab {
                field("editor.template.detail", text: $fields.detail)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(swatches.enumerated()), id: \.offset) { _, color in
                        Button {
                            withAnimation(DS.Motion.snap) { fields.accent = color }
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(DS.Palette.hairline(0.25), lineWidth: 1))
                                .overlay(Circle().stroke(DS.Palette.lime, lineWidth: fields.accent == color ? 3 : 0).padding(-4))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.dsPress)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func field(_ key: String.LocalizationValue, text: Binding<String>) -> some View {
        let title = String(localized: key, bundle: .module)
        return HStack(spacing: 12) {
            Text(title)
                .dsFont(.mono, .medium, 11, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.56))
                .frame(width: 70, alignment: .leading)
            TextField(title, text: text)
                .dsFont(.sans, .semibold, 15)
                .foregroundStyle(DS.Palette.ink)
                .frame(minHeight: 48)
        }
        .padding(.horizontal, 14)
        .dsCard(radius: 14)
    }

    private var categories: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(nil, title: String(localized: "editor.template.all", bundle: .module), symbol: "square.grid.2x2")
                ForEach(AdCategory.allCases) { item in
                    chip(item, title: item.title, symbol: item.symbol)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ item: AdCategory?, title: String, symbol: String) -> some View {
        let isOn = category == item
        return Button {
            withAnimation(DS.Motion.snap) { category = item }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).dsFont(.sans, .semibold, 13)
            }
            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.8))
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Capsule().fill(isOn ? DS.Palette.lime : DS.Palette.hairline(0.07)))
        }
        .buttonStyle(.dsPress)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(shown) { template in
                Button {
                    withAnimation(DS.Motion.settle) { choose(template) }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Color(hex: 0x1C1C20)
                            AdTemplateArt(style: template.style, fields: thumbnailFields(template))
                                .scaleEffect(template.style == .badge ? 0.34 : 0.42)
                        }
                        .frame(height: 118)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selected == template ? DS.Palette.lime : DS.Palette.hairline(0.08), lineWidth: selected == template ? 2 : 1)
                        )
                        Text(template.category.title)
                            .dsFont(.sans, .medium, 11)
                            .foregroundStyle(DS.Palette.ink(0.6))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.dsPressCard)
            }
        }
    }

    /// The grid shows each template with the brand typed so far and its own suggested words.
    private func thumbnailFields(_ template: AdTemplate) -> AdTemplateFields {
        AdTemplateFields(brand: fields.brand, headline: template.headline, detail: template.detail, accent: brandColor ?? Color(hex: template.accent))
    }

    private func choose(_ template: AdTemplate) {
        selected = template
        fields.headline = template.headline
        fields.detail = template.detail
        fields.accent = brandColor ?? Color(hex: template.accent)
    }

    private var addButton: some View {
        DSPrimaryButton(String(localized: "editor.template.add", bundle: .module)) {
            guard let data = AdTemplateArt.render(selected.style, fields: fields) else { return }
            onAdd(data, selected.style)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(DS.Palette.screen.opacity(0.96))
    }
}
