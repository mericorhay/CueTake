import DesignSystem
import Domain
import SwiftUI

/// The prompter for a foldable's outer display, facing the person being filmed.
///
/// On iPhone Duo the main cameras sit behind the outer display: open the phone, film with the best
/// camera, and the words run on the small screen right under it, so the reader looks into the lens
/// while reading. The system decides when the outer display shows it (the phone open, the app full
/// screen, a capture session running); this view is only what it shows.
///
/// The same words and the same place as the panel inside, so the two screens never disagree, drawn
/// for a small screen a metre or two away: bigger type, black behind it, no controls, and a thin
/// line that says recording is on.
public struct OuterDisplayPrompter: View {
    let model: TeleprompterModel
    /// Recording, and for how long, shown along the top.
    let isRecording: Bool
    let elapsed: TimeInterval?

    public init(model: TeleprompterModel, isRecording: Bool, elapsed: TimeInterval? = nil) {
        self.model = model
        self.isRecording = isRecording
        self.elapsed = elapsed
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            PrompterScript(
                words: model.wordStyles(
                    accent: DS.Palette.accent,
                    ink: DS.Palette.ink,
                    inkInverse: DS.Palette.inkInverse,
                    lime: DS.Palette.lime
                ),
                activeIndex: model.activeWordIndex,
                // Read from further away than the panel inside: a size up, never below 30.
                textSize: max(30, model.textSize * 1.35),
                isCentered: true,
                // The reading line high, where the lens is.
                readingLine: 0.22,
                isMirrored: false,
                upNext: model.nextSegment?.script,
                lineColor: DS.Palette.lime
            )
            .padding(.horizontal, 18)
            .padding(.top, 34)

            statusLine
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRecording ? DS.Palette.accent : DS.Palette.ink(0.35))
                .frame(width: 8, height: 8)
            if let elapsed, isRecording {
                Text(verbatim: Self.clock(elapsed))
                    .font(DS.mono(13))
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.ink(0.8))
            }
            Spacer(minLength: 0)
            // How far through the script, as a thin bar: enough to pace the rest of the take.
            GeometryReader { proxy in
                Capsule().fill(DS.Palette.ink(0.15))
                    .overlay(alignment: .leading) {
                        Capsule().fill(DS.Palette.lime)
                            .frame(width: proxy.size.width * min(1, max(0, model.progress)))
                    }
            }
            .frame(width: 90, height: 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
