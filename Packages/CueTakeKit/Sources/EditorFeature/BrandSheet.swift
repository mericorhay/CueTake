import DesignSystem
import Domain
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Everything the editor needs to put a brand and a way of working on a video. The app owns the
/// brand and the templates; the editor only shows them and says what was pressed.
public struct BrandTools {
    public var kit: BrandKit
    public var templates: [VideoTemplate]
    /// Whether a logo file exists to draw.
    public var hasLogo: Bool
    public var setKit: (BrandKit) -> Void
    public var applyKit: () -> Void
    public var pickLogo: () -> Void
    public var applyTemplate: (VideoTemplate) -> Void
    public var saveTemplate: (String) -> Void
    public var deleteTemplate: (VideoTemplate.ID) -> Void

    public init(
        kit: BrandKit,
        templates: [VideoTemplate],
        hasLogo: Bool,
        setKit: @escaping (BrandKit) -> Void,
        applyKit: @escaping () -> Void,
        pickLogo: @escaping () -> Void,
        applyTemplate: @escaping (VideoTemplate) -> Void,
        saveTemplate: @escaping (String) -> Void,
        deleteTemplate: @escaping (VideoTemplate.ID) -> Void
    ) {
        self.kit = kit
        self.templates = templates
        self.hasLogo = hasLogo
        self.setKit = setKit
        self.applyKit = applyKit
        self.pickLogo = pickLogo
        self.applyTemplate = applyTemplate
        self.saveTemplate = saveTemplate
        self.deleteTemplate = deleteTemplate
    }
}

/// The brand and the templates in one sheet: what the videos look like, and the way this one was
/// made kept for the next one.
struct BrandSheet: View {
    @Bindable var model: EditorModel
    let tools: BrandTools
    let onClose: () -> Void

