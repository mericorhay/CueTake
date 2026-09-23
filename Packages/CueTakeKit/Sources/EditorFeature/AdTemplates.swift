import DesignSystem
import Domain
import SwiftUI
import UIKit

// Picture templates for a sponsored video — a discount code, a price tag, a coupon, a poll, a
// before and after — sorted by the kind of brand they suit. Every line of a template is its own
// field, with the brand's colour, a dark or light look and a choice of face. The template is drawn
// as a picture and laid on the timeline at the playhead like any other picture; what it was drawn
// from is kept on it, so its words can be changed there and the picture drawn again.

/// The kinds of brand the templates are sorted by.
enum AdCategory: String, CaseIterable, Identifiable {
    case beauty, fashion, food, tech, gaming, fitness, travel, finance, home, education, events, partnership

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beauty: AppLocalization.string("editor.template.category.beauty", bundle: .module)
        case .fashion: AppLocalization.string("editor.template.category.fashion", bundle: .module)
        case .food: AppLocalization.string("editor.template.category.food", bundle: .module)
        case .tech: AppLocalization.string("editor.template.category.tech", bundle: .module)
        case .gaming: AppLocalization.string("editor.template.category.gaming", bundle: .module)
        case .fitness: AppLocalization.string("editor.template.category.fitness", bundle: .module)
        case .travel: AppLocalization.string("editor.template.category.travel", bundle: .module)
        case .finance: AppLocalization.string("editor.template.category.finance", bundle: .module)
        case .home: AppLocalization.string("editor.template.category.home", bundle: .module)
        case .education: AppLocalization.string("editor.template.category.education", bundle: .module)
        case .events: AppLocalization.string("editor.template.category.events", bundle: .module)
        case .partnership: AppLocalization.string("editor.template.category.partnership", bundle: .module)
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

/// One line of a template, filled in by the creator.
enum AdSlot: String, CaseIterable {
    case brand, label, title, detail, code, price, oldPrice, number, note, date, place, cta, optionA, optionB, item1, item2, item3

    var name: String {
        switch self {
        case .brand: AppLocalization.string("editor.template.slot.brand", bundle: .module)
        case .label: AppLocalization.string("editor.template.slot.label", bundle: .module)
        case .title: AppLocalization.string("editor.template.slot.title", bundle: .module)
        case .detail: AppLocalization.string("editor.template.slot.detail", bundle: .module)
        case .code: AppLocalization.string("editor.template.slot.code", bundle: .module)
        case .price: AppLocalization.string("editor.template.slot.price", bundle: .module)
        case .oldPrice: AppLocalization.string("editor.template.slot.oldPrice", bundle: .module)
        case .number: AppLocalization.string("editor.template.slot.number", bundle: .module)
        case .note: AppLocalization.string("editor.template.slot.note", bundle: .module)
        case .date: AppLocalization.string("editor.template.slot.date", bundle: .module)
        case .place: AppLocalization.string("editor.template.slot.place", bundle: .module)
        case .cta: AppLocalization.string("editor.template.slot.cta", bundle: .module)
        case .optionA: AppLocalization.string("editor.template.slot.optionA", bundle: .module)
        case .optionB: AppLocalization.string("editor.template.slot.optionB", bundle: .module)
        case .item1: AppLocalization.string("editor.template.slot.item1", bundle: .module)
        case .item2: AppLocalization.string("editor.template.slot.item2", bundle: .module)
        case .item3: AppLocalization.string("editor.template.slot.item3", bundle: .module)
        }
    }
}

/// The faces a template's big lines can take.
enum AdFont: String, CaseIterable {
    case display, clean, mono

    var title: String {
        switch self {
        case .display: AppLocalization.string("editor.template.font.display", bundle: .module)
        case .clean: AppLocalization.string("editor.template.font.clean", bundle: .module)
        case .mono: AppLocalization.string("editor.template.font.mono", bundle: .module)
        }
    }

    func font(_ size: CGFloat) -> Font {
        switch self {
        case .display: DS.fixed(.archivo, .extrabold, size)
        case .clean: DS.fixed(.sans, .semibold, size * 0.94)
        case .mono: DS.fixed(.mono, .medium, size * 0.86)
        }
    }
}

/// How a template is drawn, and which lines it has.
enum AdStyle: String, CaseIterable {
    case codeCard, coupon, priceTag, spotlight, badge, stat, bigTitle, lowerThird, newDrop, countdown, promoStrip
    case review, quote, checklist, beforeAfter, poll, giveaway, ticket, location, linkPill, ctaButton, collab

    var slots: [AdSlot] {
        switch self {
        case .codeCard: [.label, .code, .note, .brand]
        case .coupon: [.number, .label, .code, .date, .brand]
        case .priceTag: [.title, .price, .oldPrice, .brand]
        case .spotlight: [.label, .title, .price, .brand]
        case .badge: [.number, .label, .brand]
        case .stat: [.number, .title, .detail, .brand]
        case .bigTitle: [.brand, .title, .detail]
        case .lowerThird: [.brand, .title, .detail]
        case .newDrop: [.label, .title, .detail, .brand]
        case .countdown: [.title, .detail, .brand]
        case .promoStrip: [.title, .detail]
        case .review: [.title, .detail, .brand]
        case .quote: [.title, .detail]
        case .checklist: [.title, .item1, .item2, .item3, .brand]
        case .beforeAfter: [.optionA, .title, .optionB, .detail]
        case .poll: [.title, .optionA, .optionB]
        case .giveaway: [.title, .item1, .item2, .item3, .brand]
        case .ticket: [.brand, .title, .detail, .date]
        case .location: [.place, .detail, .cta]
        case .linkPill: [.title, .brand]
        case .ctaButton: [.detail, .cta, .brand]
        case .collab: [.brand, .title]
        }
    }

