import DesignSystem
import Domain
import SwiftUI
import UIKit

/// What the stage's chrome shows, read from the engine four times a second. Equatable, so each
/// change animates once instead of the whole screen redrawing with the words.
private struct StageStatus: Equatable {
    var phase: SuflorClock.Phase = .ready
    var countdown = 3
    var elapsed = 0
    var secondsToAd: Int?
    var adShare: Double = 0
    var isInAd = false
    var isPlaying = true
    var progress: Double = 0
    var hasAd = false
    var waitsForTap = false

    init() {}

    init(_ frame: SuflorFrame) {
        let clock = frame.clock
        phase = clock.phase
        countdown = max(1, Int((SuflorClock.countdown - clock.elapsed).rounded(.up)))
        elapsed = Int(max(0, clock.elapsed - SuflorClock.countdown))
        secondsToAd = clock.secondsToAd.map { Int($0.rounded(.up)) }
        if let adAt = clock.adAt, let left = clock.secondsToAd {
            adShare = 1 - left / max(1, adAt - SuflorClock.countdown)
        }
        isInAd = frame.isInAd
        isPlaying = clock.isPlaying
        progress = clock.end > 0 ? clock.offset / clock.end : 0
        hasAd = frame.layout.adTop != nil
        waitsForTap = clock.holdAt != nil && clock.adAt == nil && !clock.released
    }
}

struct SuflorStageView: View {
    @Bindable var model: SuflorModel