    @State private var name = ""
    @State private var saved = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var kit: BrandKit { tools.kit }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    colours
                    face
                    logo
                    templates
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(DS.Palette.screen)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                DSKicker(String(localized: "editor.brand.title", bundle: .module))
                Text("editor.brand.hint", bundle: .module)
                    .dsFont(.sans, .regular, 11, lineHeight: 1.3)
                    .foregroundStyle(DS.Palette.ink(0.45))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Palette.ink(0.6))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Palette.hairline(0.08)))
            }
            .buttonStyle(.dsPressIcon)
            .accessibilityLabel(Text("editor.panel.close", bundle: .module))
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    // MARK: - Colours

    private var colours: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("editor.brand.colours")

            HStack(spacing: 14) {
                swatch("editor.brand.primary", colour: kit.primary) { colour in
                    var next = kit
                    next.primary = colour
                    tools.setKit(next)
                }
                swatch("editor.brand.ink", colour: kit.ink) { colour in
                    var next = kit
                    next.ink = colour
                    tools.setKit(next)
                }
                swatch("editor.brand.secondary", colour: kit.secondary) { colour in
                    var next = kit
                    next.secondary = colour
                    tools.setKit(next)
                }
                Spacer(minLength: 0)
            }

            Button(action: tools.applyKit) {
                HStack(spacing: 8) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("editor.brand.apply", bundle: .module)
                        .dsFont(.sans, .semibold, 14)
                }
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.Palette.lime))
            }
            .buttonStyle(.dsPress(radius: 16))
        }
    }

    private func swatch(_ key: String.LocalizationValue, colour: RGBAColor, set: @escaping (RGBAColor) -> Void) -> some View {
        VStack(spacing: 6) {
            ColorPicker(
                "",
                selection: Binding(
                    get: { CaptionOverlay.color(colour) },
                    set: { set(RGBAColor($0)) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            Text(String(localized: key, bundle: .module))
                .dsFont(.sans, .medium, 10)
                .foregroundStyle(DS.Palette.ink(0.5))
        }
    }

    // MARK: - Face

    private var face: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("editor.brand.face")
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Self.faces, id: \.name) { face in
                    let isOn = kit.fontName == face.name
                    Button {
                        var next = kit
                        next.fontName = face.name
                        tools.setKit(next)
                    } label: {
                        Text(face.title)
                            .dsFont(.sans, .medium, 12)
                            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.75))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(isOn ? DS.Palette.accent : DS.Palette.hairline(0.07)))
                    }
                    .buttonStyle(.dsPress(radius: 18))
                }
                Button {
                    var next = kit
                    next.fontName = nil
                    tools.setKit(next)
                } label: {
                    Text("editor.brand.faceDefault", bundle: .module)
                        .dsFont(.sans, .medium, 12)
                        .foregroundStyle(kit.fontName == nil ? DS.Palette.inkInverse : DS.Palette.ink(0.75))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(kit.fontName == nil ? DS.Palette.accent : DS.Palette.hairline(0.07)))
                }
                .buttonStyle(.dsPress(radius: 18))
            }
        }
    }

    /// The faces the app ships, by their PostScript names.
    static let faces: [(name: String, title: String)] = [
        ("Archivo-ExtraBold", "Archivo"),
        ("InstrumentSans-SemiBold", "Instrument"),
        ("JetBrainsMono-Medium", "Mono"),
    ]

    // MARK: - Logo

    private var logo: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("editor.brand.logo")

            HStack(spacing: 10) {
                Button(action: tools.pickLogo) {
                    HStack(spacing: 7) {
                        Image(systemName: tools.hasLogo ? "photo.fill" : "photo.badge.plus")
                            .font(.system(size: 13, weight: .semibold))
                        Group {
                            if tools.hasLogo {
                                Text("editor.brand.logoChange", bundle: .module)
                            } else {
                                Text("editor.brand.logoAdd", bundle: .module)
                            }
                        }
                        .dsFont(.sans, .medium, 13)
                    }
                    .foregroundStyle(DS.Palette.ink(0.85))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 42)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.07)))
                }
                .buttonStyle(.dsPress(radius: 14))

                if tools.hasLogo {
                    Button {
                        var next = kit
                        next.watermark.isOn.toggle()
                        tools.setKit(next)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: kit.watermark.isOn ? "checkmark.seal.fill" : "seal")
                                .font(.system(size: 13, weight: .semibold))
                            Text("editor.brand.watermark", bundle: .module)
                                .dsFont(.sans, .medium, 13)
                        }
                        .foregroundStyle(kit.watermark.isOn ? DS.Palette.lime : DS.Palette.ink(0.6))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 42)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.07)))
                    }
                    .buttonStyle(.dsPress(radius: 14))
                }
                Spacer(minLength: 0)
            }

            if tools.hasLogo, kit.watermark.isOn {
                cornerRow
                sizeRow
            }
        }
    }

    private var cornerRow: some View {
        HStack(spacing: 6) {
            ForEach(BrandKit.Corner.allCases, id: \.self) { corner in
                let isOn = kit.watermark.corner == corner
                Button {
                    var next = kit
                    next.watermark.corner = corner
                    tools.setKit(next)
                } label: {
                    Image(systemName: Self.symbol(corner))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.6))
                        .frame(width: 44, height: 36)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(isOn ? DS.Palette.accent : DS.Palette.hairline(0.07)))
                }
                .buttonStyle(.dsPress(radius: 11))
            }
            Spacer(minLength: 0)
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 12) {
            Text("editor.brand.size", bundle: .module)
                .dsFont(.sans, .medium, 12)
                .foregroundStyle(DS.Palette.ink(0.55))
                .frame(width: 58, alignment: .leading)
            DSSlider(
                value: Binding(
                    get: { kit.watermark.width },
                    set: { value in
                        var next = kit
                        next.watermark.width = value
                        tools.setKit(next)
                    }
                ),
                in: 0.06...0.32,
                step: 0.01
            )
            Text(verbatim: "\(Int((kit.watermark.width * 100).rounded()))%")
                .dsFont(.mono, .medium, 11)
                .foregroundStyle(DS.Palette.ink(0.75))
                .frame(width: 38, alignment: .trailing)
        }
    }

    static func symbol(_ corner: BrandKit.Corner) -> String {
        switch corner {
        case .topLeading: "arrow.up.left.square"
        case .topTrailing: "arrow.up.right.square"
        case .bottomLeading: "arrow.down.left.square"
        case .bottomTrailing: "arrow.down.right.square"
        }
    }

    // MARK: - Templates

    private var templates: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("editor.brand.templates")

            Text("editor.brand.templates.hint", bundle: .module)
                .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                .foregroundStyle(DS.Palette.ink(0.45))

            ForEach(tools.templates) { template in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .dsFont(.sans, .semibold, 14)
                            .foregroundStyle(DS.Palette.ink)
                            .lineLimit(1)
                        Text(Self.summary(template))
                            .dsFont(.mono, .medium, 10)
                            .foregroundStyle(DS.Palette.ink(0.45))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        tools.applyTemplate(template)
                        onClose()
                    } label: {
                        Text("editor.brand.use", bundle: .module)
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(DS.Palette.inkInverse)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(DS.Palette.lime))
                    }
                    .buttonStyle(.dsPress(radius: 17))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(0.05)))
                .contextMenu {
                    Button(role: .destructive) {
                        tools.deleteTemplate(template.id)
                    } label: {
                        Label(String(localized: "editor.brand.delete", bundle: .module), systemImage: "trash")
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(String(localized: "editor.brand.name", bundle: .module), text: $name)
                    .dsFont(.sans, .regular, 13)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.hairline(0.07)))
                    .submitLabel(.done)
                    .onSubmit(save)

                Button(action: save) {
                    HStack(spacing: 6) {
                        Image(systemName: saved ? "checkmark" : "square.and.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                        Group {
                            if saved {
                                Text("editor.brand.saved", bundle: .module)
                            } else {
                                Text("editor.brand.save", bundle: .module)
                            }
                        }
                        .dsFont(.sans, .semibold, 13)
                    }
                    .foregroundStyle(DS.Palette.ink(0.9))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.hairline(0.08)))
                }
                .buttonStyle(.dsPress(radius: 12))
            }
            .onChange(of: name) { _, _ in saved = false }
        }
    }

    private func save() {
        let chosen = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = VideoTemplate.name(for: model.project)
        let title = chosen.isEmpty ? fallback : chosen
        guard !title.isEmpty else { return }
        tools.saveTemplate(title)
        name = ""
        withAnimation(reduceMotion ? nil : DS.Motion.snap) { saved = true }
    }

    static func summary(_ template: VideoTemplate) -> String {
        var parts = [template.format.label, template.captionPreset]
        if let look = template.look, look.look != .natural { parts.append(look.look.rawValue) }
        if let transition = template.transition { parts.append(transition.rawValue) }
        return parts.joined(separator: " · ")
    }

    private func label(_ key: String.LocalizationValue) -> some View {
        Text(String(localized: key, bundle: .module))
            .dsFont(.mono, .medium, 9, letterSpacing: 0.14)
            .foregroundStyle(DS.Palette.ink(0.4))
    }
}

extension RGBAColor {
    /// A colour picked on screen, as a brand colour.
    init(_ colour: Color) {
        #if canImport(UIKit)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
        UIColor(colour).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
        #else
        self.init(red: 1, green: 1, blue: 1)
        #endif
    }
}
