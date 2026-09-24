import DesignSystem
import Domain
import SwiftUI

/// The light behind the conversation.
///
/// A mesh of the app's own colours drifting very slowly, brightening while the assistant thinks.
/// It is what the glass has to refract — Liquid Glass over a flat colour is just a grey panel —
/// and it is the only signal that works without looking at any particular part of the screen.
struct AssistantAmbience: View {
    let isThinking: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Precomputed outside the view builder: nine points of arithmetic inline is the kind of
    /// expression the type checker gives up on.
    static func points(at date: Date, thinking: Bool) -> [SIMD2<Float>] {
        let t = Float(date.timeIntervalSinceReferenceDate)
        let speed: Float = thinking ? 0.9 : 0.25
        func drift(_ phase: Float) -> Float { 0.12 * sin(t * speed + phase) }
        return [
            SIMD2(0, 0), SIMD2(0.5 + drift(0), 0), SIMD2(1, 0),
            SIMD2(0, 0.5 + drift(1.3)), SIMD2(0.5 + drift(2.1), 0.5 + drift(0.7)), SIMD2(1, 0.5 + drift(2.9)),
            SIMD2(0, 1), SIMD2(0.5 + drift(3.7), 1), SIMD2(1, 1),
        ]
    }

    private var colors: [Color] {
        let screen = DS.Palette.screen
        return [
            screen, DS.Palette.accent.opacity(isThinking ? 0.34 : 0.18), screen,
            DS.Palette.lime.opacity(isThinking ? 0.22 : 0.1), screen, DS.Palette.accentWarm.opacity(isThinking ? 0.26 : 0.12),
            screen, DS.Palette.lime.opacity(0.08), screen,
        ]
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.points(at: timeline.date, thinking: isThinking),
                colors: colors
            )
        }
        .background(DS.Palette.screen)
        .animation(.easeInOut(duration: 0.8), value: isThinking)
    }
}

/// The assistant's face: a crisp four-point spark in a dark core, ringed by a slowly turning band of
/// the app's colours.
///
/// At rest the spark breathes and a small twin twinkles beside it; while it thinks the ring runs
/// fast and the spark turns. A tap spins the spark a quarter turn with a spring. Drawn, not a
/// blurred blob: it has to read as a mark at 30 points and still hold up at 96.
struct AssistantOrb: View {
    let isThinking: Bool
    /// Bumped by the caller on a tap: the spark answers with a quarter turn.
    var burst: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let d = min(proxy.size.width, proxy.size.height)
                let rotation = Angle.degrees(t * (isThinking ? 220 : 40))
                let breath = 1 + (isThinking ? 0.08 : 0.05) * sin(t * (isThinking ? 6 : 1.8))
                let twinkle = 0.35 + 0.65 * max(0, sin(t * 2.3 + 1.2))
                let band = AngularGradient(
                    colors: [DS.Palette.lime, DS.Palette.accent, DS.Palette.accentWarm, DS.Palette.lime],
                    center: .center,
                    angle: rotation
                )

                ZStack {
                    // The glow under the ring, soft; then the ring itself, sharp.
                    Circle()
                        .strokeBorder(band, lineWidth: d * 0.12)
                        .blur(radius: d * 0.08)
                        .opacity(isThinking ? 0.95 : 0.6)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(white: 0.2), Color(white: 0.05)],
                                center: UnitPoint(x: 0.35, y: 0.3),
                                startRadius: 0,
                                endRadius: d * 0.6
                            )
                        )
                        .padding(d * 0.05)
                    Circle()
                        .strokeBorder(band, lineWidth: max(1.5, d * 0.05))

                    SparkShape()
                        .fill(
                            LinearGradient(
                                colors: [.white, DS.Palette.lime],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: d * 0.46, height: d * 0.46)
                        .shadow(color: DS.Palette.lime.opacity(0.6), radius: d * 0.06)
                        .scaleEffect(breath)
                        .rotationEffect(.degrees(isThinking ? t * 90 : 0))
                        .rotationEffect(.degrees(Double(burst) * 90))
                        .animation(.spring(response: 0.45, dampingFraction: 0.55), value: burst)

                    SparkShape()
                        .fill(.white)
                        .frame(width: d * 0.16, height: d * 0.16)
                        .opacity(twinkle)
                        .scaleEffect(0.7 + 0.3 * twinkle)
                        .offset(x: d * 0.2, y: -d * 0.2)
                }
                .frame(width: d, height: d)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A four-point star with softly curved sides, the classic "spark".