    @State private var status = StageStatus()
    @State private var flash = false
    @State private var confirmingEnd = false
    @State private var dragStart: CGFloat?
    @State private var width: CGFloat = 402
    /// Step one of the guide is done once the window has floated.
    @State private var hasFloated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            DS.Palette.screen.ignoresSafeArea()
            prompter
            adGlow
            if status.phase == .countdown { countdown }
            if status.phase == .holding { holdCard }
            if flash { adFlash }
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { dock }
        .task { await followEngine() }
        .onChange(of: model.isFloating) { _, floating in
            if floating { hasFloated = true }
        }
        .onChange(of: status.isInAd) { _, inAd in
            guard inAd else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            guard !reduceMotion else { return }
            flash = true
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeOut(duration: 0.5)) { flash = false }
            }
        }
        .onChange(of: status.countdown) { _, _ in
            if status.phase == .countdown { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
        }
        .onChange(of: status.secondsToAd) { _, seconds in
            if let seconds, seconds <= 5, seconds > 0 { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
        .confirmationDialog(Text("suflor.stage.end.title", bundle: .module), isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button(String(localized: "suflor.stage.end.confirm", bundle: .module), role: .destructive) { model.endStage() }
        }
        .statusBarHidden(true)
    }

    private func followEngine() async {
        while !Task.isCancelled {
            if let frame = model.engine?.frame() {
                let next = StageStatus(frame)
                if next != status {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DS.Motion.settle) { status = next }
                }
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    // MARK: - The words

    private var prompter: some View {
        TimelineView(.animation) { _ in
            let engine = model.engine
            Canvas { graphics, size in
                guard let frame = engine?.frame() else { return }
                let scale = size.width / SuflorLayout.width
                graphics.withCGContext { cg in
                    cg.scaleBy(x: scale, y: scale)
                    SuflorPainter.drawText(cg, frame: frame, size: CGSize(width: SuflorLayout.width, height: size.height / scale))
                }
            }
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let scale = max(1, width) / SuflorLayout.width
                    let last = dragStart ?? 0
                    if dragStart == nil { model.setDragging(true) }
                    model.drag(by: Double(-(value.translation.height - last) / scale))
                    dragStart = value.translation.height
                }
                .onEnded { _ in
                    dragStart = nil
                    model.setDragging(false)
                }
        )
        .onTapGesture(count: 2) { model.togglePlaying() }
        .accessibilityElement()
        .accessibilityLabel(Text("suflor.stage.words", bundle: .module))
        .accessibilityHint(Text("suflor.stage.words.hint", bundle: .module))
        .accessibilityAction(named: Text("suflor.stage.next", bundle: .module)) { model.skip(forward: true) }
        .accessibilityAction(named: Text("suflor.stage.previous", bundle: .module)) { model.skip(forward: false) }
    }

    /// The ad's warmth, rising from the bottom while it is being read.
    private var adGlow: some View {
        RadialGradient(colors: [DS.Palette.accent(0.26), .clear], center: .bottom, startRadius: 0, endRadius: 520)
            .ignoresSafeArea()
            .opacity(status.isInAd ? 1 : 0)
            .allowsHitTesting(false)
    }

    // MARK: - Moments

    /// On stage, not started: the three things to do, in order, and a start button. The words
    /// stay visible above it and can be dragged to check them; nothing moves until play.
    private var readyGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSKicker(String(localized: "suflor.stage.guide.title", bundle: .module), size: 10, tracking: 0.18, color: DS.Palette.lime)
            guideStep(1, done: hasFloated, text: String(localized: "suflor.stage.guide.step1", bundle: .module))
            guideStep(2, done: false, text: String(localized: "suflor.stage.guide.step2", bundle: .module))
            guideStep(3, done: false, text: String(localized: "suflor.stage.guide.step3", bundle: .module))
            Button {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                model.togglePlaying()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))
                    Text("suflor.stage.guide.here", bundle: .module).dsFont(.sans, .semibold, 14)
                }
                .foregroundStyle(DS.Palette.lime)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Capsule().stroke(DS.Palette.lime(0.5), lineWidth: 1.5))
            }
            .buttonStyle(.dsPress)
            .accessibilityLabel(Text("suflor.stage.start", bundle: .module))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(tint: DS.Palette.glass(0.8), in: RoundedRectangle(cornerRadius: 26, style: .continuous), border: DS.Palette.lime(0.25))
        .padding(.horizontal, 12)
    }

    /// One numbered step; the number turns into a tick once it is done.
    private func guideStep(_ number: Int, done: Bool, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? DS.Palette.lime : DS.Palette.hairline(0.1))
                if done {
                    DrawnCheck(progress: 1)
                        .stroke(DS.Palette.inkInverse, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text(verbatim: "\(number)")
                        .dsFont(.archivo, .bold, 13)
                        .foregroundStyle(DS.Palette.ink)
                }
            }
            .frame(width: 26, height: 26)
            Text(text)
                .dsFont(.sans, .medium, 15, lineHeight: 1.3)
                .foregroundStyle(done ? DS.Palette.ink(0.5) : DS.Palette.ink)
                .strikethrough(done, color: DS.Palette.ink(0.4))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
        .animation(DS.Motion.bloom, value: done)
        .accessibilityElement(children: .combine)
    }

    /// 3, 2, 1: each number lands with a bloom and a ring that empties with its second.
    private var countdown: some View {
        ZStack {
            DS.Palette.screen.opacity(0.78).ignoresSafeArea()
            ZStack {
                Circle()
                    .stroke(DS.Palette.lime(0.25), lineWidth: 2)
                    .frame(width: 190, height: 190)
                    .scaleEffect(reduceMotion ? 1 : 1.12)
                    .opacity(0.6)
                Circle()
                    .stroke(DS.Palette.lime, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 160, height: 160)
                Text("\(status.countdown)")
                    .dsFont(.archivo, .extrabold, 96, fixed: true)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText(countsDown: true))
                    .id(status.countdown)
                    .transition(.scale(scale: 1.8).combined(with: .opacity))
            }
            Text("suflor.stage.countdown", bundle: .module)
                .dsFont(.mono, .medium, 12, letterSpacing: 0.2)
                .foregroundStyle(DS.Palette.ink(0.66))
                .offset(y: 130)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    /// Waiting at the ad: the minute counted down in a gold ring, a button to go now.
    private var holdCard: some View {
        GeometryReader { proxy in
            let reading = proxy.size.height * SuflorPainter.readingLine
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    ZStack {
                        if status.secondsToAd != nil {
                            ProgressRing(share: status.adShare, color: DS.Palette.amber, width: 5)
                            Text(SuflorSession.clock(Double(status.secondsToAd ?? 0)))
                                .dsFont(.archivo, .bold, 18, fixed: true)
                                .foregroundStyle(DS.Palette.ink)
                                .contentTransition(.numericText(countsDown: true))
                                .monospacedDigit()
                        } else {
                            ProgressRing(share: 1, color: DS.Palette.amber, width: 5)
                            Image(systemName: "forward.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(DS.Palette.amber)
                                .symbolEffect(.pulse, isActive: !reduceMotion)
                        }
                    }
                    .frame(width: 74, height: 74)
                    .scaleEffect(urgent && !reduceMotion ? 1.06 : 1)
                    .animation(urgent && !reduceMotion ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true) : .default, value: urgent)

                    VStack(alignment: .leading, spacing: 4) {
                        Group {
                            if status.waitsForTap {
                                Text("suflor.stage.hold.manual", bundle: .module)
                            } else {
                                Text("suflor.stage.hold.title", bundle: .module)
                            }
                        }
                        .dsFont(.archivo, .bold, 18)
                        .foregroundStyle(DS.Palette.ink)
                        Text("suflor.stage.hold.detail", bundle: .module)
                            .dsFont(.sans, .regular, 13, lineHeight: 1.3)
                            .foregroundStyle(DS.Palette.ink(0.66))
                    }
                    Spacer(minLength: 0)
                }
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    model.startAd()
                } label: {
                    Text("suflor.stage.hold.now", bundle: .module)
                        .dsFont(.sans, .semibold, 15)
                        .foregroundStyle(DS.Palette.inkInverse)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Capsule().fill(DS.Palette.amber))
                }
                .buttonStyle(.dsPress)
                .padding(.top, 14)
            }
            .padding(18)
            .dsGlass(tint: DS.Palette.glass(0.8), in: RoundedRectangle(cornerRadius: 26, style: .continuous), border: DS.Palette.amber.opacity(0.35))
            .shadow(color: DS.Palette.amber.opacity(0.18), radius: 30, y: 12)
            .padding(.horizontal, 18)
            .offset(y: reading + 30)
        }
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    private var urgent: Bool { (status.secondsToAd ?? 99) <= 5 }

    /// The ad starts: a band of light sweeps down the screen and the word lands.
    private var adFlash: some View {
        ZStack {
            AdSweep()
            VStack(spacing: 6) {
                Text("suflor.stage.adNow", bundle: .module)
                    .dsFont(.archivo, .extrabold, 44, fixed: true)
                    .foregroundStyle(DS.Palette.ink)
                Text(model.session?.plan.brief.brand ?? "")
                    .dsFont(.mono, .medium, 13, letterSpacing: 0.2)
                    .foregroundStyle(DS.Palette.ink(0.8))
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                confirmingEnd = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Palette.ink(0.86))
                    .frame(width: 44, height: 44)
                    .dsGlass(tint: DS.Palette.glass(0.5), in: Circle())
            }
            .buttonStyle(.dsPressIcon)
            .accessibilityLabel(Text("suflor.stage.end", bundle: .module))

            HStack(spacing: 4) {
                LiveDot(size: 7)
                Group {
                    if model.brief.kind == .live {
                        Text("suflor.chrome.live", bundle: .module)
                    } else {
                        Text("suflor.chrome.video", bundle: .module)
                    }
                }
                .dsFont(.mono, .medium, 11, letterSpacing: 0.14)
                Text(SuflorSession.clock(Double(status.elapsed)))
                    .dsFont(.mono, .medium, 12)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }
            .foregroundStyle(DS.Palette.ink)
            .padding(.trailing, 12)
            .frame(minHeight: 36)
            .dsGlass(tint: DS.Palette.glass(0.5), in: Capsule())

            Spacer(minLength: 0)
            adPill
        }
        .padding(.horizontal, 16)
        .padding(.top, 54)
    }

    @ViewBuilder
    private var adPill: some View {
        if status.isInAd {
            Text("suflor.chrome.ad", bundle: .module)
                .dsFont(.mono, .medium, 12, letterSpacing: 0.16)
                .foregroundStyle(DS.Palette.inkInverse)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Capsule().fill(DS.Palette.accent))
                .shadow(color: DS.Palette.accent(0.6), radius: 14)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        } else if let seconds = status.secondsToAd {
            HStack(spacing: 8) {
                ProgressRing(share: status.adShare, color: DS.Palette.amber, width: 3)
                    .frame(width: 18, height: 18)
                Text("suflor.chrome.toAd", bundle: .module)
                    .dsFont(.mono, .medium, 11, letterSpacing: 0.14)
                Text(SuflorSession.clock(Double(seconds)))
                    .dsFont(.mono, .medium, 12)
                    .contentTransition(.numericText(countsDown: true))
                    .monospacedDigit()
            }
            .foregroundStyle(seconds <= 30 ? DS.Palette.inkInverse : DS.Palette.amber)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(Capsule().fill(seconds <= 30 ? DS.Palette.amber : DS.Palette.amber.opacity(0.14)))
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }

    private var dock: some View {
        VStack(spacing: 12) {
            if status.phase == .ready {
                readyGuide
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let items = model.session?.plan.brief.mustSay, !items.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(items, id: \.self) { item in
                            MustSayChip(item: item, isTicked: model.session?.ticked[item] != nil) {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                withAnimation(DS.Motion.bloom) { model.tick(item) }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(spacing: 10) {
                    transport
                    HStack(spacing: 8) {
                        SuflorStepper(
                            value: "\(Int(model.wordsPerMinute))",
                            caption: String(localized: "suflor.pace.unit", bundle: .module),
                            minusLabel: String(localized: "suflor.pace.slower", bundle: .module),
                            plusLabel: String(localized: "suflor.pace.faster", bundle: .module),
                            onMinus: { withAnimation(DS.Motion.snap) { model.nudgePace(-10) } },
                            onPlus: { withAnimation(DS.Motion.snap) { model.nudgePace(10) } }
                        )
                        SuflorStepper(
                            value: "\(Int(model.textSize))",
                            caption: String(localized: "suflor.size.unit", bundle: .module),
                            minusLabel: String(localized: "suflor.size.smaller", bundle: .module),
                            plusLabel: String(localized: "suflor.size.larger", bundle: .module),
                            onMinus: { withAnimation(DS.Motion.snap) { model.nudgeSize(-2) } },
                            onPlus: { withAnimation(DS.Motion.snap) { model.nudgeSize(2) } }
                        )
                    }
                }
                windowPreview
            }
            .padding(14)
            .dsGlass(tint: DS.Palette.glass(0.72), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.horizontal, 12)

            floatButton
                .padding(.horizontal, 12)
            Text("suflor.stage.windowHint", bundle: .module)
                .dsFont(.sans, .regular, 12)
                .foregroundStyle(DS.Palette.ink(0.56))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.bottom, 22)
    }

    private var transport: some View {
        HStack(spacing: 14) {
            transportButton("backward.fill", label: "suflor.stage.previous") { model.skip(forward: false) }
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                model.togglePlaying()
            } label: {
                Image(systemName: status.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DS.Palette.inkInverse)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(DS.Palette.lime))
                    .shadow(color: DS.Palette.lime(0.35), radius: 16, y: 6)
            }
            .buttonStyle(.dsPressIcon)
            .accessibilityLabel(playLabel)
            transportButton("forward.fill", label: "suflor.stage.next") { model.skip(forward: true) }
        }
    }

    private var playLabel: Text {
        if status.isPlaying { return Text("suflor.stage.pause", bundle: .module) }
        return Text("suflor.stage.play", bundle: .module)
    }

    private func transportButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DS.Palette.ink(0.9))
                .frame(width: 48, height: 48)
                .background(Circle().fill(DS.Palette.hairline(0.08)))
        }
        .buttonStyle(.dsPressIcon)
        .accessibilityLabel(Text(label, bundle: .module))
    }

    /// The floating window as it is right now — the real frames — and where it grows from.
    private var windowPreview: some View {
        VStack(spacing: 6) {
            ZStack {
                if let engine = model.engine {
                    SuflorWindowPreview(layer: engine.displayLayer) { model.attachWindow() }
                }
                if model.isFloating {
                    ZStack {
                        DS.Palette.screen.opacity(0.85)
                        Image(systemName: "pip.exit")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(DS.Palette.lime)
                            .symbolEffect(.pulse, isActive: !reduceMotion)
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: 84, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Palette.lime(model.isFloating ? 0.8 : 0.25), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            Text("suflor.stage.window", bundle: .module)
                .dsFont(.mono, .medium, 10, letterSpacing: 0.12)
                .foregroundStyle(DS.Palette.ink(0.56))
        }
        .accessibilityHidden(true)
    }

    private var floatButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            if model.isFloating { model.bringBack() } else { model.floatAway() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: model.isFloating ? "pip.exit" : "pip.enter")
                    .font(.system(size: 17, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Group {
                    if model.isFloating {
                        Text("suflor.stage.bringBack", bundle: .module)
                    } else {
                        Text("suflor.stage.float", bundle: .module)
                    }
                }
                .dsFont(.sans, .semibold, 16)
            }
            .foregroundStyle(DS.Palette.inkInverse)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                ZStack {
                    DS.gradient(150, [DS.Palette.accent, DS.Palette.accentWarm])
                    if !model.isFloating { SweepShine() }
                }
            }
            .clipShape(Capsule())
            .shadow(color: DS.Palette.accent(0.4), radius: 20, y: 10)
        }
        .buttonStyle(.dsPress(radius: 28))
        .disabled(!model.canFloat && !model.isFloating)
        .opacity(model.canFloat || model.isFloating ? 1 : 0.5)
        .animation(DS.Motion.settle, value: model.isFloating)
    }
}