    /// Where it lands on the frame — its centre, from the left and the top — and how wide it is
    /// as a share of the frame's width. Wide on purpose: a card is read on a phone in a second,
    /// and its small lines (a label, a brand) must still be legible after Instagram compresses it.
    var placement: (x: Double, y: Double, width: Double) {
        switch self {
        case .codeCard: (0.5, 0.72, 0.86)
        case .coupon: (0.5, 0.7, 0.9)
        case .priceTag: (0.5, 0.74, 0.84)
        case .spotlight: (0.5, 0.66, 0.84)
        case .badge: (0.75, 0.22, 0.44)
        case .stat: (0.5, 0.3, 0.84)
        case .bigTitle: (0.5, 0.24, 0.94)
        case .lowerThird: (0.5, 0.84, 0.94)
        case .newDrop: (0.5, 0.3, 0.86)
        case .countdown: (0.5, 0.16, 0.9)
        case .promoStrip: (0.5, 0.5, 1.1)
        case .review: (0.5, 0.72, 0.9)
        case .quote: (0.5, 0.3, 0.92)
        case .checklist: (0.5, 0.66, 0.88)
        case .beforeAfter: (0.5, 0.74, 0.94)
        case .poll: (0.5, 0.62, 0.86)
        case .giveaway: (0.5, 0.66, 0.9)
        case .ticket: (0.5, 0.72, 0.92)
        case .location: (0.5, 0.8, 0.84)
        case .linkPill: (0.5, 0.86, 0.78)
        case .ctaButton: (0.5, 0.82, 0.82)
        case .collab: (0.5, 0.14, 0.84)
        }
    }
}

/// One template: a style, a first draft of every line in the viewer's language, and a colour.
struct AdTemplate: Identifiable, Hashable {
    let id: String
    let category: AdCategory
    let style: AdStyle
    let texts: [AdSlot: String]
    /// The colour it suggests when the brand has none of its own.
    let accent: UInt32
    let isLight: Bool

    private static var turkish: Bool { AppLocalization.locale.language.languageCode?.identifier == "tr" }
    private static func say(_ tr: String, _ en: String) -> String { turkish ? tr : en }

    private init(_ id: String, _ category: AdCategory, _ style: AdStyle, _ accent: UInt32, light: Bool = false, _ texts: [AdSlot: String]) {
        self.id = id
        self.category = category
        self.style = style
        self.texts = texts
        self.accent = accent
        self.isLight = light
    }