struct SparkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        // How far the sides bow out from the centre toward the corners; 0 is a needle-thin star.
        let bow = 0.16
        let dx = rect.width / 2 * bow
        let dy = rect.height / 2 * bow
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: c.y), control: CGPoint(x: c.x + dx, y: c.y - dy))
        path.addQuadCurve(to: CGPoint(x: c.x, y: rect.maxY), control: CGPoint(x: c.x + dx, y: c.y + dy))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: c.y), control: CGPoint(x: c.x - dx, y: c.y + dy))
        path.addQuadCurve(to: CGPoint(x: c.x, y: rect.minY), control: CGPoint(x: c.x - dx, y: c.y - dy))
        path.closeSubpath()
        return path
    }
}

/// One message.
///
/// The user's words are solid and on the right; the assistant's are glass and on the left, with
/// its links underneath as real buttons. Markdown is rendered because models write lists and bold,
/// and showing the asterisks would make the answer look broken.
struct AssistantBubble: View {
    let message: AssistantMessage
    let onDestination: (AssistantDestination) -> Void
    let onWorkflow: (WorkflowDefinition, Bool) -> Void

    var body: some View {
        switch message.role {
        case .user: user
        case .assistant: assistant
        }
    }

    private var user: some View {
        HStack {
            Spacer(minLength: 56)
            Text(message.text)
                .dsFont(.sans, .regular, 15, lineHeight: 1.4)
                .foregroundStyle(DS.Palette.inkInverse)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 20,
                        bottomLeadingRadius: 20,
                        bottomTrailingRadius: 6,
                        topTrailingRadius: 20,
                        style: .continuous
                    )
                    .fill(DS.gradient(160, [DS.Palette.accent, DS.Palette.accentWarm]))
                )
                .textSelection(.enabled)
        }
    }

    private var assistant: some View {
        let parsed = AssistantDestination.parse(message.text)

        return HStack(alignment: .bottom, spacing: 8) {
            AssistantOrb(isThinking: false)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 10) {
                Text(Self.markdown(parsed.text))
                    .dsFont(.sans, .regular, 15, lineHeight: 1.45)
                    .foregroundStyle(DS.Palette.ink(0.92))
                    .tint(DS.Palette.lime)
                    .textSelection(.enabled)

                if let workflow = parsed.workflow {
                    WorkflowProposalCard(workflow: workflow, onOpen: { onWorkflow(workflow, false) }, onRun: { onWorkflow(workflow, true) })
                }

                if !parsed.destinations.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(parsed.destinations, id: \.self) { destination in
                            Button {
                                onDestination(destination)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: destination.symbol)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(AppLocalization.string(destination.titleKey, bundle: .module))
                                        .dsFont(.sans, .semibold, 12)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .foregroundStyle(DS.Palette.inkInverse)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.dsPress(radius: 20))
                            .glassEffect(.regular.tint(DS.Palette.lime).interactive(), in: .capsule)
                        }
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .glassEffect(
                .regular,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: 6,
                    bottomTrailingRadius: 20,
                    topTrailingRadius: 20,
                    style: .continuous
                )
            )

            Spacer(minLength: 30)
        }
    }

    /// Inline markdown, keeping line breaks. Full-block markdown parsing would swallow the line
    /// breaks models use for short lists, which is most of what they write.
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

