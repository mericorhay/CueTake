import DesignSystem
import Domain
import SwiftUI
import UIKit

/// The videos one "Generate video" step is making, one tile each.
///
/// Watching is the whole point of a long generation: a single spinner over the app for two
/// minutes says nothing, while ten tiles that develop one by one say exactly how far along it is,
/// which ones failed, and what came back.
@MainActor
@Observable
public final class GenerationBoard {
    public let stepID: WorkflowStep.ID
    public let modelTitle: String
    /// Width over height of the videos being made.
    public let aspect: Double
    public private(set) var tiles: [GenerationTile]

    public init(stepID: WorkflowStep.ID, modelTitle: String, aspect: Double, prompts: [String]) {
        self.stepID = stepID
        self.modelTitle = modelTitle
        self.aspect = aspect
        tiles = prompts.enumerated().map { GenerationTile(id: $0.offset, prompt: $0.element) }
    }

    public var doneCount: Int { tiles.filter { $0.phase == .done }.count }
    public var failedCount: Int { tiles.filter { $0.phase == .failed }.count }
    public var settledCount: Int { doneCount + failedCount }
    public var isFinished: Bool { settledCount == tiles.count }

    public func start(_ index: Int) {
        guard tiles.indices.contains(index) else { return }
        tiles[index].phase = .working
        tiles[index].started = .now
    }

    public func progress(_ index: Int, _ value: Double?) {
        guard tiles.indices.contains(index), tiles[index].phase == .working, let value else { return }
        tiles[index].progress = min(max(value, 0), 1)
    }

    public func finish(_ index: Int, thumbnail: Data?) {
        guard tiles.indices.contains(index) else { return }
        tiles[index].phase = .done
        tiles[index].progress = 1
        tiles[index].thumbnail = thumbnail.flatMap(UIImage.init(data:))
    }

    public func fail(_ index: Int, message: String?) {
        guard tiles.indices.contains(index) else { return }
        tiles[index].phase = .failed
        tiles[index].failure = message
    }

    /// Tiles that never started, when the run is stopped.
    public func cancelWaiting() {
        for index in tiles.indices where tiles[index].phase == .queued || tiles[index].phase == .working {
            tiles[index].phase = .failed
            tiles[index].failure = String(localized: "studio.generate.stopped", bundle: .module)
        }
    }
}

public struct GenerationTile: Identifiable {
    public enum Phase: Hashable {
        case queued, working, done, failed
    }

    public let id: Int
    public let prompt: String
    public var phase: Phase = .queued
    public var started: Date?
    public var progress: Double?
    public var thumbnail: UIImage?
    public var failure: String?
}

// MARK: - View

struct GenerationBoardView: View {
    let board: GenerationBoard

    @State private var selected: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: board.aspect < 1 ? 62 : 96), spacing: 8)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(board.tiles) { tile in
                    GenerationTileView(tile: tile, aspect: board.aspect, isSelected: selected == tile.id)
                        .onTapGesture {
                            withAnimation(DS.Motion.snap) { selected = selected == tile.id ? nil : tile.id }
                        }
                }
            }

            if let selected, let tile = board.tiles.first(where: { $0.id == selected }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: tile.prompt)
                        .dsFont(.sans, .regular, 11, lineHeight: 1.35)
                        .foregroundStyle(DS.Palette.ink(0.75))
                    if let failure = tile.failure {
                        Text(verbatim: failure)
                            .dsFont(.sans, .medium, 11, lineHeight: 1.35)
                            .foregroundStyle(DS.Palette.accentWarm)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.Palette.hairline(0.06)))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.Palette.hairline(0.04)))
        .sensoryFeedback(.impact(weight: .light), trigger: board.doneCount)
        .sensoryFeedback(.error, trigger: board.failedCount)
        .sensoryFeedback(.success, trigger: board.isFinished) { _, finished in finished && board.doneCount > 0 }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : DS.Motion.settle, value: board.settledCount)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: board.isFinished ? "checkmark.circle.fill" : "wand.and.stars")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.lime)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, options: .repeating, isActive: !board.isFinished && !reduceMotion)
                Text(verbatim: board.modelTitle)
                    .dsFont(.sans, .semibold, 12)
                    .foregroundStyle(DS.Palette.ink(0.85))
                Spacer(minLength: 0)
                Text(verbatim: "\(board.doneCount)/\(board.tiles.count)")
                    .dsFont(.mono, .semibold, 12)
                    .foregroundStyle(DS.Palette.ink)
                    .contentTransition(.numericText(value: Double(board.doneCount)))
                if board.failedCount > 0 {
                    Text(verbatim: "−\(board.failedCount)")
                        .dsFont(.mono, .medium, 11)
                        .foregroundStyle(DS.Palette.accentWarm)
                        .contentTransition(.numericText(value: Double(board.failedCount)))
                }
            }

            // Two layers: what is made, and what has at least finished trying.
            GeometryReader { proxy in
                let total = max(Double(board.tiles.count), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Palette.hairline(0.08))
                    Capsule()
                        .fill(DS.Palette.accentWarm.opacity(0.5))
                        .frame(width: proxy.size.width * Double(board.settledCount) / total)
                    Capsule()
                        .fill(LinearGradient(colors: [DS.Palette.lime, DS.Palette.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * Double(board.doneCount) / total)
                }
            }
            .frame(height: 5)
        }
    }
}

private struct GenerationTileView: View {
    let tile: GenerationTile
    let aspect: Double
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shake = 0

    var body: some View {
        ZStack {
            switch tile.phase {
            case .queued:
                queued
                    .transition(.opacity)
            case .working:
                DSDevelopingFilm(started: tile.started, progress: tile.progress)
                    .transition(.opacity)
            case .done:
                done
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace).combined(with: .scale(scale: 1.12)))
            case .failed:
                failed
                    .transition(.opacity)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? DS.Palette.ink : .clear, lineWidth: 2)
        }
        .overlay(alignment: .topLeading) {
            Text(verbatim: "\(tile.id + 1)")
                .dsFont(.mono, .semibold, 10)
                .foregroundStyle(tile.phase == .done ? DS.Palette.ink : DS.Palette.ink(0.55))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(tile.phase == .done ? DS.Palette.inkInverse(0.55) : .clear))
                .padding(5)
        }
        .keyframeAnimator(initialValue: 0.0, trigger: shake) { content, offset in
            content.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0, duration: 0.02)
                SpringKeyframe(-7, duration: 0.07)
                SpringKeyframe(6, duration: 0.07)
                SpringKeyframe(-4, duration: 0.07)
                SpringKeyframe(0, duration: 0.12)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.78), value: tile.phase)
        .onChange(of: tile.phase) { _, phase in
            if phase == .failed, !reduceMotion { shake += 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(tile.id + 1). \(tile.prompt)"))
    }

    private var queued: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(DS.Palette.hairline(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.Palette.hairline(0.03)))
    }

    @ViewBuilder
    private var done: some View {
        if let thumbnail = tile.thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Palette.inkInverse, DS.Palette.lime)
                        .padding(5)
                        .transition(.symbolEffect(.drawOn))
                }
        } else {
            ZStack {
                DS.Palette.lime.opacity(0.18)
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Palette.lime)
            }
        }
    }

    private var failed: some View {
        ZStack {
            DS.Palette.accentWarm.opacity(0.14)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Palette.accentWarm)
                .symbolEffect(.bounce, value: shake)
        }
    }
}
