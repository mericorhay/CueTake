import DesignSystem
import Domain
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
    @State private var isCorrecting = false
    /// A finished track is shown for review; this goes back to drawing a new one from scratch.
    @State private var isRedrawing = false
    @State private var trackingTask: Task<Void, Never>?
    @State private var frameTask: Task<Void, Never>?

    private var isAnalyzing: Bool {
        if case .analyzing = model.mainSubjectTracking { return true }
        return false
    }

    private var isApplied: Bool {
        if case .applied = model.mainSubjectTracking { return true }
        return false
    }

    private var isReviewing: Bool {
        !isCorrecting && !isRedrawing && !model.subjectTrackReviewPoints.isEmpty
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
        .onDisappear {
            trackingTask?.cancel()
            frameTask?.cancel()
            model.mainSubjectTracking = .idle
        }
        .sensoryFeedback(.success, trigger: successPulse)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: close) {
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
                    .foregroundStyle(DS.Palette.ink(0.56))
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
            Image(systemName: isReviewing ? "checkmark.circle.fill" : isAnalyzing ? "scope" : "hand.draw")
                .foregroundStyle(isReviewing ? DS.Palette.lime : DS.Palette.accent)
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
        if isCorrecting, !isAnalyzing {
            return String(localized: "editor.track.correctInstruction", bundle: .module)
        }
        if isReviewing {
            return String(localized: "editor.track.applied", bundle: .module)
        }
        return switch model.mainSubjectTracking {
        case .idle: String(localized: "editor.track.instruction", bundle: .module)
        case .analyzing(let progress): String(localized: "editor.track.progress \(Int((progress * 100).rounded()))", bundle: .module)
        case .applied: String(localized: "editor.track.instruction", bundle: .module)
        case .noFace, .failed: String(localized: "editor.track.failed", bundle: .module)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if isReviewing {
                SubjectTrackConfidenceSpine(points: model.subjectTrackReviewPoints) { point in
                    beginCorrection(at: point)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                HStack(spacing: 8) {
                    Button {
                        withAnimation(DS.Motion.settle) {
                            isRedrawing = true
                            strokes.removeAll()
                            activeStroke.removeAll()
                        }
                        model.mainSubjectTracking = .idle
                    } label: {
                        Label(String(localized: "editor.track.redraw", bundle: .module), systemImage: "hand.draw")
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(DS.Palette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Capsule().fill(DS.Palette.hairline(0.09)))
                    }
                    .buttonStyle(.dsPress(radius: 22))

                    Button {
                        guard let (index, _) = model.segmentAtPlayhead else { return }
                        let id = model.project.segments[index].id
                        withAnimation(DS.Motion.settle) {
                            model.removeSubjectTrack(forSegment: id)
                            strokes.removeAll()
                            activeStroke.removeAll()
                        }
                    } label: {
                        Label(String(localized: "editor.trackPanel.delete", bundle: .module), systemImage: "trash")
                            .dsFont(.sans, .semibold, 12)
                            .foregroundStyle(DS.Palette.accentWarm)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Capsule().fill(DS.Palette.accentWarm.opacity(0.1)))
                    }
                    .buttonStyle(.dsPress(radius: 22))
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                Button(action: close) {
                    Text("editor.track.return", bundle: .module)
                        .dsFont(.sans, .semibold, 12)
                        .foregroundStyle(DS.Palette.ink(0.72))
                        .frame(height: 36)
                }
                .buttonStyle(.dsPress(radius: 18))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                trackingControls
            }
        }
        .padding(.horizontal, 16)
        .dsMotion(DS.Motion.settle, reduced: reduceMotion, value: isReviewing)
    }

    private var trackingControls: some View {
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
                trackingTask = Task {
                    await model.trackSelectedSubject(
                        in: bounds,
                        zoom: zoom,
                        correctionRadius: isCorrecting ? 2 : nil
                    )
                    guard !Task.isCancelled else { return }
                    if isApplied {
                        withAnimation(DS.Motion.settle) {
                            isCorrecting = false
                            isRedrawing = false
                            strokes.removeAll()
                            activeStroke.removeAll()
                        }
                        successPulse += 1
                    }
                    trackingTask = nil
                }
            } label: {
                HStack(spacing: 9) {
                    if isAnalyzing {
                        ProgressView().controlSize(.small).tint(DS.Palette.inkInverse)
                    } else {
                        Image(systemName: "scope")
                    }
                    Text(isCorrecting ? "editor.track.correct" : "editor.track.start", bundle: .module)
                        .contentTransition(.symbolEffect(.replace))
                }
                .dsFont(.sans, .semibold, 13)
                .foregroundStyle(DS.Palette.inkInverse)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Capsule().fill(DS.Palette.accent))
            }
            .buttonStyle(.dsPress(radius: 25))
            .disabled(normalizedSelectionBounds == nil || isAnalyzing || image == nil)
            .opacity(normalizedSelectionBounds == nil ? 0.42 : 1)
        }
    }

    private func beginCorrection(at point: SubjectTrackReviewPoint) {
        withAnimation(DS.Motion.settle) {
            isCorrecting = true
            strokes.removeAll()
            activeStroke.removeAll()
            image = nil
        }
        model.beginSubjectCorrection(at: point.timelineTime)
        frameTask?.cancel()
        frameTask = Task {
            let frame = await model.subjectSelectionFrame()
            guard !Task.isCancelled else { return }
            image = frame
            frameTask = nil
        }
    }

    private func close() {
        trackingTask?.cancel()
        frameTask?.cancel()
        trackingTask = nil
        frameTask = nil
        model.mainSubjectTracking = .idle
        onClose()
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
                guard !isAnalyzing, !isReviewing, image != nil, frame.contains(value.location) else { return }
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

private struct SubjectTrackConfidenceSpine: View {
    let points: [SubjectTrackReviewPoint]
    let onSelect: (SubjectTrackReviewPoint) -> Void

    private var weakPoints: [SubjectTrackReviewPoint] {
        SubjectTrackReviewPoint.reviewIssues(in: points)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(String(localized: "editor.track.confidence", bundle: .module), systemImage: "waveform.path.ecg")
                    .dsFont(.sans, .semibold, 11)
                    .foregroundStyle(DS.Palette.ink(0.76))
                Spacer(minLength: 8)
                Text(
                    weakPoints.isEmpty
                        ? String(localized: "editor.track.stable", bundle: .module)
                        : String(localized: "editor.track.weak \(weakPoints.count)", bundle: .module)
                )
                .dsFont(.mono, .medium, 10)
                .foregroundStyle(weakPoints.isEmpty ? DS.Palette.lime : DS.Palette.accentWarm)
            }

            GeometryReader { proxy in
                ZStack {
                    Capsule().fill(DS.Palette.hairline(0.08))
                    Canvas { context, size in
                        for point in points {
                            let x = min(max(point.progress, 0), 1) * size.width
                            let height = max(5, point.confidence * (size.height - 8))
                            let rect = CGRect(x: x - 1.5, y: (size.height - height) / 2, width: 3, height: height)
                            context.fill(
                                Capsule().path(in: rect),
                                with: .color(point.needsReview ? DS.Palette.accentWarm : DS.Palette.lime)
                            )
                        }
                    }
                    .padding(.horizontal, 5)
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        let trackWidth = max(proxy.size.width - 10, 1)
                        let tapped = min(max((value.location.x - 5) / trackWidth, 0), 1)
                        guard proxy.size.width > 0,
                              let nearest = points.min(by: {
                                  abs($0.progress - tapped) < abs($1.progress - tapped)
                              })
                        else { return }
                        onSelect(nearest)
                    }
                )
            }
            .frame(height: 42)

            if let weakest = weakPoints.min(by: { $0.confidence < $1.confidence }) {
                Button { onSelect(weakest) } label: {
                    Label(String(localized: "editor.track.correctWeakest", bundle: .module), systemImage: "scope")
                        .dsFont(.sans, .semibold, 11)
                        .foregroundStyle(DS.Palette.accentWarm)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.dsPress(radius: 18))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.Palette.hairline(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DS.Palette.hairline(0.08), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
