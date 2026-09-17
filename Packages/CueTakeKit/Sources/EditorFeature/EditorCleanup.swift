import Domain
import Foundation

/// Cleaning a take against its script: pauses, fillers, repeats and restarts.
///
/// Everything goes through `rebuild`, the same primitive deleting a phrase uses, so a cleaned clip
/// is ordinary clips pointing into the same file. The pieces remember where they came from, which
/// is what lets the cut be opened again later, after other edits, not only by undo.
extension EditorModel {
    public func cleanupPlan(at index: Int, options: CleanupOptions = CleanupOptions()) -> CleanupPlan? {
        guard project.segments.indices.contains(index) else { return nil }
        return CleanupPlanner.plan(
            for: project.segments[index],
            localeIdentifier: project.localeIdentifier,
            options: options
        )
    }

    /// Cuts the chosen items out of their clip. Returns the seconds removed.
    @discardableResult
    public func applyCleanup(_ plan: CleanupPlan, chosen: Set<CleanupItem.ID>) -> Double {
        guard let index = project.segments.firstIndex(where: { $0.id == plan.segmentID }) else { return 0 }
        let segment = project.segments[index]
        let kept = plan.kept(chosen)
        let saved = plan.saved(chosen)
        guard !kept.isEmpty, saved > 0.05 else { return 0 }

        let words = segment.selectedTake?.transcript?.words ?? []
        let scripts = plan.alignment.map {
            Self.scripts(for: kept, words: words, script: segment.script, alignment: $0)
        }
        // A piece of an earlier cleanup stays in that cleanup, so opening it brings back the clip
        // as it was shot rather than as it was after the first pass.
        let origin = segment.cleanup ?? CleanupOrigin(
            group: UUID(),
            script: segment.script,
            takes: segment.takes,
            selectedTakeID: segment.selectedTakeID
        )
        rebuild(segmentAt: index, keeping: kept, scripts: scripts, origin: origin)
        return saved
    }

    /// Cleans every clip with the default choices, limited to `kinds`. One undo step.
    @discardableResult
    public func cleanUpAllClips(kinds: Set<CleanupItem.Kind>, options: CleanupOptions = CleanupOptions()) -> (clips: Int, seconds: Double) {
        let plans = project.segments.indices.compactMap { cleanupPlan(at: $0, options: options) }
        let work = plans.compactMap { plan -> (CleanupPlan, Set<CleanupItem.ID>)? in
            let chosen = Set(plan.items.filter { $0.isOn && kinds.contains($0.kind) }.map(\.id))
            return plan.saved(chosen) > 0.05 && !plan.kept(chosen).isEmpty ? (plan, chosen) : nil
        }
        guard !work.isEmpty else { return (0, 0) }

        record("editor.change.cleanup", symbol: "wand.and.stars")
        let wasApplying = isApplyingPlan
        isApplyingPlan = true
        defer { isApplyingPlan = wasApplying }

        var clips = 0
        var seconds = 0.0
        // Last clip first: a rebuilt clip becomes several, and the ones before it keep their place.
        for (plan, chosen) in work.reversed() {
            let saved = applyCleanup(plan, chosen: chosen)
            if saved > 0 {
                clips += 1
                seconds += saved
            }
        }
        return (clips, seconds)
    }

    /// The run of clips one cleanup made, around `index`, with what it removed.
    public func cleanupGroup(at index: Int) -> (range: ClosedRange<Int>, removed: Double)? {
        let segments = project.segments
        guard segments.indices.contains(index), let group = segments[index].cleanup?.group else { return nil }
        var lower = index
        while lower > 0, segments[lower - 1].cleanup?.group == group { lower -= 1 }
        var upper = index
        while upper + 1 < segments.count, segments[upper + 1].cleanup?.group == group { upper += 1 }
        guard let original = segments[lower...upper].lazy.compactMap({ $0.cleanup?.originalTake }).first else { return nil }
        let left = segments[lower...upper].reduce(0.0) { $0 + ($1.selectedTake?.sourceRange.duration.seconds ?? 0) }
        return (lower...upper, max(0, original.sourceRange.duration.seconds - left))
    }

