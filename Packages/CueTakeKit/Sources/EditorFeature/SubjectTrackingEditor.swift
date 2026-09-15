import DesignSystem
import SwiftUI
import UIKit

/// Selects an arbitrary subject on the source picture. The editor never asks for tracker boxes or
/// directions: the gesture is the instruction, and the engine walks both ways from this frame.
struct SubjectTrackingEditor: View {
    @Bindable var model: EditorModel
    let onClose: () -> Void

    private enum MarkingMode: String, CaseIterable {
        case lasso, paint
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var mode: MarkingMode = .lasso
    @State private var strokes: [[CGPoint]] = []
    @State private var activeStroke: [CGPoint] = []
    @State private var zoom = 1.15
    @State private var successPulse = 0

    private var isAnalyzing: Bool {
        if case .analyzing = model.mainSubjectTracking { return true }
        return false
    }

    private var isApplied: Bool {
        if case .applied = model.mainSubjectTracking { return true }
        return false
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                    .padding(.top, proxy.safeAreaInsets.top + 6)

                GeometryReader { stage in
                    let frame = imageRect(in: stage.size)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous)
                            .fill(DS.Palette.camera)

                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: frame.width, height: frame.height)
                                .offset(x: frame.minX, y: frame.minY)
                        } else {
                            ProgressView()
                                .tint(DS.Palette.lime)
                                .frame(width: stage.size.width, height: stage.size.height)
                        }

