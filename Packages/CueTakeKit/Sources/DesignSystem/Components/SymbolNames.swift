import SwiftUI

extension DS {
    /// What an icon-only control does, in words, for VoiceOver.
    ///
    /// A button drawn as nothing but a symbol was announced as "button" and nothing more. The
    /// symbols the app uses for the same action everywhere — close, done, add, send — get the same
    /// words everywhere; a symbol not listed here says nothing, and its screen names it itself.
    public static func actionName(forSymbol symbol: String) -> Text? {
        let key: String.LocalizationValue? = switch symbol {
        case "xmark", "xmark.circle", "xmark.circle.fill": "a11y.close"
        case "checkmark", "checkmark.circle.fill": "a11y.done"
        case "plus", "plus.circle", "plus.circle.fill": "a11y.add"
        case "minus", "minus.circle": "a11y.less"
        case "arrow.up", "arrow.up.circle.fill", "paperplane.fill": "a11y.send"
        case "nosign": "a11y.none"
        case "trash", "trash.fill": "a11y.delete"
        case "chevron.left", "arrow.left": "a11y.back"
        case "rotate.left": "a11y.rotateLeft"
        case "rotate.right": "a11y.rotateRight"
        case "arrow.left.and.right.righttriangle.left.righttriangle.right": "a11y.flipHorizontal"
        case "arrow.up.and.down.righttriangle.up.righttriangle.down": "a11y.flipVertical"
        case "scope": "a11y.centre"
        case "rectangle.expand.vertical": "a11y.fillFrame"
        case "square.grid.2x2": "a11y.allTools"
        case "arrow.up.to.line": "a11y.moveUp"
        case "arrow.down.to.line": "a11y.moveDown"
        case "square.and.arrow.up": "a11y.share"
        case "ellipsis", "ellipsis.circle": "a11y.more"
        default: nil
        }
        return key.map { Text(AppLocalization.string($0, bundle: .module)) }
    }
}

extension View {
    /// Names an icon-only control by the action its symbol stands for.
    public func dsActionName(_ symbol: String) -> some View {
        modifier(ActionName(name: DS.actionName(forSymbol: symbol)))
    }
}

private struct ActionName: ViewModifier {
    let name: Text?

    func body(content: Content) -> some View {
        if let name {
            content.accessibilityLabel(name)
        } else {
            content
        }
    }
}