/// Three dots in a glass pill, rising one after another.
struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AssistantOrb(isThinking: true)
                .frame(width: 22, height: 22)

            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(DS.Palette.ink(0.75))
                            .frame(width: 7, height: 7)
                            .offset(y: -4 * max(0, sin(t * 6 - Double(index) * 0.7)))
                            .opacity(0.45 + 0.55 * max(0, sin(t * 6 - Double(index) * 0.7)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .glassEffect(.regular, in: .capsule)

            Spacer(minLength: 0)
        }
        .accessibilityLabel(Text("assistant.status.thinking", bundle: .module))
    }
}

/// Every conversation, most recent first.
///
/// Slides in over the conversation rather than replacing it, so leaving the list puts you back
/// exactly where you were — the list is a place you visit, not a place you go.
struct AssistantSessionsView: View {
    @Bindable var model: AssistantModel
    @State private var confirmingDeleteAll = false

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.black.opacity(0.35))
                .ignoresSafeArea()
                .onTapGesture { model.showsSessions = false }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("assistant.sessions", bundle: .module)
                        .dsFont(.archivo, .bold, 22)
                        .foregroundStyle(DS.Palette.ink)
                    Spacer(minLength: 0)
                    Button {
                        model.showsSessions = false
                    } label: {
                        Image(systemName: "xmark")
                            .dsActionName("xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(DS.Palette.ink(0.8))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.dsPressIcon)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)

                Button {
                    withAnimation(DS.Motion.settle) { model.newSession() }
                } label: {
                    Label(AppLocalization.string("assistant.newChat", bundle: .module), systemImage: "square.and.pencil")
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.dsPress(radius: 18))
                .glassEffect(.regular.tint(DS.Palette.lime).interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 18)
                .padding(.bottom, 10)

                if model.sessions.isEmpty {
                    Text("assistant.sessions.empty", bundle: .module)
                        .dsFont(.sans, .regular, 13)
                        .foregroundStyle(DS.Palette.ink(0.56))
                        .padding(18)
                    Spacer(minLength: 0)
                } else {
                    List {
                        ForEach(model.sessions) { session in
                            row(session)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation(DS.Motion.settle) { model.remove(session.id) }
                                    } label: {
                                        Label(AppLocalization.string("assistant.delete", bundle: .module), systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)

                    Button(role: .destructive) {
                        confirmingDeleteAll = true
                    } label: {
                        Label(AppLocalization.string("assistant.deleteAll", bundle: .module), systemImage: "trash")
                            .dsFont(.sans, .medium, 13)
                            .foregroundStyle(DS.Palette.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.dsPress(radius: 16))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                    .confirmationDialog(
                        AppLocalization.string("assistant.deleteAll.confirm", bundle: .module),
                        isPresented: $confirmingDeleteAll,
                        titleVisibility: .visible
                    ) {
                        Button(AppLocalization.string("assistant.deleteAll", bundle: .module), role: .destructive) {
                            withAnimation(DS.Motion.settle) { model.removeAll() }
                        }
                    }
                }
            }
            .frame(maxWidth: 330, maxHeight: .infinity, alignment: .top)
            .glassEffect(.regular, in: UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28, style: .continuous))
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func row(_ session: AssistantSession) -> some View {
        let isCurrent = session.id == model.currentID

        return Button {
            withAnimation(DS.Motion.settle) { model.open(session.id) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.title.isEmpty ? AppLocalization.string("assistant.title", bundle: .module) : session.title)
                        .dsFont(.sans, .semibold, 14)
                        .foregroundStyle(DS.Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(session.updatedAt, format: .relative(presentation: .named))
                        .dsFont(.mono, .medium, 10)
                        .foregroundStyle(DS.Palette.ink(0.52))
                }
                Text(AssistantDestination.parse(session.preview).text)
                    .dsFont(.sans, .regular, 12)
                    .foregroundStyle(DS.Palette.ink(0.5))
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isCurrent ? DS.Palette.lime.opacity(0.12) : DS.Palette.hairline(0.04))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isCurrent ? DS.Palette.lime.opacity(0.5) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.dsPress(radius: 16))
    }
}
