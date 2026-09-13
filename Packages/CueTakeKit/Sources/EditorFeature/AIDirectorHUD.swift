import DesignSystem
import Domain
import SwiftUI

/// The AI's voice while it has the studio: what it is reading, which change it is making now, what
/// it made. It grows out of the top of the screen and folds back into it.
struct AIDirectorHUD: View {
    @Bindable var model: EditorModel
    let onReview: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let session = model.aiSession {
                card(session)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .scale(scale: 0.35, anchor: .top).combined(with: .opacity).combined(with: .offset(y: -24)),
                                removal: .scale(scale: 0.6, anchor: .top).combined(with: .opacity)
                            )
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.5, dampingFraction: 0.74), value: model.aiSession == nil)
        .task(id: finishedID) {
            // A finished run tidies itself away; failures wait to be read.
            guard finishedID != nil else { return }
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            model.dismissAISession()
        }
    }

    private var finishedID: UUID? {
        guard case .finished = model.aiSession?.phase else { return nil }
        return model.aiSession?.changeSetID
    }

    private func card(_ session: AISession) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return VStack(alignment: .leading, spacing: 11) {
            switch session.phase {
            case .thinking: thinking(session)
            case .applying: applying(session)
            case .finished(let applied, let skipped): finished(session, applied: applied, skipped: skipped)
            case .failed(let message): failed(message)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: 440, alignment: .leading)
        .background {
            shape.fill(.ultraThinMaterial)
            shape.fill(DS.Palette.glassSheet(0.86))
        }
        .overlay { AIRing(shape: shape, active: model.isAIDriving) }
        .shadow(color: AIPalette.violet.opacity(model.isAIDriving ? 0.35 : 0.15), radius: 24, y: 10)
        // It sits over the title bar; once the AI is done, a flick up puts it away.
        .gesture(
            DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height < -16 { model.dismissAISession() }
            },
            including: model.isAIDriving ? .subviews : .all
        )
        .padding(.horizontal, 14)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: session.phase)
    }

    // MARK: - Phases

    private func thinking(_ session: AISession) -> some View {
        HStack(spacing: 12) {
            AIOrb(fast: false)
            VStack(alignment: .leading, spacing: 3) {
                Text("editor.ai.hud.reading", bundle: .module)
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(DS.Palette.ink)
                Text(verbatim: "“\(session.instruction)”")
                    .dsFont(.sans, .regular, 11)
                    .foregroundStyle(DS.Palette.ink(0.6))
                    .lineLimit(1)
                Text("editor.ai.reading \(session.clips) \(session.words) \(session.beats)", bundle: .module)
                    .dsFont(.mono, .medium, 9)
                    .foregroundStyle(AIPalette.linear)
            }
            Spacer(minLength: 0)
            stopButton
        }
        .transition(.opacity)
    }

    private func applying(_ session: AISession) -> some View {
        let count = max(1, session.steps.count)
        let step = session.steps.indices.contains(session.current) ? session.steps[session.current] : nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AIOrb(fast: true)
                VStack(alignment: .leading, spacing: 3) {
                    ZStack(alignment: .leading) {
                        if let step {
                            HStack(spacing: 6) {
                                Image(systemName: step.symbol)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AIPalette.linear)
                                Text(step.text)
                                    .dsFont(.sans, .semibold, 13)
                                    .foregroundStyle(DS.Palette.ink)
                                    .lineLimit(1)
                            }
                            .id(step.id)
                            .transition(
                                reduceMotion ? .opacity : .push(from: .bottom).combined(with: .opacity)
                            )
                        }
                    }
                    .clipped()
                    Text("editor.ai.hud.step \(session.current + 1) \(count)", bundle: .module)
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.45))
                        .contentTransition(.numericText())
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.8), value: session.current)
                Spacer(minLength: 0)
                stopButton
            }

            stepTrack(session)
        }
        .transition(.opacity)
    }

    /// One dot per change: done ones filled with the spectrum, the current one wide and glowing.
    private func stepTrack(_ session: AISession) -> some View {
        HStack(spacing: session.steps.count > 16 ? 2 : 4) {
            ForEach(session.steps) { step in
                let done = step.id < session.current
                let now = step.id == session.current
                Capsule()
                    .fill(done || now ? AnyShapeStyle(AIPalette.linear) : AnyShapeStyle(DS.Palette.hairline(0.12)))
                    .frame(width: now ? 26 : nil, height: 5)
                    .frame(maxWidth: now ? 26 : .infinity)
                    .shadow(color: now ? AIPalette.violet.opacity(0.9) : .clear, radius: 5)
            }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: session.current)
    }

    private func finished(_ session: AISession, applied: Int, skipped: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AIPalette.linear)
                    .symbolEffect(.bounce, value: applied)
                    .shadow(color: AIPalette.violet.opacity(0.6), radius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("editor.ai.hud.done \(applied)", bundle: .module)
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.ink)
                    if skipped > 0 {
                        Text("editor.ai.skipped \(skipped)", bundle: .module)
                            .dsFont(.sans, .regular, 11)
                            .foregroundStyle(DS.Palette.ink(0.45))
                    }
                }
                Spacer(minLength: 0)
                closeButton
            }
            if !session.summary.isEmpty {
                Text(session.summary)
                    .dsFont(.sans, .regular, 12, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.ink(0.7))
                    .lineLimit(3)
            }
            HStack(spacing: 8) {
                Button {
                    guard let id = session.changeSetID else { return }
                    withAnimation(DS.Motion.settle) { model.revertAIChangeSet(id) }
                    model.dismissAISession()
                } label: {
                    Label {
                        Text("editor.ai.hud.undo", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.ink)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(DS.Palette.hairline(0.1)))
                }
                .buttonStyle(.dsPress(radius: 20))

                Button(action: onReview) {
                    Label {
                        Text("editor.ai.hud.review", bundle: .module)
                    } icon: {
                        Image(systemName: "list.bullet.rectangle.portrait")
                    }
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.inkInverse)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(AIPalette.linear))
                }
                .buttonStyle(.dsPress(radius: 20))
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Palette.accent)
                Text(message)
                    .dsFont(.sans, .regular, 12, lineHeight: 1.35)
                    .foregroundStyle(DS.Palette.ink(0.85))
                    .lineLimit(4)
                Spacer(minLength: 0)
                closeButton
            }
            Button {
                model.retryAI()
            } label: {
                Label {
                    Text("editor.ai.retry", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
                .dsFont(.sans, .semibold, 12)
                .foregroundStyle(DS.Palette.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(Capsule().fill(DS.Palette.hairline(0.1)))
            }
            .buttonStyle(.dsPress(radius: 20))
        }
        .transition(.opacity)
    }

    // MARK: - Pieces

    private var stopButton: some View {
        Button {
            model.stopAI()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("editor.ai.hud.stop", bundle: .module)
                    .dsFont(.sans, .semibold, 11)
            }
            .foregroundStyle(DS.Palette.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Capsule().fill(DS.Palette.hairline(0.12)))
        }
        .buttonStyle(.dsPress(radius: 20))
    }

    private var closeButton: some View {
        Button {
            model.dismissAISession()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DS.Palette.ink(0.7))
                .frame(width: 28, height: 28)
                .background(Circle().fill(DS.Palette.hairline(0.1)))
        }
        .buttonStyle(.dsPressIcon)
    }
}

