import Foundation

/// Two people's edits to the same project, made into one.
///
/// A shared project changes on several phones at once. Saving whole documents over each other —
/// last save wins — throws away whatever the other person did in the meantime, which in an editor
/// is someone's afternoon. So a save that finds the project changed under it merges three
/// versions: the one both sides started from, this phone's, and the one already saved.
///
/// The rules, in the order they matter:
/// - A thing only one side changed takes that side's change. This is nearly every case: two
///   people rarely touch the same clip in the same minute.
/// - Things are matched by identity, not position, so a clip one person moved and a caption the
///   other retyped both survive.
/// - Something one side changed and the other deleted is kept, changed. Losing work is worse than
///   an extra clip, which is one tap to delete again.
/// - When both sides changed the same thing, the save being made now wins — it is the newer edit —
///   and the collision is reported so the person can be told.
///
/// Pure and deterministic: no clocks, no devices. The same three inputs always give the same
/// project, which is what lets it be tested properly.
public enum ProjectMerge {
    public struct Collision: Hashable, Sendable {
        /// Which part of the project, e.g. "segments" or "title".
        public var field: String
        /// The thing both sides changed, when it has an identity.
        public var id: UUID?
    }

    public struct Result: Sendable {
        public var project: Project
        /// Things both sides changed; this side's change was kept.
        public var collisions: [Collision]
        /// Whether the other side's work is in the result at all. False means this side simply
        /// replaces the saved one — nothing of theirs was waiting.
        public var tookTheirs: Bool
    }

    public static func merge(base: Project, mine: Project, theirs: Project) -> Result {
        var collisions: [Collision] = []
        var result = mine

        func scalar<T: Equatable>(_ path: WritableKeyPath<Project, T>, _ name: String) {
            let (value, clash) = pick(base: base[keyPath: path], mine: mine[keyPath: path], theirs: theirs[keyPath: path])
            result[keyPath: path] = value
            if clash { collisions.append(Collision(field: name, id: nil)) }
        }

        func list<T: Identifiable & Equatable>(_ path: WritableKeyPath<Project, [T]>, _ name: String) where T.ID == UUID {
            let merged = mergeList(base: base[keyPath: path], mine: mine[keyPath: path], theirs: theirs[keyPath: path])
            result[keyPath: path] = merged.items
            collisions += merged.clashes.map { Collision(field: name, id: $0) }
        }

        scalar(\.title, "title")
        scalar(\.format, "format")
        scalar(\.localeIdentifier, "localeIdentifier")
        scalar(\.captionStyle, "captionStyle")
        scalar(\.voiceEffects, "voiceEffects")
        scalar(\.mainVideoPlacement, "mainVideoPlacement")
        scalar(\.mainVideoVolume, "mainVideoVolume")
        scalar(\.captionWindow, "captionWindow")
        scalar(\.metadata, "metadata")

        // Clips go deeper than the others: one person retyping a clip's words while another fixes
        // its captions is the commonest collaboration there is, and it is not a collision.
        let clips = mergeList(base: base.segments, mine: mine.segments, theirs: theirs.segments, combine: mergeSegment)
        result.segments = clips.items
        collisions += clips.clashes.map { Collision(field: "segments", id: $0) }
        list(\.recordings, "recordings")
        list(\.audio, "audio")
        list(\.overlays, "overlays")
        list(\.videoLayers, "videoLayers")
        list(\.effects, "effects")
        list(\.transitions, "transitions")
        list(\.aiConversations, "aiConversations")

        // Footage is never lost to a merge: a recording any clip still points at stays, even if
        // one side had tidied it away.
        let used = Set(result.segments.flatMap { $0.takes.map(\.recordingID) } + result.videoLayers.map(\.recordingID))
        for recording in theirs.recordings + mine.recordings
        where used.contains(recording.id) && !result.recordings.contains(where: { $0.id == recording.id }) {
            result.recordings.append(recording)
        }

        result.schemaVersion = max(mine.schemaVersion, theirs.schemaVersion)
        result.createdAt = min(mine.createdAt, theirs.createdAt)
        result.updatedAt = max(mine.updatedAt, theirs.updatedAt)

        let tookTheirs = theirs != base
        return Result(project: result, collisions: collisions, tookTheirs: tookTheirs)
    }

    /// One value both sides may have changed. Returns the value and whether it was a real clash.
    static func pick<T: Equatable>(base: T, mine: T, theirs: T) -> (T, Bool) {
        if mine == theirs { return (mine, false) }
        if mine == base { return (theirs, false) }
        if theirs == base { return (mine, false) }
        return (mine, true)
    }