    /// Puts a cleaned clip back as it was shot.
    public func restoreCleanup(at index: Int) {
        guard let group = cleanupGroup(at: index),
              let carrier = group.range.first(where: { project.segments[$0].cleanup?.takes != nil }),
              let origin = project.segments[carrier].cleanup,
              let takes = origin.takes, !takes.isEmpty
        else { return }

        record("editor.change.restoreCleanup", symbol: "arrow.uturn.backward")
        let pieces = Array(project.segments[group.range])
        let from = start(at: group.range.lowerBound)
        let before = pieces.reduce(0.0) { $0 + $1.barWeight }

        var restored = project.segments[carrier]
        restored.takes = takes
        restored.selectedTakeID = origin.selectedTakeID ?? takes.last?.id
        restored.script = origin.script
        restored.cleanup = nil
        restored.estimatedDuration = restored.selectedTake?.sourceRange.duration
        restored.refreshCaptions(maxWordsPerCue: project.captionStyle.maxWordsPerCue)

        let ids = Set(pieces.map(\.id))
        let lastID = pieces.last?.id
        project.transitions.removeAll { ids.contains($0.after) && $0.after != lastID }
        for t in project.transitions.indices where project.transitions[t].after == lastID {
            project.transitions[t].after = restored.id
        }
        project.segments.replaceSubrange(group.range, with: [restored])

        // What was laid after the clip moves on by the footage that came back.
        let grown = restored.barWeight - before
        if grown > 0.001 {
            project.openGap(at: from + before, length: grown)
        }
        project.updatedAt = .now
        inspectedSegment = restored.id
        seek(to: min(playhead, duration))
    }

    /// The part of the script each kept span says, so a piece's prompter and alignment keep
    /// working from the script rather than from what happened to be said.
    static func scripts(
        for kept: [ClosedRange<Double>],
        words: [TimedWord],
        script: String,
        alignment: ScriptAlignment
    ) -> [String] {
        let scriptWords = ScriptText.words(in: script)
        var result: [String] = []
        var next = 0
        for (n, span) in kept.enumerated() {
            let inside = words.indices.filter {
                words[$0].range.start.seconds >= span.lowerBound - 0.001
                    && words[$0].range.end.seconds <= span.upperBound + 0.001
            }
            let matched = inside.compactMap { alignment.scriptIndex(ofSpoken: $0) }
            guard let low = matched.min(), let high = matched.max(), !scriptWords.isEmpty else {
                result.append(inside.map { words[$0].text }.joined(separator: " "))
                continue
            }
            // Words the reader skipped belong to the piece that follows them; the last piece takes
            // whatever is left of the script.
            let lower = min(next, low)
            let upper = n == kept.count - 1 ? scriptWords.count - 1 : high
            guard lower <= upper, upper < scriptWords.count else {
                result.append(inside.map { words[$0].text }.joined(separator: " "))
                continue
            }
            result.append(scriptWords[lower...upper].joined(separator: " "))
            next = upper + 1
        }
        return result
    }

    /// The best-reading take of a clip, when it is not the one in use.
    public func betterTake(at index: Int) -> (id: Take.ID, score: TakeScore)? {
        guard project.segments.indices.contains(index) else { return nil }
        let segment = project.segments[index]
        guard let best = segment.bestTake(localeIdentifier: project.localeIdentifier),
              best.id != segment.selectedTakeID
        else { return nil }
        return best
    }

    public func takeScore(_ take: Take, at index: Int) -> TakeScore? {
        guard project.segments.indices.contains(index) else { return nil }
        return TakeScore.score(take, script: project.segments[index].script, localeIdentifier: project.localeIdentifier)
    }
}
