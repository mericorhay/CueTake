import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// How much of the screen the keyboard covers, live.
///
/// SwiftUI moves a view out of the keyboard's way only when it is allowed to resize it. A screen
/// that must not resize — the editor, whose picture and timeline would jump every time a field is
/// tapped — has to be lifted instead, and to lift it you have to know the height.
@MainActor
@Observable
public final class DSKeyboard {
    public private(set) var height: CGFloat = 0

    public init() {
        #if canImport(UIKit)
        let centre = NotificationCenter.default
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillShowNotification] {
            centre.addObserver(forName: name, object: nil, queue: .main) { note in
                let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                Task { @MainActor [weak self] in self?.cover(frame) }
            }
        }
        centre.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in self?.cover(nil) }
        }
        #endif
    }

    #if canImport(UIKit)
    private func cover(_ frame: CGRect?) {
        guard let frame, let screen = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.screen.bounds.height
        else {
            height = 0
            return
        }
        // Off the bottom of the screen: on its way out, or an external keyboard's bar.
        height = max(0, screen - frame.origin.y)
    }
    #endif
}

public extension View {
    /// Lifts the view clear of the keyboard when `active`, for screens that ignore it otherwise.
    ///
    /// `leaving` is what stays covered under the lifted view — the home indicator's room, say — so
    /// the panel sits just above the keyboard rather than jammed against it.
    func dsKeyboardLift(_ keyboard: DSKeyboard, active: Bool, leaving: CGFloat = 12, maximum: CGFloat = 360) -> some View {
        let lift = active && keyboard.height > 0 ? min(max(0, keyboard.height - leaving), maximum) : 0
        return offset(y: -lift)
            .animation(.easeOut(duration: 0.22), value: lift)
    }
}