    static let all: [AdTemplate] = [
        // Beauty
        AdTemplate("beauty.code", .beauty, .codeCard, 0xF7A8C4, [.label: say("İndirim kodu", "Discount code"), .code: "GLOW20", .note: say("Tüm ürünlerde · Pazar'a kadar", "Sitewide · until Sunday"), .brand: "Glow"]),
        AdTemplate("beauty.review", .beauty, .review, 0xF7A8C4, light: true, [.title: say("İki haftada fark ettim, cildim daha parlak", "Two weeks in and my skin is brighter"), .detail: say("14 gündür kullanıyorum", "Using it for 14 days"), .brand: "Glow"]),
        AdTemplate("beauty.new", .beauty, .newDrop, 0xE9C9A6, [.label: say("YENİ", "NEW"), .title: say("C vitamini serumu", "Vitamin C serum"), .detail: say("Şimdi raflarda", "Out now"), .brand: "Glow"]),
        AdTemplate("beauty.beforeafter", .beauty, .beforeAfter, 0xF7A8C4, [.optionA: say("ÖNCE", "BEFORE"), .title: say("Mat ve yorgun", "Dull and tired"), .optionB: say("SONRA", "AFTER"), .detail: say("Aydınlık ve nemli", "Bright and hydrated")]),
        AdTemplate("beauty.checklist", .beauty, .checklist, 0xF7A8C4, light: true, [.title: say("Neden seviyorum", "Why I love it"), .item1: say("Parfümsüz", "Fragrance-free"), .item2: say("Hassas cilde uygun", "Good for sensitive skin"), .item3: say("Hızlı emiliyor", "Absorbs fast"), .brand: "Glow"]),
        // Fashion
        AdTemplate("fashion.title", .fashion, .bigTitle, 0xFFFFFF, [.brand: "Atelier", .title: say("Yeni sezon", "New season"), .detail: say("Koleksiyon yayında", "The collection is live")]),
        AdTemplate("fashion.price", .fashion, .priceTag, 0xD8C3A5, light: true, [.title: say("Keten gömlek", "Linen shirt"), .price: "899 ₺", .oldPrice: "1.299 ₺", .brand: "Atelier"]),
        AdTemplate("fashion.countdown", .fashion, .countdown, 0xFF5A4F, light: true, [.title: say("Son 24 saat", "Last 24 hours"), .detail: say("Sepette %30 indirim", "30% off at checkout"), .brand: "Atelier"]),
        AdTemplate("fashion.strip", .fashion, .promoStrip, 0xFFB840, [.title: say("SEZON SONU", "END OF SEASON"), .detail: "%50"]),
        AdTemplate("fashion.poll", .fashion, .poll, 0xFF5A4F, light: true, [.title: say("Hangisini alayım?", "Which one should I get?"), .optionA: say("Siyah", "Black"), .optionB: say("Bej", "Beige")]),
        // Food & drink
        AdTemplate("food.badge", .food, .badge, 0xFFB840, [.number: "%25", .label: say("İNDİRİM", "OFF"), .brand: "Lezzet"]),
        AdTemplate("food.price", .food, .priceTag, 0xFF7A3D, light: true, [.title: say("Burger menü", "Burger combo"), .price: "149 ₺", .oldPrice: "189 ₺", .brand: "Lezzet"]),
        AdTemplate("food.location", .food, .location, 0xFF5A4F, light: true, [.place: "Lezzet Kadıköy", .detail: say("Moda Cad. No: 12", "12 Moda Street"), .cta: say("Bugün gel", "Come today")]),
        AdTemplate("food.cta", .food, .ctaButton, 0x2FBF71, [.detail: say("İlk siparişe ücretsiz teslimat", "Free delivery on your first order"), .cta: say("Şimdi sipariş ver", "Order now"), .brand: "Lezzet"]),
        AdTemplate("food.coupon", .food, .coupon, 0xFFB840, light: true, [.number: "%20", .label: say("İLK SİPARİŞ", "FIRST ORDER"), .code: "AFIYET", .date: say("31 Ekim'e kadar", "Until 31 October"), .brand: "Lezzet"]),
        // Tech
        AdTemplate("tech.new", .tech, .newDrop, 0x3D8BFF, [.label: say("YENİ", "NEW"), .title: say("Yeni kulaklık", "The new earbuds"), .detail: say("Ön siparişte", "Pre-order now"), .brand: "Pulse"]),
        AdTemplate("tech.stat", .tech, .stat, 0x3D8BFF, [.number: say("2 kat", "2×"), .title: say("daha uzun pil", "the battery life"), .detail: say("Bir ay kullandım", "After a month of use"), .brand: "Pulse"]),
        AdTemplate("tech.spotlight", .tech, .spotlight, 0x6C5CE7, [.label: say("ÖNE ÇIKAN", "SPOTLIGHT"), .title: "Pulse Pro", .price: "4.999 ₺", .brand: "Pulse"]),
        AdTemplate("tech.checklist", .tech, .checklist, 0x3D8BFF, [.title: say("3 sebep", "3 reasons"), .item1: say("Gürültü engelleme", "Noise cancelling"), .item2: say("30 saat pil", "30-hour battery"), .item3: say("Suya dayanıklı", "Water resistant"), .brand: "Pulse"]),
        AdTemplate("tech.code", .tech, .codeCard, 0x6C5CE7, [.label: say("Kodla ek indirim", "Extra off with code"), .code: "TECH15", .note: say("Sadece bu hafta", "This week only"), .brand: "Pulse"]),
        // Gaming
        AdTemplate("gaming.collab", .gaming, .collab, 0x9B5CFF, [.brand: "Nova Games", .title: say("İş birliği", "Partnership")]),
        AdTemplate("gaming.code", .gaming, .codeCard, 0x9B5CFF, [.label: say("Oyun içi kod", "In-game code"), .code: "LOOT2026", .note: say("Efsanevi kostüm hediye", "A legendary skin, free"), .brand: "Nova Games"]),
        AdTemplate("gaming.countdown", .gaming, .countdown, 0x00E5A8, [.title: say("Etkinlik bitiyor", "Event ends soon"), .detail: say("Son 3 gün", "3 days left"), .brand: "Nova Games"]),
        AdTemplate("gaming.giveaway", .gaming, .giveaway, 0x9B5CFF, [.title: say("Çekiliş", "Giveaway"), .item1: say("Takip et", "Follow"), .item2: say("Arkadaşını etiketle", "Tag a friend"), .item3: say("Yorum yaz", "Leave a comment"), .brand: "Nova Games"]),
        AdTemplate("gaming.poll", .gaming, .poll, 0x00E5A8, [.title: say("Hangi karakter?", "Which character?"), .optionA: say("Savaşçı", "Warrior"), .optionB: say("Büyücü", "Mage")]),
        // Fitness
        AdTemplate("fitness.title", .fitness, .bigTitle, 0xC6F24A, [.brand: "Fit+", .title: say("30 gün meydan okuma", "30-day challenge"), .detail: say("Benimle başla", "Start with me")]),
        AdTemplate("fitness.badge", .fitness, .badge, 0xC6F24A, [.number: "%40", .label: say("ÜYELİK", "MEMBERSHIP"), .brand: "Fit+"]),
        AdTemplate("fitness.stat", .fitness, .stat, 0xC6F24A, [.number: "-6 kg", .title: say("8 haftada", "in 8 weeks"), .detail: say("Programı takip ettim", "I followed the plan"), .brand: "Fit+"]),
        AdTemplate("fitness.beforeafter", .fitness, .beforeAfter, 0xC6F24A, [.optionA: say("1. GÜN", "DAY 1"), .title: say("10 şınav", "10 push-ups"), .optionB: say("30. GÜN", "DAY 30"), .detail: say("40 şınav", "40 push-ups")]),
        AdTemplate("fitness.cta", .fitness, .ctaButton, 0xC6F24A, [.detail: say("İlk hafta ücretsiz", "First week free"), .cta: say("Hemen katıl", "Join now"), .brand: "Fit+"]),
        // Travel
        AdTemplate("travel.ticket", .travel, .ticket, 0x1FB5C9, light: true, [.brand: "Rota", .title: say("Kapadokya kaçamağı", "A weekend in Cappadocia"), .detail: say("3 gece · Kahvaltı dahil", "3 nights · Breakfast included"), .date: "12–15 EKİM"]),
        AdTemplate("travel.title", .travel, .bigTitle, 0x1FB5C9, [.brand: "Rota", .title: say("Nereye gidiyoruz?", "Where to next?"), .detail: say("Rota linkte", "Route in the link")]),
        AdTemplate("travel.link", .travel, .linkPill, 0xFFB840, [.title: say("Erken rezervasyon linkte", "Early booking in the link"), .brand: "Rota"]),
        AdTemplate("travel.location", .travel, .location, 0x1FB5C9, light: true, [.place: "Uçhisar", .detail: say("Kapadokya, Nevşehir", "Cappadocia, Türkiye"), .cta: say("Haritada gör", "See on the map")]),
        AdTemplate("travel.coupon", .travel, .coupon, 0x1FB5C9, [.number: "%15", .label: say("OTEL İNDİRİMİ", "HOTEL DISCOUNT"), .code: "ROTA15", .date: say("Kasım sonuna kadar", "Until the end of November"), .brand: "Rota"]),
        // Apps & finance
        AdTemplate("finance.code", .finance, .codeCard, 0x2FBF71, [.label: say("Davet kodu", "Invite code"), .code: "HOSGELDIN", .note: say("İlk yatırıma 100 ₺ hediye", "₺100 on your first deposit"), .brand: "Cüzdan"]),
        AdTemplate("finance.link", .finance, .linkPill, 0x3D8BFF, [.title: say("Uygulamayı indir", "Get the app"), .brand: "Cüzdan"]),
        AdTemplate("finance.stat", .finance, .stat, 0x2FBF71, [.number: "%0", .title: say("komisyon", "commission"), .detail: say("İlk 3 ay", "For the first 3 months"), .brand: "Cüzdan"]),
        AdTemplate("finance.checklist", .finance, .checklist, 0x2FBF71, light: true, [.title: say("2 dakikada hesap", "An account in 2 minutes"), .item1: say("Uygulamayı indir", "Download the app"), .item2: say("Kodu gir", "Enter the code"), .item3: say("Hediyeni al", "Get your gift"), .brand: "Cüzdan"]),
        AdTemplate("finance.cta", .finance, .ctaButton, 0x3D8BFF, [.detail: say("Linki profilde", "Link in profile"), .cta: say("Ücretsiz başla", "Start free"), .brand: "Cüzdan"]),
        // Home & living
        AdTemplate("home.price", .home, .priceTag, 0xB08968, light: true, [.title: say("Kahve makinesi", "Coffee machine"), .price: "2.499 ₺", .oldPrice: "3.199 ₺", .brand: "Evim"]),
        AdTemplate("home.review", .home, .review, 0xB08968, light: true, [.title: say("Sabahlarım gerçekten değişti", "My mornings really changed"), .detail: say("Her gün kullanıyorum", "I use it every day"), .brand: "Evim"]),
        AdTemplate("home.spotlight", .home, .spotlight, 0xB08968, [.label: say("ÇOK SATAN", "BESTSELLER"), .title: say("Keten nevresim", "Linen bedding"), .price: "1.199 ₺", .brand: "Evim"]),
        AdTemplate("home.quote", .home, .quote, 0xB08968, [.title: say("Ev, en çok vakit geçirdiğin yer olmalı.", "Home should be your favourite place."), .detail: "Evim"]),
        AdTemplate("home.strip", .home, .promoStrip, 0xB08968, [.title: say("EV HAFTASI", "HOME WEEK"), .detail: "%30"]),
        // Education
        AdTemplate("education.ticket", .education, .ticket, 0x6C5CE7, light: true, [.brand: "Akademi", .title: say("Canlı ders", "Live class"), .detail: say("Ücretsiz · Kayıt linkte", "Free · Sign up in the link"), .date: say("SALI 20:00", "TUE 8 PM")]),
        AdTemplate("education.badge", .education, .badge, 0x6C5CE7, [.number: "%50", .label: say("İLK AY", "FIRST MONTH"), .brand: "Akademi"]),
        AdTemplate("education.checklist", .education, .checklist, 0x6C5CE7, [.title: say("Bu derste", "In this class"), .item1: say("Temelleri öğren", "Learn the basics"), .item2: say("Proje yap", "Build a project"), .item3: say("Sertifika al", "Get a certificate"), .brand: "Akademi"]),
        AdTemplate("education.stat", .education, .stat, 0x6C5CE7, [.number: "12.000+", .title: say("öğrenci", "students"), .detail: say("Sen de katıl", "Join them"), .brand: "Akademi"]),
        AdTemplate("education.quote", .education, .quote, 0x6C5CE7, light: true, [.title: say("Hiç bu kadar kolay öğrenmemiştim.", "I've never learned this easily."), .detail: say("Bir öğrenci", "A student")]),
        // Events
        AdTemplate("events.ticket", .events, .ticket, 0xFF5A4F, light: true, [.brand: "Fest", .title: say("Yaz festivali", "Summer festival"), .detail: say("İstanbul · Kapılar 18:00", "Istanbul · Doors 6 pm"), .date: "12.10"]),
        AdTemplate("events.countdown", .events, .countdown, 0xFF5A4F, light: true, [.title: say("Biletler tükeniyor", "Tickets selling out"), .detail: say("Son 100 bilet", "Last 100 tickets"), .brand: "Fest"]),
        AdTemplate("events.giveaway", .events, .giveaway, 0xFF5A4F, [.title: say("2 bilet kazan", "Win 2 tickets"), .item1: say("Beğen", "Like"), .item2: say("Arkadaşını etiketle", "Tag a friend"), .item3: say("Paylaş", "Share"), .brand: "Fest"]),
        AdTemplate("events.location", .events, .location, 0xFF5A4F, [.place: "KüçükÇiftlik Park", .detail: say("Maçka, İstanbul", "Maçka, Istanbul"), .cta: say("Yol tarifi", "Directions")]),
        AdTemplate("events.strip", .events, .promoStrip, 0xFF5A4F, [.title: say("BİLETLER SATIŞTA", "TICKETS ON SALE"), .detail: "LIVE"]),
        // Partnership
        AdTemplate("partnership.lower", .partnership, .lowerThird, 0xFF5A4F, [.brand: say("Marka", "Brand"), .title: say("İş birliği", "Paid partnership"), .detail: say("Bu video reklam içerir", "This video contains an ad")]),
        AdTemplate("partnership.collab", .partnership, .collab, 0xFFFFFF, [.brand: say("Marka", "Brand"), .title: say("İş birliği", "Partnership")]),
        AdTemplate("partnership.cta", .partnership, .ctaButton, 0xFF5A4F, light: true, [.detail: say("Kodum açıklamada", "My code is in the description"), .cta: say("Linke dokun", "Tap the link"), .brand: say("Marka", "Brand")]),
        AdTemplate("partnership.link", .partnership, .linkPill, 0xC6F24A, [.title: say("Link bio'da", "Link in bio"), .brand: say("Marka", "Brand")]),
    ]
}

/// What the creator fills in.
struct AdTemplateFields: Equatable {
    var texts: [AdSlot: String]
    var accent: Color
    var isLight: Bool
    var font: AdFont

