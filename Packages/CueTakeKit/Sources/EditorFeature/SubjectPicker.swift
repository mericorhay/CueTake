import DesignSystem
import Domain
import SwiftUI

/// Waits for one tap on the picture: the thing tapped is what an object background keeps in
/// front, followed from frame to frame by the render.
///
/// The point is taken on the frame as it is shown. Where the main video is zoomed or moved that
/// is not exactly the same point of the footage, which is why the render keeps whichever thing
/// is nearest when nothing is right under it.
struct SubjectPicker: View {
    @Bindable var model: EditorModel
    @State private var ripple: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let rect = OverlayCanvas.videoRect(in: proxy.size, render: model.project.format.renderSize)
            ZStack(alignment: .top) {
                Color.black.opacity(0.28)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        pick(at: location, in: rect)
                    }

                if let ripple {
                    Circle()
                        .strokeBorder(DS.Palette.lime, lineWidth: 2)
                        .frame(width: 44, height: 44)
                        .position(ripple)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .symbolEffect(.pulse, options: .repeating)
                    Text("editor.effect.pick.hint", bundle: .module)
                        .dsFont(.sans, .semibold, 12)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(DS.Motion.snap) { model.pickingSubject = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.white.opacity(0.18)))
                    }
                    .buttonStyle(.dsPressIcon)
                    .accessibilityLabel(Text("editor.done", bundle: .module))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(.top, 12)
                .padding(.horizontal, 12)
            }
        }
    }

    private func pick(at location: CGPoint, in rect: CGRect) {
        guard let id = model.pickingSubject, rect.width > 0, rect.height > 0, rect.contains(location) else { return }
        let point = SubjectPoint(x: (location.x - rect.minX) / rect.width, y: (location.y - rect.minY) / rect.height)
        withAnimation(DS.Motion.snap) { ripple = location }
        model.updateBackground(id, coalescing: "subject-point") { $0.subjectPoint = point }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(DS.Motion.settle) {
                ripple = nil
                model.pickingSubject = nil
            }
        }
    }
}
