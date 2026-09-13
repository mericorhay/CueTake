import Domain
import Foundation

/// What happened when a plan was applied.
public struct EditPlanOutcome: Sendable, Equatable {
    public var applied: Int
    /// Operations that could not be carried out, by type — an unknown clip, an unknown operation.
    public var skipped: [String]
}

/// Carries out an AI edit plan with the editor's own tools, as one undoable step.
///
/// Nothing here is new editing code. A cut is `rebuild(segmentAt:keeping:)`, a speed change is
/// `updatePlayback` — the same calls the buttons make — so a plan can only do what a person could
/// have done by hand, and everything it does is visible on the timeline and undone by one tap.
///
/// Clips are addressed by id, never by position: a plan's second operation must not land on the
/// wrong clip because its first one split something. Every change to a clip's footage is gathered
/// first and applied in one rebuild per clip for the same reason.
extension EditorModel {
    public func document(beatStep: Double = 0.25) -> EditDocument {
        EditDocument(project: project, beatStep: beatStep)
    }

    @discardableResult
    public func apply(_ plan: EditPlan) -> EditPlanOutcome {
        record("editor.change.ai", symbol: "sparkles")
        isApplyingPlan = true
        defer { isApplyingPlan = false }

        var applied = 0
        var skipped: [String] = []

        func index(of clip: String) -> Int? {
            project.segments.firstIndex { $0.id.uuidString == clip }
        }

        // 1. Settings of clips, captions, sound and look.
        for operation in plan.operations {
            switch operation {
            case .setSpeed(let clip, let speed):
                guard let i = index(of: clip) else { skipped.append(operation.type); continue }
                updatePlayback(at: i) { $0.speed = speed; $0.freeze = nil }
                applied += 1
            case .reverse(let clip, let on):
                guard let i = index(of: clip) else { skipped.append(operation.type); continue }
                updatePlayback(at: i) { $0.isReversed = on }
                applied += 1
            case .freeze(let clip, let seconds):
                guard let i = index(of: clip) else { skipped.append(operation.type); continue }
                updatePlayback(at: i) { $0.freeze = seconds.map { MediaTime(seconds: $0) } }
                applied += 1
            case .setCaptionText(let caption, let text):
                guard let i = project.segments.firstIndex(where: { $0.captions.contains { $0.id.uuidString == caption } }),
                      let id = UUID(uuidString: caption)
                else { skipped.append(operation.type); continue }
                project.segments[i].setCaptionText(id, to: text)
                applied += 1
            case .captionStyle(let preset, let position):
                guard CaptionStyle.presetIDs.contains(preset) else { skipped.append(operation.type); continue }
                let previous = project.captionStyle
                let y = position.map { min(max($0, 0.08), 0.92) } ?? previous.position.y
                project.captionStyle = CaptionStyle.preset(preset, position: CaptionPosition(x: 0.5, y: y))
                if previous.maxWordsPerCue != project.captionStyle.maxWordsPerCue {
                    for s in project.segments.indices where !project.segments[s].captions.contains(where: \.isUserEdited) {
                        project.segments[s].refreshCaptions(maxWordsPerCue: project.captionStyle.maxWordsPerCue)
                    }
                }
                applied += 1
            case .voiceCleanup(let on):
                setVoiceEffects(AudioEffects(noiseReduction: on, voiceEnhance: on, deRumble: on))
                applied += 1
            case .setMusicLevel(let audio, let gain):
                guard let id = UUID(uuidString: audio), project.audio.contains(where: { $0.id == id }) else {
                    skipped.append(operation.type); continue
                }
                updateAudio(id) { $0.setDecibels(gain) }
                applied += 1
            case .unknown(let type):
                skipped.append(type)
            default:
                continue
            }
        }

        // 2. Footage: every cut for a clip gathered, then one rebuild.
        var cuts: [String: [ClosedRange<Double>]] = [:]
        for operation in plan.operations {
            switch operation {
            case .cut(let clip, let from, let to):
                guard index(of: clip) != nil else { skipped.append(operation.type); continue }
                cuts[clip, default: []].append(from...to)
                applied += 1
            case .removeWords(let clip, let words):
                guard let i = index(of: clip) else { skipped.append(operation.type); continue }
                let spoken = spokenWords(at: i)
                let ranges = words.filter { spoken.indices.contains($0) }.map {
                    spoken[$0].range.start.seconds...spoken[$0].range.end.seconds
                }
                guard !ranges.isEmpty else { skipped.append(operation.type); continue }
                cuts[clip, default: []].append(contentsOf: ranges)
                applied += 1
            case .trimPauses(let clip, let minPause):
                let targets = clip.map { [$0] } ?? project.segments.map(\.id.uuidString)
                var found = false
                for target in targets {
                    guard let i = index(of: target) else { continue }
                    // A little air left at both ends of every pause, so the cut sounds like a
                    // breath rather than a splice.
                    let gaps = silenceGaps(at: i, threshold: max(0.2, minPause))
                        .compactMap { gap -> ClosedRange<Double>? in
                            let lower = gap.lowerBound + 0.12
                            let upper = gap.upperBound - 0.12
                            return upper > lower ? lower...upper : nil
                        }
                    if !gaps.isEmpty {
                        cuts[target, default: []].append(contentsOf: gaps)
                        found = true
                    }
                }
                if found { applied += 1 }
            default:
                continue
            }
        }
        for (clip, ranges) in cuts {
            guard let i = index(of: clip) else { continue }
            let total = project.segments[i].selectedTake?.sourceRange.duration.seconds ?? project.segments[i].sourceSeconds
            let keep = Self.complement(of: ranges, within: total)
            if keep.isEmpty {
                if project.segments.count > 1 { deleteSegment(at: i) }
            } else {
                rebuild(segmentAt: i, keeping: keep)
            }
        }

        // 3. Clips removed.
        for operation in plan.operations {
            guard case .deleteClip(let clip) = operation else { continue }
            guard let i = index(of: clip), project.segments.count > 1 else { skipped.append(operation.type); continue }
            deleteSegment(at: i)
            applied += 1
        }

        // 4. Order.
        for operation in plan.operations {
            guard case .reorder(let order) = operation else { continue }
            let ranked = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            let reordered = project.segments.enumerated().sorted { left, right in
                let a = ranked[left.element.id.uuidString] ?? (order.count + left.offset)
                let b = ranked[right.element.id.uuidString] ?? (order.count + right.offset)
                return a < b
            }.map(\.element)
            if reordered.map(\.id) != project.segments.map(\.id) {
                project.segments = reordered
            }
            applied += 1
        }

        project.updatedAt = .now
        seek(to: min(playhead, duration))
        return EditPlanOutcome(applied: applied, skipped: skipped)
    }

    /// The parts of `0...total` not covered by any range, merged and clamped.
    static func complement(of ranges: [ClosedRange<Double>], within total: Double) -> [ClosedRange<Double>] {
        let sorted = ranges
            .map { max(0, $0.lowerBound)...min(total, max($0.lowerBound, $0.upperBound)) }
            .sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Double>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound + 0.02 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        var keep: [ClosedRange<Double>] = []
        var cursor = 0.0
        for range in merged {
            if range.lowerBound - cursor > 0.13 { keep.append(cursor...range.lowerBound) }
            cursor = max(cursor, range.upperBound)
        }
        if total - cursor > 0.13 { keep.append(cursor...total) }
        return keep
    }
}