/// A living sphere of the AI's colours with sparkles on it: turning slowly while it reads, quickly
/// while it works.
struct AIOrb: View {
    let fast: Bool
    var size: CGFloat = 36

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = (t * (fast ? 220 : 90)).truncatingRemainder(dividingBy: 360)
            let breath = 0.5 + 0.5 * sin(t * (fast ? 6 : 2.4))
            ZStack {
                Circle()
                    .fill(AIPalette.angular(angle))
                    .blur(radius: 8)
                    .scaleEffect(0.9 + breath * 0.25)
                    .opacity(0.8)
                Circle()
                    .fill(AIPalette.angular(-angle * 0.7))
                    .overlay {
                        Circle().fill(
                            RadialGradient(colors: [.white.opacity(0.5), .clear], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.5)
                        )
                    }
                    .scaleEffect(0.82 + breath * 0.06)
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2)
                    .rotationEffect(.degrees(sin(t * 1.6) * 8))
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

/// A turning spectrum outline for the HUD, still when the AI is idle.
struct AIRing<S: InsettableShape>: View {
    let shape: S
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !active)) { context in
            let angle = active ? (context.date.timeIntervalSinceReferenceDate * 160).truncatingRemainder(dividingBy: 360) : 30
            shape
                .strokeBorder(AIPalette.angular(angle), lineWidth: active ? 1.6 : 1)
                .opacity(active ? 1 : 0.5)
        }
        .allowsHitTesting(false)
    }
}