    /// A list of things with identities, merged item by item, in an order both sides would
    /// recognise.
    static func mergeList<T: Identifiable & Equatable>(
        base: [T],
        mine: [T],
        theirs: [T],
        combine: ((T, T, T) -> (T, Bool))? = nil
    ) -> (items: [T], clashes: [UUID]) where T.ID == UUID {
        let baseByID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let mineByID = Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let theirsByID = Dictionary(theirs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var kept: [UUID: T] = [:]
        var clashes: [UUID] = []
        let everyone = Set(baseByID.keys).union(mineByID.keys).union(theirsByID.keys)

        for id in everyone {
            let was = baseByID[id]
            let ours = mineByID[id]
            let others = theirsByID[id]
            switch (was, ours, others) {
            case let (was?, ours?, others?):
                let (value, clash) = combine?(was, ours, others) ?? pick(base: was, mine: ours, theirs: others)
                kept[id] = value
                if clash { clashes.append(id) }
            case let (was?, nil, others?):
                // I deleted it. If they changed it meanwhile, their change is kept.
                if others != was { kept[id] = others; clashes.append(id) }
            case let (was?, ours?, nil):
                // They deleted it. If I changed it meanwhile, mine is kept.
                if ours != was { kept[id] = ours; clashes.append(id) }
            case (_?, nil, nil):
                break
            case let (nil, ours?, _):
                // New here — and if both sides somehow made the same id, mine.
                kept[id] = ours
            case let (nil, nil, others?):
                kept[id] = others
            case (nil, nil, nil):
                break
            }
        }

        let order = mergedOrder(
            base: base.map(\.id),
            mine: mine.map(\.id),
            theirs: theirs.map(\.id),
            keep: Set(kept.keys)
        )
        // Sorted for determinism: sets iterate in a different order on every run.
        return (order.compactMap { kept[$0] }, clashes.sorted { $0.uuidString < $1.uuidString })
    }

    /// One clip both sides touched, merged field by field: words, captions, takes and timing are
    /// separate things, so changing different ones is not a collision.
    static func mergeSegment(base: Segment, mine: Segment, theirs: Segment) -> (Segment, Bool) {
        if mine == theirs { return (mine, false) }
        if mine == base { return (theirs, false) }
        if theirs == base { return (mine, false) }

        var merged = mine
        var clash = false
        func field<T: Equatable>(_ path: WritableKeyPath<Segment, T>) {
            let (value, collided) = pick(base: base[keyPath: path], mine: mine[keyPath: path], theirs: theirs[keyPath: path])
            merged[keyPath: path] = value
            if collided { clash = true }
        }
        field(\.role)
        field(\.title)
        field(\.script)
        field(\.estimatedDuration)
        field(\.teleprompter)
        field(\.selectedTakeID)
        field(\.playback)
        field(\.background)
        field(\.smartReframe)
        field(\.cleanup)
        field(\.metadata)

        let takes = mergeList(base: base.takes, mine: mine.takes, theirs: theirs.takes)
        merged.takes = takes.items
        let captions = mergeList(base: base.captions, mine: mine.captions, theirs: theirs.captions)
        merged.captions = captions.items
        if !takes.clashes.isEmpty || !captions.clashes.isEmpty { clash = true }

        // A chosen take that the merge took away falls back to one that is there.
        if let chosen = merged.selectedTakeID, !merged.takes.contains(where: { $0.id == chosen }) {
            merged.selectedTakeID = merged.takes.first?.id
        }
        return (merged, clash)
    }

    /// The order of a merged list. Whoever rearranged it decides the order; if both did, this
    /// side does. Things only the other side added go in after the thing they followed there.
    static func mergedOrder(base: [UUID], mine: [UUID], theirs: [UUID], keep: Set<UUID>) -> [UUID] {
        func common(_ list: [UUID], _ other: [UUID]) -> [UUID] {
            let shared = Set(other)
            return list.filter { shared.contains($0) }
        }
        let mineMoved = common(mine, base) != common(base, mine)
        let theirsMoved = common(theirs, base) != common(base, theirs)
        let (lead, follow) = (!mineMoved && theirsMoved) ? (theirs, mine) : (mine, theirs)

        var order = lead.filter { keep.contains($0) }
        var placed = Set(order)
        // Anything the leading side does not have: after its nearest predecessor in the list it
        // came from, or at the front when it had none.
        for list in [follow, base] {
            for (index, id) in list.enumerated() where keep.contains(id) && !placed.contains(id) {
                let before = list[..<index].last { placed.contains($0) }
                let at = before.flatMap { anchor in order.firstIndex(of: anchor).map { $0 + 1 } } ?? 0
                order.insert(id, at: at)
                placed.insert(id)
            }
        }
        return order
    }
}