    func text(_ slot: AdSlot) -> String { texts[slot] ?? "" }

    /// For keeping on the picture.
    func stored(templateID: String) -> OverlayTemplate {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(accent).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return OverlayTemplate(
            id: templateID,
            texts: Dictionary(uniqueKeysWithValues: texts.map { ($0.key.rawValue, $0.value) }),
            accent: RGBAColor(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha)),
            isLight: isLight,
            font: font.rawValue
        )
    }

    init(texts: [AdSlot: String], accent: Color, isLight: Bool, font: AdFont) {
        self.texts = texts
        self.accent = accent
        self.isLight = isLight
        self.font = font
    }

    init(stored: OverlayTemplate) {
        texts = Dictionary(uniqueKeysWithValues: stored.texts.compactMap { key, value in AdSlot(rawValue: key).map { ($0, value) } })
        accent = Color(.sRGB, red: stored.accent.red, green: stored.accent.green, blue: stored.accent.blue, opacity: stored.accent.alpha)
        isLight = stored.isLight
        font = AdFont(rawValue: stored.font) ?? .display
    }
}

// MARK: - Drawing

/// A template drawn at 360 points wide; it is rendered at three times that for the video.
struct AdTemplateArt: View {
    let style: AdStyle
    let fields: AdTemplateFields

    static let width: CGFloat = 360

    private var accent: Color { fields.accent }
    /// Text on the accent: near-black on light colours, white on dark ones.
    private var onAccent: Color { Self.isLight(fields.accent) ? Color(white: 0.06) : .white }
    /// The card: white or near-black.
    private var paper: Color { fields.isLight ? .white : Color(white: 0.07) }
    private var ink: Color { fields.isLight ? Color(white: 0.06) : .white }
    private var sub: Color { fields.isLight ? Color(white: 0.42) : Color(white: 0.7) }
    /// The accent where it is text on the card: kept readable when the accent is close to the card.
    private var accentInk: Color {
        let accentIsLight = Self.isLight(fields.accent)
        if fields.isLight, accentIsLight { return Color(white: 0.06) }
        if !fields.isLight, !accentIsLight, Self.luminance(fields.accent) < 0.2 { return .white }
        return accent
    }