/// An item the brand asked for: tapped when said, the tick drawing itself in.
private struct MustSayChip: View {
    let item: String
    let isTicked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isTicked ? DS.Palette.lime : .clear)
                        .overlay(Circle().stroke(isTicked ? .clear : DS.Palette.ink(0.4), lineWidth: 1.5))
                    DrawnCheck(progress: isTicked ? 1 : 0)
                        .stroke(DS.Palette.inkInverse, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .padding(4)
                }
                .frame(width: 20, height: 20)
                Text(item)
                    .dsFont(.sans, .semibold, 14)
                    .foregroundStyle(isTicked ? DS.Palette.ink(0.56) : DS.Palette.ink)
                    .strikethrough(isTicked, color: DS.Palette.ink(0.4))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .dsGlass(tint: isTicked ? DS.Palette.lime(0.1) : DS.Palette.glass(0.6), in: Capsule(), border: isTicked ? DS.Palette.lime(0.5) : DS.Palette.hairline(0.12))
        }
        .buttonStyle(.dsPress)
        .accessibilityAddTraits(isTicked ? .isSelected : [])
    }
}

/// A band of the accent sweeping down the screen once.
private struct AdSweep: View {
    @State private var travelled = false

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, DS.Palette.accent(0.55), DS.Palette.accentWarm.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: proxy.size.height * 0.5)
            .offset(y: travelled ? proxy.size.height : -proxy.size.height * 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1)) { travelled = true }
            }
        }
        .ignoresSafeArea()
    }
}