                        selectionWash(in: frame)
                        instruction
                            .frame(width: stage.size.width)
                            .padding(.top, 14)
                    }
                    .contentShape(Rectangle())
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous))
                    .gesture(markingGesture(in: frame))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous)
                            .stroke(DS.Palette.hairline(0.12), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .onAppear { selectionFrame = frame }
                    .onChange(of: frame) { _, value in selectionFrame = value }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                footer
                    .padding(.bottom, proxy.safeAreaInsets.bottom + 8)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(DS.Palette.screen.ignoresSafeArea())
        .statusBarHidden(true)
        .task { image = await model.subjectSelectionFrame() }
        .sensoryFeedback(.success, trigger: successPulse)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(DS.Palette.hairline(0.08)))
            }
            .buttonStyle(.dsPressIcon)
            .accessibilityLabel(Text("editor.track.close", bundle: .module))

            VStack(alignment: .leading, spacing: 2) {
                Text("editor.track.title", bundle: .module)
                    .dsFont(.archivo, .bold, 18)
                    .foregroundStyle(DS.Palette.ink)
                Text("editor.track.subtitle", bundle: .module)
                    .dsFont(.sans, .medium, 10)
                    .foregroundStyle(DS.Palette.ink(0.48))
            }
            Spacer(minLength: 0)
            if !strokes.isEmpty || !activeStroke.isEmpty {
                Button {
                    withAnimation(DS.Motion.snap) {
                        strokes.removeAll()
                        activeStroke.removeAll()
                    }
                } label: {
                    Label(String(localized: "editor.track.clear", bundle: .module), systemImage: "arrow.counterclockwise")
                        .dsFont(.sans, .semibold, 11)
                        .foregroundStyle(DS.Palette.ink(0.7))
                        .frame(height: 44)
                }
                .buttonStyle(.dsPress(radius: 18))
                .disabled(isAnalyzing)
            }
        }
        .padding(.horizontal, 16)
    }

    private var instruction: some View {
        HStack(spacing: 7) {
            Image(systemName: isApplied ? "checkmark.circle.fill" : isAnalyzing ? "scope" : "hand.draw")
                .foregroundStyle(isApplied ? DS.Palette.lime : DS.Palette.accent)
                .symbolEffect(.breathe, options: .repeating, isActive: isAnalyzing)
            Text(statusText)
                .dsFont(.sans, .semibold, 11)
                .foregroundStyle(DS.Palette.ink)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(DS.Palette.inkInverse(0.68)))
        .animation(DS.Motion.snap, value: model.mainSubjectTracking)
    }

    private var statusText: String {
        switch model.mainSubjectTracking {
        case .idle: String(localized: "editor.track.instruction", bundle: .module)
        case .analyzing(let progress): String(localized: "editor.track.progress \(Int((progress * 100).rounded()))", bundle: .module)
        case .applied: String(localized: "editor.track.applied", bundle: .module)
        case .noFace, .failed: String(localized: "editor.track.failed", bundle: .module)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(MarkingMode.allCases, id: \.self) { choice in
                    let selected = mode == choice
                    Button {
                        withAnimation(DS.Motion.snap) { mode = choice }
                    } label: {
                        Label(
                            String(localized: choice == .lasso ? "editor.track.lasso" : "editor.track.paint", bundle: .module),
                            systemImage: choice == .lasso ? "lasso" : "paintbrush.pointed"
                        )
                        .dsFont(.sans, .semibold, 11)
                        .foregroundStyle(selected ? DS.Palette.inkInverse : DS.Palette.ink(0.68))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Capsule().fill(selected ? DS.Palette.lime : DS.Palette.hairline(0.07)))
                    }
                    .buttonStyle(.dsPress(radius: 21))
                    .disabled(isAnalyzing)
                }
            }

            HStack(spacing: 8) {
                Text("editor.track.closeness", bundle: .module)
                    .dsFont(.sans, .medium, 11)
                    .foregroundStyle(DS.Palette.ink(0.55))
                Spacer(minLength: 4)
                ForEach([1.10, 1.15, 1.20], id: \.self) { value in
                    Button {
                        withAnimation(DS.Motion.snap) { zoom = value }
                    } label: {
                        Text(verbatim: "+%\(Int(((value - 1) * 100).rounded()))")
                            .dsFont(.mono, .medium, 10)
                            .foregroundStyle(abs(zoom - value) < 0.001 ? DS.Palette.inkInverse : DS.Palette.ink(0.7))
                            .frame(width: 58, height: 36)
                            .background(Capsule().fill(abs(zoom - value) < 0.001 ? DS.Palette.accent : DS.Palette.hairline(0.07)))
                    }
                    .buttonStyle(.dsPress(radius: 18))
                    .disabled(isAnalyzing)
                }
            }

            Button {
                guard let bounds = normalizedSelectionBounds else { return }
                Task {
                    await model.trackSelectedSubject(in: bounds, zoom: zoom)
                    if isApplied { successPulse += 1 }
                }
            } label: {
                HStack(spacing: 9) {
                    if isAnalyzing {
                        ProgressView().controlSize(.small).tint(DS.Palette.inkInverse)
                    } else {
                        Image(systemName: isApplied ? "checkmark" : "scope")
                    }
                    Text(isApplied ? "editor.track.done" : "editor.track.start", bundle: .module)
                        .contentTransition(.symbolEffect(.replace))
                }
                .dsFont(.sans, .semibold, 13)
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Capsule().fill(isApplied ? DS.Palette.lime : DS.Palette.accent))
            }
            .buttonStyle(.dsPress(radius: 25))
            .disabled(normalizedSelectionBounds == nil || isAnalyzing || image == nil || isApplied)
            .opacity(normalizedSelectionBounds == nil && !isApplied ? 0.42 : 1)

            if isApplied {
                Button(action: onClose) {
                    Text("editor.track.return", bundle: .module)
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.ink(0.72))
                        .frame(height: 36)
                }
                .buttonStyle(.dsPress(radius: 18))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 16)
        .dsMotion(DS.Motion.settle, reduced: reduceMotion, value: isApplied)
    }

    private func imageRect(in size: CGSize) -> CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func markingGesture(in frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isAnalyzing, image != nil, frame.contains(value.location) else { return }
                if let last = activeStroke.last, hypot(last.x - value.location.x, last.y - value.location.y) < 2 { return }
                activeStroke.append(value.location)
            }
            .onEnded { _ in
                guard !activeStroke.isEmpty else { return }
                if activeStroke.count == 1, let point = activeStroke.first {
                    let r = min(frame.width, frame.height) * 0.09
                    strokes.append([
                        CGPoint(x: point.x - r, y: point.y - r),
                        CGPoint(x: point.x + r, y: point.y + r),
                    ])
                } else {
                    strokes.append(activeStroke)
                }
                activeStroke.removeAll()
            }
    }

    @ViewBuilder
    private func selectionWash(in frame: CGRect) -> some View {
        let all = strokes + (activeStroke.isEmpty ? [] : [activeStroke])
        Canvas { context, _ in
            for stroke in all {
                guard let first = stroke.first else { continue }
                var path = Path()
                path.move(to: first)
                for point in stroke.dropFirst() { path.addLine(to: point) }
                if mode == .lasso, stroke.count > 2 { path.closeSubpath() }
                if mode == .paint {
                    context.stroke(path, with: .color(DS.Palette.lime(0.48)), style: StrokeStyle(lineWidth: 26, lineCap: .round, lineJoin: .round))
                } else {
                    context.fill(path, with: .color(DS.Palette.lime(0.13)))
                    context.stroke(path, with: .color(DS.Palette.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
        .mask(Rectangle().path(in: frame))
        .overlay {
            if let bounds = selectionBounds, !isAnalyzing {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.Palette.lime, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    .frame(width: bounds.width, height: bounds.height)
                    .position(x: bounds.midX, y: bounds.midY)
                    .allowsHitTesting(false)
            }
        }
    }

    private var selectionBounds: CGRect? {
        let points = strokes.flatMap { $0 } + activeStroke
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY)).insetBy(dx: -10, dy: -10)
    }

    private var normalizedSelectionBounds: CGRect? {
        guard image != nil, let selectionBounds else { return nil }
        guard let stage = selectionFrame else { return nil }
        let clipped = selectionBounds.intersection(stage)
        guard clipped.width >= 8, clipped.height >= 8 else { return nil }
        return CGRect(
            x: (clipped.minX - stage.minX) / stage.width,
            y: (clipped.minY - stage.minY) / stage.height,
            width: clipped.width / stage.width,
            height: clipped.height / stage.height
        )
    }

    @State private var selectionFrame: CGRect?
}