    private func t(_ slot: AdSlot) -> String { fields.text(slot) }
    private func big(_ size: CGFloat) -> Font { fields.font.font(size) }
    private func sans(_ weight: DS.FontWeight, _ size: CGFloat) -> Font { DS.fixed(.sans, weight, size) }
    private func mono(_ size: CGFloat) -> Font { DS.fixed(.mono, .medium, size) }

    var body: some View {
        Group {
            switch style {
            case .codeCard: codeCard
            case .coupon: coupon
            case .priceTag: priceTag
            case .spotlight: spotlight
            case .badge: badge
            case .stat: stat
            case .bigTitle: bigTitle
            case .lowerThird: lowerThird
            case .newDrop: newDrop
            case .countdown: countdown
            case .promoStrip: promoStrip
            case .review: review
            case .quote: quote
            case .checklist: checklist
            case .beforeAfter: beforeAfter
            case .poll: poll
            case .giveaway: giveaway
            case .ticket: ticket
            case .location: location
            case .linkPill: linkPill
            case .ctaButton: ctaButton
            case .collab: collab
            }
        }
        .frame(width: Self.width)
    }

    private func card(_ radius: CGFloat = 24) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(paper.opacity(fields.isLight ? 1 : 0.94))
            .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
    }

    @ViewBuilder
    private func line(_ slot: AdSlot, _ font: Font, _ color: Color, tracking: CGFloat = 0, lines: Int = 1) -> some View {
        if !t(slot).isEmpty {
            Text(verbatim: t(slot))
                .font(font)
                .tracking(tracking)
                .foregroundStyle(color)
                .lineLimit(lines)
                .minimumScaleFactor(0.5)
        }
    }

    private var codeCard: some View {
        VStack(spacing: 12) {
            line(.label, mono(13), sub, tracking: 2.5)
            Text(verbatim: t(.code).isEmpty ? "CODE" : t(.code))
                .font(big(46))
                .foregroundStyle(onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(onAccent.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        .padding(6)
                )
            line(.note, sans(.medium, 14), ink, lines: 2)
            line(.brand, mono(12), sub, tracking: 2)
        }
        .padding(20)
        .background(card(26))
    }

    private var coupon: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(verbatim: t(.number))
                    .font(big(44))
                    .foregroundStyle(onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                line(.label, mono(11), onAccent.opacity(0.85), tracking: 1.5, lines: 2)
            }
            .multilineTextAlignment(.center)
            .padding(12)
            .frame(width: 130)
            .frame(maxHeight: .infinity)
            .background(accent)
            VStack(alignment: .leading, spacing: 6) {
                line(.brand, mono(11), sub, tracking: 2)
                HStack(spacing: 6) {
                    Image(systemName: "scissors").font(.system(size: 12, weight: .bold)).foregroundStyle(sub)
                    line(.code, big(26), ink)
                }
                line(.date, sans(.medium, 13), sub)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(paper)
        }
        .frame(height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [8, 5])))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
    }

    private var priceTag: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                line(.brand, mono(11), sub, tracking: 2)
                line(.title, sans(.semibold, 22), ink, lines: 2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 2) {
                if !t(.oldPrice).isEmpty {
                    Text(verbatim: t(.oldPrice))
                        .font(sans(.medium, 14))
                        .strikethrough(true, color: onAccent.opacity(0.7))
                        .foregroundStyle(onAccent.opacity(0.75))
                }
                Text(verbatim: t(.price))
                    .font(big(28))
                    .foregroundStyle(onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(.horizontal, 16)
            .frame(minWidth: 120)
            .frame(maxHeight: .infinity)
            .background(accent)
        }
        .frame(height: 100)
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .leading) {
            Circle().fill(sub.opacity(0.4)).frame(width: 12, height: 12).padding(.leading, 7)
        }
        .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
    }

    private var spotlight: some View {
        VStack(spacing: 10) {
            line(.label, mono(12), onAccent, tracking: 2)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(accent))
            line(.title, big(34), ink, lines: 2)
                .multilineTextAlignment(.center)
            if !t(.price).isEmpty {
                Text(verbatim: t(.price))
                    .font(big(28))
                    .foregroundStyle(accentInk)
            }
            line(.brand, mono(12), sub, tracking: 2)
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                card(30)
                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(0.35), .clear], center: .center, startRadius: 4, endRadius: 150))
                    .frame(width: 300, height: 300)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        )
    }

    private var badge: some View {
        ZStack {
            StarBurst(points: 18)
                .fill(accent)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
            VStack(spacing: 0) {
                Text(verbatim: t(.number))
                    .font(big(84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                line(.label, mono(18), onAccent, tracking: 2)
                line(.brand, sans(.semibold, 15), onAccent.opacity(0.8))
                    .padding(.top, 4)
            }
            .foregroundStyle(onAccent)
            .padding(44)
        }
        .frame(width: Self.width, height: Self.width)
        .rotationEffect(.degrees(-10))
    }

    private var stat: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: t(.number))
                .font(big(78))
                .foregroundStyle(accentInk)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            line(.title, sans(.semibold, 24), ink, lines: 2)
            Rectangle().fill(accent).frame(width: 56, height: 5).padding(.vertical, 6)
            line(.detail, sans(.regular, 15), sub, lines: 2)
            line(.brand, mono(12), sub, tracking: 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card(26))
    }

    private var bigTitle: some View {
        VStack(spacing: 8) {
            line(.brand, mono(14), .white.opacity(0.9), tracking: 4)
            Text(verbatim: t(.title))
                .font(big(56))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .shadow(color: .black.opacity(0.55), radius: 12, y: 4)
            Capsule().fill(accent).frame(width: 110, height: 8)
            line(.detail, sans(.semibold, 18), .white)
                .shadow(color: .black.opacity(0.55), radius: 8, y: 3)
        }
        .padding(.vertical, 10)
    }

    private var lowerThird: some View {
        HStack(spacing: 0) {
            Text(verbatim: t(.brand).uppercased())
                .font(big(20))
                .foregroundStyle(onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 16)
                .frame(maxWidth: 140)
                .frame(maxHeight: .infinity)
                .background(accent)
            VStack(alignment: .leading, spacing: 2) {
                line(.title, sans(.semibold, 18), ink)
                line(.detail, sans(.regular, 13), sub)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(paper)
        }
        .frame(height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
    }

    private var newDrop: some View {
        VStack(spacing: 10) {
            line(.label, big(22), onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(accent))
                .rotationEffect(.degrees(-4))
            line(.title, big(40), ink, lines: 2)
                .multilineTextAlignment(.center)
            line(.detail, sans(.semibold, 16), sub)
            line(.brand, mono(12), sub, tracking: 2)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(card(26))
    }

    private var countdown: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill").font(.system(size: 18, weight: .bold))
                Text(verbatim: t(.title).uppercased())
                    .font(big(26))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .foregroundStyle(onAccent)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(accent)
            HStack {
                line(.detail, sans(.semibold, 17), ink)
                Spacer(minLength: 8)
                line(.brand, mono(12), sub, tracking: 1.5)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(paper)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
    }

    private var promoStrip: some View {
        let unit = [t(.title), t(.detail)].filter { !$0.isEmpty }.joined(separator: "  ✦  ")
        return Text(verbatim: Array(repeating: unit, count: 4).joined(separator: "  ✦  "))
            .font(big(26))
            .foregroundStyle(onAccent)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, 12)
            .frame(width: Self.width * 1.3)
            .background(accent)
            .rotationEffect(.degrees(-5))
            .frame(width: Self.width, height: 110)
            .clipped()
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill").font(.system(size: 16)).foregroundStyle(Self.isLight(accent) && fields.isLight ? Color(hex: 0xF5A623) : accent)
                }
            }
            if !t(.title).isEmpty {
                Text(verbatim: "“\(t(.title))”")
                    .font(sans(.semibold, 21))
                    .foregroundStyle(ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
            }
            HStack {
                line(.detail, sans(.regular, 14), sub)
                Spacer(minLength: 8)
                if !t(.brand).isEmpty {
                    Text(verbatim: t(.brand))
                        .font(mono(12))
                        .foregroundStyle(onAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(accent))
                }
            }
        }
        .padding(20)
        .background(card(22))
    }

    private var quote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "“")
                .font(big(90))
                .foregroundStyle(accent)
                .frame(height: 56, alignment: .top)
            line(.title, big(32), .white, lines: 4)
                .shadow(color: .black.opacity(0.55), radius: 10, y: 4)
            if !t(.detail).isEmpty {
                Text(verbatim: "— \(t(.detail))")
                    .font(sans(.semibold, 16))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.55), radius: 8, y: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            line(.title, big(26), ink, lines: 2)
            ForEach([AdSlot.item1, .item2, .item3], id: \.self) { slot in
                if !t(slot).isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(onAccent)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(accent))
                        Text(verbatim: t(slot))
                            .font(sans(.semibold, 17))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
            line(.brand, mono(12), sub, tracking: 2)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card(24))
    }

    private var beforeAfter: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                line(.optionA, mono(12), sub, tracking: 2)
                line(.title, sans(.semibold, 18), ink, lines: 2)
            }
            .multilineTextAlignment(.center)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(paper)
            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(onAccent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(accent))
                .zIndex(1)
                .padding(.horizontal, -17)
            VStack(spacing: 6) {
                line(.optionB, mono(12), onAccent.opacity(0.85), tracking: 2)
                line(.detail, sans(.semibold, 18), onAccent, lines: 2)
            }
            .multilineTextAlignment(.center)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(accent)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
    }

    private var poll: some View {
        VStack(spacing: 12) {
            line(.title, sans(.semibold, 20), ink, lines: 2)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                pollOption(t(.optionA), filled: true)
                pollOption(t(.optionB), filled: false)
            }
        }
        .padding(18)
        .background(card(22))
    }

    private func pollOption(_ text: String, filled: Bool) -> some View {
        Text(verbatim: text)
            .font(sans(.semibold, 17))
            .foregroundStyle(filled ? onAccent : ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(filled ? accent : sub.opacity(0.15)))
    }

    private var giveaway: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(onAccent)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent))
                line(.title, big(28), ink, lines: 2)
            }
            ForEach(Array([AdSlot.item1, .item2, .item3].enumerated()), id: \.offset) { index, slot in
                if !t(slot).isEmpty {
                    HStack(spacing: 10) {
                        Text(verbatim: "\(index + 1)")
                            .font(big(15))
                            .foregroundStyle(accentInk)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(accentInk, lineWidth: 2))
                        Text(verbatim: t(slot))
                            .font(sans(.semibold, 17))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
            line(.brand, mono(12), sub, tracking: 2)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card(24))
    }

    private var ticket: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                line(.brand, mono(11), sub, tracking: 2)
                line(.title, big(26), ink, lines: 2)
                line(.detail, sans(.medium, 14), sub, lines: 2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(paper)
            VStack(spacing: 6) {
                Image(systemName: "ticket.fill").font(.system(size: 20, weight: .semibold))
                line(.date, mono(13), onAccent, lines: 2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(onAccent)
            .padding(8)
            .frame(width: 92)
            .frame(maxHeight: .infinity)
            .background(accent)
        }
        .frame(height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            // Where the ticket would be torn: a dashed line and two notches.
            HStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .foregroundStyle(sub.opacity(0.5))
                    .frame(width: 1)
                    .padding(.vertical, 14)
                    .padding(.trailing, 92)
            }
        }
        .overlay {
            HStack {
                Spacer()
                VStack {
                    Circle().frame(width: 18, height: 18).offset(y: -9)
                    Spacer()
                    Circle().frame(width: 18, height: 18).offset(y: 9)
                }
                .frame(width: 18)
                .padding(.trailing, 83)
            }
            .blendMode(.destinationOut)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
    }

    private var location: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(onAccent)
                .frame(width: 50, height: 50)
                .background(Circle().fill(accent))
            VStack(alignment: .leading, spacing: 2) {
                line(.place, sans(.bold, 19), ink)
                line(.detail, sans(.regular, 14), sub)
            }
            Spacer(minLength: 4)
            if !t(.cta).isEmpty {
                Text(verbatim: t(.cta))
                    .font(sans(.semibold, 13))
                    .foregroundStyle(accentInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .overlay(Capsule().stroke(accentInk.opacity(0.6), lineWidth: 1.5))
            }
        }
        .padding(12)
        .background(Capsule().fill(paper).shadow(color: .black.opacity(0.28), radius: 12, y: 6))
    }

    private var linkPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(onAccent)
                .frame(width: 42, height: 42)
                .background(Circle().fill(accent))
            VStack(alignment: .leading, spacing: 1) {
                line(.title, sans(.semibold, 18), ink)
                line(.brand, sans(.regular, 13), sub)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .padding(.trailing, 12)
        .background(Capsule().fill(paper).shadow(color: .black.opacity(0.28), radius: 12, y: 6))
    }

    private var ctaButton: some View {
        VStack(spacing: 10) {
            line(.detail, sans(.semibold, 16), .white, lines: 2)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
            HStack(spacing: 10) {
                Text(verbatim: t(.cta))
                    .font(big(24))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Image(systemName: "arrow.right").font(.system(size: 18, weight: .heavy))
            }
            .foregroundStyle(onAccent)
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(Capsule().fill(accent).shadow(color: accent.opacity(0.5), radius: 16, y: 8))
            line(.brand, mono(12), .white.opacity(0.85), tracking: 2)
                .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
        }
    }

    private var collab: some View {
        HStack(spacing: 10) {
            Text(verbatim: t(.brand).uppercased())
                .font(big(20))
                .foregroundStyle(onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(accent))
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(ink)
            line(.title, sans(.semibold, 17), ink)
        }
        .padding(8)
        .padding(.trailing, 10)
        .background(Capsule().fill(paper.opacity(0.9)))
        .overlay(Capsule().stroke(sub.opacity(0.3), lineWidth: 1))
    }

    static func luminance(_ color: Color) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return Double(0.299 * red + 0.587 * green + 0.114 * blue)
    }

    static func isLight(_ color: Color) -> Bool { luminance(color) > 0.6 }

    /// The template as a picture with a clear background, three times its drawn size.
    static func render(_ style: AdStyle, fields: AdTemplateFields) -> Data? {
        let renderer = ImageRenderer(content: AdTemplateArt(style: style, fields: fields).padding(18))
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
        let inner = outer * 0.87
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

/// A template drawn small inside a box of its own: scaled to fit and clipped, so it never spills
/// over its neighbours.
private struct TemplateThumbnail: View {
    let style: AdStyle
    let fields: AdTemplateFields
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / (AdTemplateArt.width + 40), height / (style == .badge ? AdTemplateArt.width + 40 : 260))
            ZStack {
                LinearGradient(colors: [Color(hex: 0x3A2A24), Color(hex: 0x141416)], startPoint: .top, endPoint: .bottom)
                AdTemplateArt(style: style, fields: fields)
                    .fixedSize()
                    .scaleEffect(min(1, scale))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

// MARK: - The sheet

/// Pick a template, fill in every line, put it on the timeline — or change one already there.
struct AdTemplateSheet: View {
    /// The brand kit's colour, offered first when there is one.
    let brandColor: Color?
    /// A template picture being changed, or nil for a new one.
    let editing: OverlayTemplate?
    let onAdd: (Data, AdStyle, OverlayTemplate) -> Void
    let onClose: () -> Void

    @State private var category: AdCategory?
    @State private var selected = AdTemplate.all[0]
    @State private var fields = AdTemplateFields(texts: [:], accent: .red, isLight: false, font: .display)
    @State private var loaded = false
    @AppStorage("editor.template.brand") private var savedBrand = ""

    private var swatches: [Color] {
        let presets: [UInt32] = [0xFF5A4F, 0xC6F24A, 0xFFB840, 0xF7A8C4, 0x3D8BFF, 0x9B5CFF, 0x1FB5C9, 0x2FBF71, 0xB08968, 0x111111, 0xFFFFFF]
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
                    TemplateThumbnail(style: selected.style, fields: fields, height: selected.style == .badge ? 300 : 250)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(DS.Palette.hairline(0.1), lineWidth: 1))
                        .padding(.top, 8)
                        .animation(DS.Motion.settle, value: selected)
                        .accessibilityHidden(true)
                    form
                    look
                    if editing == nil {
                        categories
                        grid
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.Palette.screen)
            .navigationTitle(AppLocalization.string(titleKey, bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("editor.template.cancel", bundle: .module), action: onClose)
                }
            }
            .safeAreaInset(edge: .bottom) { addButton }
        }
        .tint(DS.Palette.lime)
        .onAppear(perform: load)
    }

    private var titleKey: String.LocalizationValue {
        editing == nil ? "editor.template.title" : "editor.template.editTitle"
    }

    private var actionKey: String.LocalizationValue {
        editing == nil ? "editor.template.add" : "editor.template.save"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let editing, let template = AdTemplate.all.first(where: { $0.id == editing.id }) {
            selected = template
            fields = AdTemplateFields(stored: editing)
        } else {
            choose(selected)
        }
    }

    /// One field for every line the chosen template has.
    private var form: some View {
        VStack(spacing: 8) {
            ForEach(selected.style.slots, id: \.self) { slot in
                field(slot)
            }
        }
    }

    private func field(_ slot: AdSlot) -> some View {
        let binding = Binding(
            get: { fields.text(slot) },
            set: { value in
                fields.texts[slot] = value
                if slot == .brand { savedBrand = value }
            }
        )
        return HStack(spacing: 12) {
            Text(verbatim: slot.name.uppercased())
                .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.56))
                .frame(width: 84, alignment: .leading)
            TextField(slot.name, text: binding)
                .dsFont(.sans, .semibold, 15)
                .foregroundStyle(DS.Palette.ink)
                .frame(minHeight: 46)
        }
        .padding(.horizontal, 14)
        .dsCard(radius: 14)
    }

    /// Colour, dark or light, and the face of the big lines.
    private var look: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(swatches.enumerated()), id: \.offset) { _, color in
                        Button {
                            withAnimation(DS.Motion.snap) { fields.accent = color }
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 32, height: 32)
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
            HStack(spacing: 8) {
                option(AppLocalization.string("editor.template.dark", bundle: .module), isOn: !fields.isLight) { fields.isLight = false }
                option(AppLocalization.string("editor.template.light", bundle: .module), isOn: fields.isLight) { fields.isLight = true }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(AdFont.allCases, id: \.self) { face in
                    option(face.title, isOn: fields.font == face) { fields.font = face }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func option(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(DS.Motion.snap) { action() }
        } label: {
            Text(verbatim: title)
                .dsFont(.sans, .semibold, 13)
                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.8))
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(Capsule().fill(isOn ? DS.Palette.lime : DS.Palette.hairline(0.07)))
        }
        .buttonStyle(.dsPress)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var categories: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(nil, title: AppLocalization.string("editor.template.all", bundle: .module), symbol: "square.grid.2x2")
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
                Text(verbatim: title).dsFont(.sans, .semibold, 13)
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
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
            ForEach(shown) { template in
                Button {
                    withAnimation(DS.Motion.settle) { choose(template) }
                } label: {
                    VStack(spacing: 6) {
                        TemplateThumbnail(style: template.style, fields: thumbnailFields(template), height: 130)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(selected == template ? DS.Palette.lime : DS.Palette.hairline(0.08), lineWidth: selected == template ? 2 : 1)
                            )
                        Text(verbatim: template.category.title)
                            .dsFont(.sans, .medium, 11)
                            .foregroundStyle(DS.Palette.ink(0.6))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.dsPressCard)
            }
        }
    }

    /// Each template in the grid with its own words and the brand typed so far.
    private func thumbnailFields(_ template: AdTemplate) -> AdTemplateFields {
        var texts = template.texts
        if !savedBrand.isEmpty, template.style.slots.contains(.brand) { texts[.brand] = savedBrand }
        return AdTemplateFields(texts: texts, accent: brandColor ?? Color(hex: template.accent), isLight: template.isLight, font: fields.font)
    }

    private func choose(_ template: AdTemplate) {
        selected = template
        var texts = template.texts
        if !savedBrand.isEmpty, template.style.slots.contains(.brand) { texts[.brand] = savedBrand }
        fields.texts = texts
        fields.accent = brandColor ?? Color(hex: template.accent)
        fields.isLight = template.isLight
    }

    private var addButton: some View {
        DSPrimaryButton(AppLocalization.string(actionKey, bundle: .module)) {
            guard let data = AdTemplateArt.render(selected.style, fields: fields) else { return }
            onAdd(data, selected.style, fields.stored(templateID: selected.id))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(DS.Palette.screen.opacity(0.96))
    }
}

