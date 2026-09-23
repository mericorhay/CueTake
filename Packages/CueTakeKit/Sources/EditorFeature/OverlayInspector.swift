import DesignSystem
import Domain
import SwiftUI

/// Everything about one picture or line of text: when it shows, what it says, how it looks.
///
/// Time comes first, because "from 29 seconds to the middle" is the question this panel exists to
/// answer: exact start and end in tenths, and a button to put either end where the playhead is.
struct OverlayInspector: View {
    @Bindable var model: EditorModel
    let overlay: Overlay
    let onClose: () -> Void
    /// Opens typing above the keyboard.
    var onType: () -> Void = {}
    /// Opens a template picture's words for changing. Nil for anything that is not a template.
    var onEditTemplate: (() -> Void)? = nil

    private var end: Double { overlay.start.seconds + overlay.duration.seconds }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let onEditTemplate {
                        Button(action: onEditTemplate) {
                            HStack(spacing: 8) {
                                Image(systemName: "character.cursor.ibeam")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("editor.template.edit", bundle: .module)
                                    .dsFont(.sans, .semibold, 14)
                            }
                            .foregroundStyle(DS.Palette.inkInverse)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(DS.Palette.lime))
                        }
                        .buttonStyle(.dsPress)
                    }
                    timing
                    if case .text(let text) = overlay.content {
                        textControls(text)
                    }
                    behindPerson
                    look
                    actions
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(16)
        .frame(maxHeight: 330)
        .dsGlass(
            tint: DS.Palette.glassSheet(0.95),
            in: UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet, topTrailingRadius: DS.Radius.sheet, style: .continuous),
            border: DS.Palette.hairline(0.12)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: overlay.isText ? "textformat" : "photo")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(overlay.isText ? DS.Palette.lime : DS.Palette.accentWarm))
            VStack(alignment: .leading, spacing: 1) {
                Text(overlay.isText ? "editor.overlay.text" : "editor.overlay.image", bundle: .module)
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.ink)
                Text(verbatim: "\(MediaTime(seconds: overlay.start.seconds).preciseTimecode) – \(MediaTime(seconds: end).preciseTimecode)")
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.56))
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Text("editor.overlay.gestureHint", bundle: .module)
                .dsFont(.sans, .regular, 10)
                .foregroundStyle(DS.Palette.ink(0.56))
                .multilineTextAlignment(.trailing)
            Button(action: onClose) {
                Image(systemName: "checkmark")
                    .dsActionName("checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Palette.inkInverse)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Palette.lime))
            }
            .buttonStyle(.dsPressIcon)
        }
    }

    // MARK: - Timing

    private var timing: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSKicker(AppLocalization.string("editor.overlay.when", bundle: .module), size: 10, color: DS.Palette.ink(0.56))
            TimingReadout(start: overlay.start.seconds, end: end)
            HStack(spacing: 8) {
                smallButton("editor.overlay.startHere", symbol: "arrow.right.to.line") {
                    model.startOverlayAtPlayhead(overlay.id)
                }
                smallButton("editor.overlay.endHere", symbol: "arrow.left.to.line") {
                    model.endOverlayAtPlayhead(overlay.id)
                }
                smallButton("editor.tool.split", symbol: "scissors") {
                    withAnimation(DS.Motion.settle) { model.splitOverlay(overlay.id) }
                }
                smallButton("editor.overlay.untilEnd", symbol: "arrow.right.to.line.compact") {
                    // Read before the edit: the change closure has the project open for writing.
                    let videoEnd = model.duration
                    model.updateOverlay(overlay.id, coalescing: "overlay-end") {
                        $0.duration = MediaTime(seconds: max(Overlay.shortest, videoEnd - $0.start.seconds))
                    }
                }
            }
        }
    }

    // MARK: - Text

    private func textControls(_ text: OverlayText) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DSKicker(AppLocalization.string("editor.overlay.words", bundle: .module), size: 10, color: DS.Palette.ink(0.56))
            TextEntryField(
                text: text.text,
                placeholder: AppLocalization.string("editor.overlay.placeholder", bundle: .module),
                action: onType
            )

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(OverlayText.fonts, id: \.self) { font in
                        let isOn = text.fontName == font
                        Button {
                            setText { $0.fontName = font }
                        } label: {
                            Text(verbatim: "Aa")
                                .font(.custom(font, fixedSize: 17))
                                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink)
                                .frame(width: 48, height: 38)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isOn ? DS.Palette.ink : DS.Palette.hairline(0.07)))
                        }
                        .buttonStyle(.dsPress(radius: 10))
                    }
                }
            }
            .scrollIndicators(.hidden)

            colorRow("editor.overlay.color", options: CaptionsScreen.colorSwatches, selected: text.color, allowsNone: false) { color in
                setText { $0.color = color ?? .white }
            }
            colorRow("editor.overlay.plate", options: CaptionsScreen.plateSwatches, selected: text.background, allowsNone: true) { color in
                setText { $0.background = color }
            }
        }
    }

    private func setText(_ change: @escaping (inout OverlayText) -> Void) {
        model.updateOverlay(overlay.id, coalescing: "overlay-style") {
            if case .text(var t) = $0.content {
                change(&t)
                $0.content = .text(t)
            }
        }
    }

    // MARK: - Behind the person

    /// The viral one: a title the person stands in front of.
    private var behindPerson: some View {
        let isOn = overlay.isBehindPerson
        return Button {
            withAnimation(DS.Motion.settle) {
                model.updateOverlay(overlay.id, coalescing: "overlay-behind") { $0.isBehindPerson.toggle() }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.and.background.dotted")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.lime)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isOn ? DS.Palette.lime : DS.Palette.lime.opacity(0.14)))
                    .symbolEffect(.bounce, value: isOn)
                VStack(alignment: .leading, spacing: 2) {
                    Text("editor.overlay.behind", bundle: .module)
                        .dsFont(.sans, .semibold, 13)
                        .foregroundStyle(DS.Palette.ink)
                    Group {
                        if isOn {
                            Text("editor.overlay.behind.on", bundle: .module)
                        } else {
                            Text("editor.overlay.behind.off", bundle: .module)
                        }
                    }
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.ink(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? DS.Palette.lime : DS.Palette.ink(0.3))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.Palette.hairline(isOn ? 0.1 : 0.05)))
        }
        .buttonStyle(.dsPress(radius: 14))
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Look

    private var look: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSKicker(AppLocalization.string("editor.overlay.look", bundle: .module), size: 10, color: DS.Palette.ink(0.56))

            HStack(spacing: 10) {
                Image(systemName: "square.resize.down").font(.system(size: 12)).foregroundStyle(DS.Palette.ink(0.5))
                Slider(
                    value: Binding(
                        get: { overlay.transform.scale },
                        set: { value in model.updateOverlay(overlay.id, coalescing: "overlay-scale") { $0.transform.scale = value } }
                    ),
                    in: OverlayTransform.scaleRange
                )
                .tint(DS.Palette.accent)
                Image(systemName: "square.resize.up").font(.system(size: 14)).foregroundStyle(DS.Palette.ink(0.5))
            }

            HStack(spacing: 10) {
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 12)).foregroundStyle(DS.Palette.ink(0.5))
                Slider(
                    value: Binding(
                        get: { overlay.transform.opacity },
                        set: { value in model.updateOverlay(overlay.id, coalescing: "overlay-opacity") { $0.transform.opacity = value } }
                    ),
                    in: 0.05...1
                )
                .tint(DS.Palette.lime)
                Text(verbatim: "\(Int(overlay.transform.opacity * 100))%")
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.6))
                    .frame(width: 34, alignment: .trailing)
            }

            HStack(spacing: 6) {
                iconButton("rotate.left", isOn: false) {
                    model.updateOverlay(overlay.id, coalescing: "overlay-rotate") { $0.transform.rotation -= 15 }
                }
                iconButton("rotate.right", isOn: false) {
                    model.updateOverlay(overlay.id, coalescing: "overlay-rotate") { $0.transform.rotation += 15 }
                }
                iconButton("arrow.left.and.right.righttriangle.left.righttriangle.right", isOn: overlay.transform.flipX) {
                    model.updateOverlay(overlay.id, coalescing: "overlay-flip") { $0.transform.flipX.toggle() }
                }
                iconButton("arrow.up.and.down.righttriangle.up.righttriangle.down", isOn: overlay.transform.flipY) {
                    model.updateOverlay(overlay.id, coalescing: "overlay-flip") { $0.transform.flipY.toggle() }
                }
                iconButton("scope", isOn: false) {
                    // Straight and centred again.
                    model.updateOverlay(overlay.id, coalescing: "overlay-reset") {
                        $0.transform.x = 0.5
                        $0.transform.y = 0.5
                        $0.transform.rotation = 0
                    }
                }
                if !overlay.isText {
                    iconButton("rectangle.expand.vertical", isOn: false) {
                        // Covers the frame, like a full-screen photo.
                        let render = model.project.format.renderSize
                        let frameAspect = Double(render.width) / Double(max(1, render.height))
                        model.updateOverlay(overlay.id, coalescing: "overlay-fill") {
                            guard case .image(_, let aspect) = $0.content else { return }
                            $0.transform.scale = 2 * max(1, frameAspect / max(aspect, 0.01))
                            $0.transform.x = 0.5
                            $0.transform.y = 0.5
                            $0.transform.rotation = 0
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(OverlayAnimation.allCases, id: \.self) { animation in
                    let isOn = overlay.animation == animation
                    Button {
                        model.updateOverlay(overlay.id, coalescing: "overlay-animation") { $0.animation = animation }
                    } label: {
                        Text(Self.animationLabel(animation))
                            .dsFont(.sans, .medium, 11)
                            .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(isOn ? DS.Palette.accent : DS.Palette.hairline(0.07)))
                    }
                    .buttonStyle(.dsPress(radius: 20))
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            smallButton("editor.overlay.duplicate", symbol: "plus.square.on.square") {
                withAnimation(DS.Motion.settle) { model.duplicateOverlay(overlay.id) }
            }
            smallButton("editor.overlay.front", symbol: "square.3.layers.3d.top.filled") {
                model.bringOverlayToFront(overlay.id)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(DS.Motion.settle) { model.removeOverlay(overlay.id) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                    Text("editor.overlay.delete", bundle: .module).dsFont(.sans, .medium, 12)
                }
                .foregroundStyle(DS.Palette.accent)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Capsule().fill(DS.Palette.accent(0.12)))
            }
            .buttonStyle(.dsPress(radius: 20))
        }
    }

    // MARK: - Parts

    private func timeStepper(_ key: String.LocalizationValue, value: Double, onStep: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 0) {
            stepButton("minus") { onStep(-0.1) }
            VStack(spacing: 1) {
                Text(AppLocalization.string(key, bundle: .module))
                    .dsFont(.mono, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.56))
                Text(verbatim: MediaTime(seconds: value).preciseTimecode)
                    .dsFont(.mono, .medium, 13)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText(value: value))
            }
            .frame(maxWidth: .infinity)
            stepButton("plus") { onStep(0.1) }
        }
        .padding(4)
        .background(Capsule().fill(DS.Palette.hairline(0.06)))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .dsActionName(symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(DS.Palette.hairline(0.08)))
        }
        .buttonRepeatBehavior(.enabled)
        .buttonStyle(.dsPressIcon)
    }

    private func smallButton(_ key: String.LocalizationValue, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(AppLocalization.string(key, bundle: .module)).dsFont(.sans, .medium, 11).lineLimit(1)
            }
            .foregroundStyle(DS.Palette.ink(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(DS.Palette.hairline(0.08)))
        }
        .buttonStyle(.dsPress(radius: 20))
    }

    private func iconButton(_ symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .dsActionName(symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? DS.Palette.inkInverse : DS.Palette.ink(0.85))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isOn ? DS.Palette.lime : DS.Palette.hairline(0.08)))
        }
        .buttonStyle(.dsPress(radius: 10))
    }

    private func colorRow(
        _ key: String.LocalizationValue,
        options: [(id: String, color: RGBAColor)],
        selected: RGBAColor?,
        allowsNone: Bool,
        onPick: @escaping (RGBAColor?) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(AppLocalization.string(key, bundle: .module))
                .dsFont(.sans, .medium, 11)
                .foregroundStyle(DS.Palette.ink(0.5))
                .frame(width: 70, alignment: .leading)
            if allowsNone {
                Button { onPick(nil) } label: {
                    Image(systemName: "nosign")
                        .dsActionName("nosign")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.ink(0.6))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(DS.Palette.hairline(0.07)))
                        .overlay(Circle().stroke(selected == nil ? DS.Palette.accent : .clear, lineWidth: 2).padding(-3))
                }
                .buttonStyle(.dsPressIcon)
            }
            ForEach(options, id: \.id) { option in
                let isOn = selected.map { abs($0.red - option.color.red) < 0.02 && abs($0.green - option.color.green) < 0.02 && abs($0.blue - option.color.blue) < 0.02 } ?? false
                Button { onPick(option.color) } label: {
                    Circle()
                        .fill(CaptionOverlay.color(option.color))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(DS.Palette.hairline(0.25), lineWidth: 1))
                        .overlay(Circle().stroke(isOn ? DS.Palette.accent : .clear, lineWidth: 2).padding(-3))
                }
                .buttonStyle(.dsPressIcon)
            }
            Spacer(minLength: 0)
        }
    }

    static func animationLabel(_ animation: OverlayAnimation) -> String {
        switch animation {
        case .none: AppLocalization.string("editor.overlay.anim.none", bundle: .module)
        case .fade: AppLocalization.string("editor.overlay.anim.fade", bundle: .module)
        case .pop: AppLocalization.string("editor.overlay.anim.pop", bundle: .module)
        case .slideUp: AppLocalization.string("editor.overlay.anim.slide", bundle: .module)
        }
    }
}
