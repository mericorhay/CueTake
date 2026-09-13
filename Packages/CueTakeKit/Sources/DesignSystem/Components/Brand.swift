import SwiftUI

/// The CueTake mark: a take, cut clean in two — the coral half that was said, the lime half that
/// is kept.
///
/// A raster cut from the approved artwork and snapped to the exact brand colours, drawn at the
/// size asked for. Sized by height, because the mark sits beside type and has to line up with it.
public struct DSBrandMark: View {
    private let height: CGFloat

    public init(height: CGFloat = 28) {
        self.height = height
    }

    public var body: some View {
        Image("BrandMark", bundle: .module)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel(Text(verbatim: "CueTake"))
    }
}

/// Mark and name, side by side.
///
/// The name is set in Archivo rather than taken from the artwork: live type stays sharp at every
/// size, and it is the same face the rest of the app speaks in, so the logo and the headlines
/// under it read as one voice.
public struct DSBrandLockup: View {
    private let size: CGFloat
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(size: CGFloat = 18) {
        self.size = size
    }

    public var body: some View {
        HStack(spacing: size * 0.45) {
            DSBrandMark(height: size * 1.25)
                // Arrives with a small snap, the way a cut lands.
                .scaleEffect(shown || reduceMotion ? 1 : 0.6)
                .rotationEffect(.degrees(shown || reduceMotion ? 0 : -18))
                .opacity(shown || reduceMotion ? 1 : 0)

            Text(verbatim: "CueTake")
                .font(DS.archivo(.bold, size))
                .foregroundStyle(DS.Palette.ink)
                .opacity(shown || reduceMotion ? 1 : 0)
                .offset(x: shown || reduceMotion ? 0 : -6)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(DS.Motion.bloom.delay(0.05)) { shown = true }
        }
    }
}