// MARK: - The AI's hand

extension AdTemplate {
    /// The template a request names: by its id, else the first of its style.
    static func match(_ request: TemplateRequest) -> AdTemplate? {
        if let id = request.template, let named = all.first(where: { $0.id == id }) { return named }
        guard let wanted = request.style?.lowercased() else { return nil }
        return all.first { $0.style.rawValue.lowercased() == wanted }
    }
}

extension EditorModel {
    /// A template picture the AI asked for: its lines as written, the rest empty, in its style's
    /// usual place unless it said where.
    func aiAddTemplate(_ request: TemplateRequest, id: UUID, at playhead: Double) -> [AITarget]? {
        guard let template = AdTemplate.match(request) else { return nil }
        var texts: [AdSlot: String] = [:]
        for slot in template.style.slots {
            if let value = request.texts[slot.rawValue] { texts[slot] = value }
        }
        if texts[.brand] == nil, template.style.slots.contains(.brand),
           let brand = UserDefaults.standard.string(forKey: "editor.template.brand"), !brand.isEmpty {
            texts[.brand] = brand
        }
        let fields = AdTemplateFields(
            texts: texts,
            accent: request.color.flatMap { RGBAColor(hex: $0) }.map(CaptionOverlay.color) ?? Color(hex: template.accent),
            isLight: request.light ?? template.isLight,
            font: request.font.flatMap(AdFont.init(rawValue:)) ?? .display
        )
        guard let data = AdTemplateArt.render(template.style, fields: fields), let stored = storeOverlayImage(data) else { return nil }
        let spot = template.style.placement
        let start = max(0, request.start ?? playhead)
        let length = request.duration ?? request.end.map { $0 - start } ?? 4
        var overlay = Overlay(
            id: id,
            content: .image(relativePath: stored.path, aspect: stored.aspect),
            start: MediaTime(seconds: start),
            duration: MediaTime(seconds: max(Overlay.shortest, length)),
            transform: OverlayTransform(x: request.x ?? spot.x, y: request.y ?? spot.y, scale: request.scale ?? spot.width / 0.5),
            animation: .pop
        )
        overlay.template = fields.stored(templateID: template.id)
        project.overlays.append(overlay)
        overlayImages[id] = stored.image
        // Through the one door every overlay edit uses, for its limits.
        updateOverlay(id) { _ in }
        return [.overlay(id)]
    }

