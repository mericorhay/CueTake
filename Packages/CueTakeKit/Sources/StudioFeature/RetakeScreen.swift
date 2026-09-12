import DesignSystem
import Domain
import Observation
import SwiftUI

/// Re-records exactly one segment. The rest of the cut is never touched — that is the whole point
/// of the Segment → Take model, and this screen is where the user sees it.
@MainActor
@Observable
public final class RetakeModel {
    public enum State: Sendable {
        case ready
        case rolling
        case compare
    }

    public enum Choice: String, Sendable {
        case old
        case new
    }

    public private(set) var state: State = .ready
    public private(set) var wordIndex = 0
    public var choice: Choice = .new

    public let segment: Segment
    private var task: Task<Void, Never>?

    public init(segment: Segment) {
        self.segment = segment
    }

    public var words: [String] {
        ScriptText.words(in: segment.script).map(String.init)
    }

    /// Stand-in for speech tracking, at the design's 130ms per word.
    public func start() {
        guard task == nil else { return }
        state = .rolling
        wordIndex = 0
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(130))
                guard let self, state == .rolling else { return }
                if wordIndex + 1 >= words.count {
                    finish()
                    return
                }
                wordIndex += 1
            }
        }
    }

    public func stop() {
        finish()
    }

    /// Cancels the running timer without touching what is already on screen, the way the design
    /// clears its intervals on every navigation.
    public func stopTimers() {
        task?.cancel()
        task = nil
    }

    public func redo() {
        task?.cancel()
        task = nil
        state = .ready
        wordIndex = 0
    }

    private func finish() {
        task?.cancel()
        task = nil
        state = .compare
    }
}

public struct RetakeScreen: View {
    @Bindable private var model: RetakeModel
    private let onBack: () -> Void
    private let onKeep: (RetakeModel.Choice) -> Void

    public init(
        model: RetakeModel,
        onBack: @escaping () -> Void,
        onKeep: @escaping (RetakeModel.Choice) -> Void
    ) {
        self.model = model
        self.onBack = onBack
        self.onKeep = onKeep
    }

    private var segmentColor: Color {
        DS.Palette.segment(at: model.segment.role.paletteIndex)
    }

    public var body: some View {
        ZStack {
            CameraBackdrop()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    DSCircleButton("←", size: 34, fontSize: 15, style: .glass, action: onBack)
                    DSKicker(
                        String(localized: "retake.kicker \(model.segment.role.displayLabel)", bundle: .module),
                        color: DS.Palette.ink(0.55)
                    )
                }

                Spacer(minLength: 0)

                switch model.state {
                case .ready: readyState
                case .rolling: rollingState
                case .compare: compareState
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 58)
            .padding(.bottom, 36)
            .dsScreenLayout(scrolls: true)
        }
        .dsEnter(.screen())
    }

    // MARK: - Ready

    private var readyState: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                DSKicker(
                    "\(model.segment.role.displayLabel) · \(Int(model.segment.barWeight))s",
                    size: 9,
                    color: segmentColor
                )

                Text(model.segment.script)
                    .dsFont(.sans, .regular, 17, lineHeight: 1.45)
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.top, 10)

                Text("retake.note", bundle: .module)
                    .dsFont(.sans, .regular, 12)
                    .foregroundStyle(DS.Palette.ink(0.38))
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .dsGlass(
                tint: DS.Palette.glass(0.62),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous),
                border: DS.Palette.hairline(0.13)
            )
            .padding(.bottom, 20)

            Button {
                model.start()
            } label: {
                ZStack {
                    RecordRing().frame(width: 92, height: 92)
                    Circle()
                        .fill(DS.Palette.hairline(0.1))
                        .overlay(Circle().stroke(DS.Palette.hairline(0.55), lineWidth: 3))
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(DS.Palette.accent)
                        .frame(width: 58, height: 58)
                        .shadow(color: DS.Palette.accent(0.6), radius: 15)
                }
            }
            .buttonStyle(.dsPress)
        }
        .dsEnter(.rise(duration: 0.4))
    }

    // MARK: - Rolling

    private var rollingState: some View {
        VStack(spacing: 0) {
            FlowLayout(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(model.words.enumerated()), id: \.offset) { index, word in
                    Text(word + " ")
                        .dsFont(.sans, .medium, 17, lineHeight: 1.5)
                        .foregroundStyle(index == model.wordIndex ? DS.Palette.lime : DS.Palette.ink)
                        .opacity(index < model.wordIndex ? 0.32 : 1)
                        .animation(DS.Easing.ease(0.25), value: model.wordIndex)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .dsGlass(
                tint: DS.Palette.glass(0.62),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous),
                border: DS.Palette.accent(0.4)
            )
            .padding(.bottom, 20)

            Button {
                model.stop()
            } label: {
                ZStack {
                    Circle()
                        .fill(DS.Palette.hairline(0.1))
                        .overlay(Circle().stroke(DS.Palette.hairline(0.6), lineWidth: 3))
                        .frame(width: 76, height: 76)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DS.Palette.accent)
                        .frame(width: 26, height: 26)
                        .dsPulse(duration: 1.6)
                }
            }
            .buttonStyle(.dsPress)
        }
        .dsEnter(.rise(duration: 0.4))
    }

    // MARK: - Compare

    private var compareState: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                takeCard(
                    .old,
                    kicker: String(localized: "retake.take.old.kicker", bundle: .module),
                    title: String(localized: "retake.take.old.title", bundle: .module),
                    meta: String(localized: "retake.take.old.meta", bundle: .module)
                )
                takeCard(
                    .new,
                    kicker: String(localized: "retake.take.new.kicker", bundle: .module),
                    title: String(localized: "retake.take.new.title", bundle: .module),
                    meta: String(localized: "retake.take.new.meta", bundle: .module)
                )
            }
            .padding(.bottom, 14)

            FlexRow(spacing: 10, weights: [1, 1.3]) {
                DSSecondaryButton(
                    String(localized: "retake.shootAgain", bundle: .module),
                    verticalPadding: 16
                ) {
                    model.redo()
                }

                DSPrimaryButton(
                    String(
                        localized: model.choice == .new ? "retake.keep.new" : "retake.keep.old",
                        bundle: .module
                    ),
                    verticalPadding: 16,
                    glow: false
                ) {
                    onKeep(model.choice)
                }
            }
        }
        .dsEnter(.rise(duration: 0.4))
    }

    private func takeCard(
        _ choice: RetakeModel.Choice,
        kicker: String,
        title: String,
        meta: String
    ) -> some View {
        let isOn = model.choice == choice

        return Button {
            withAnimation(DS.Easing.ease(0.3)) { model.choice = choice }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker)
                    .dsFont(.mono, .medium, 9, letterSpacing: 0.12)
                    .foregroundStyle(DS.Palette.ink(0.45))
                Text(title)
                    .dsFont(.archivo, .bold, 16)
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.top, 5)
                Text(meta)
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.ink(0.45))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .dsGlass(
                tint: isOn ? DS.Palette.accent(0.16) : DS.Palette.glass(0.6),
                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous),
                border: isOn ? DS.Palette.accent : DS.Palette.hairline(0.12)
            )
        }
        .buttonStyle(.dsPress)
    }
}