    /// New lines or a new look for a template picture already on the video. A line written empty
    /// is cleared; lines not written stay.
    func aiEditTemplate(_ id: UUID, _ request: TemplateRequest) -> [AITarget]? {
        guard let overlay = project.overlays.first(where: { $0.id == id }), let stored = overlay.template else { return nil }
        let current = AdTemplate.all.first { $0.id == stored.id }
        guard let template = (request.style != nil || request.template != nil ? AdTemplate.match(request) : nil) ?? current else { return nil }
        var fields = AdTemplateFields(stored: stored)
        for (name, value) in request.texts {
            guard let slot = AdSlot(rawValue: name) else { continue }
            fields.texts[slot] = value
        }
        if let color = request.color.flatMap({ RGBAColor(hex: $0) }) { fields.accent = CaptionOverlay.color(color) }
        if let light = request.light { fields.isLight = light }
        if let font = request.font.flatMap(AdFont.init(rawValue:)) { fields.font = font }
        guard let data = AdTemplateArt.render(template.style, fields: fields) else { return nil }
        replaceTemplateImage(id, with: data, template: fields.stored(templateID: template.id))
        if request.start != nil || request.duration != nil || request.end != nil || request.x != nil || request.y != nil || request.scale != nil {
            updateOverlay(id, coalescing: "ai") {
                if let start = request.start { $0.start = MediaTime(seconds: max(0, start)) }
                if let length = request.duration {
                    $0.duration = MediaTime(seconds: max(Overlay.shortest, length))
                } else if let end = request.end {
                    $0.duration = MediaTime(seconds: max(Overlay.shortest, end - $0.start.seconds))
                }
                if let x = request.x { $0.transform.x = x }
                if let y = request.y { $0.transform.y = y }
                if let scale = request.scale { $0.transform.scale = scale }
            }
        }
        return [.overlay(id)]
    }
}
