import Foundation

/// An authored camera move stored in source time. A split, trim, speed change or reorder therefore
/// changes where the move is displayed, never which frames it belongs to.
public struct CameraMotionRecipe: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, CaseIterable, Hashable, Sendable, Codable {
        case pushIn
        case pullOut
        case punch
    }

    public enum Feel: String, CaseIterable, Hashable, Sendable, Codable {
        case calm
        case natural
        case energetic
    }

    public var id: UUID
    public var sourceRange: MediaTimeRange
    /// Added magnification: 0.15 means a move from 1x to 1.15x.
    public var amount: Double
    public var kind: Kind
    public var feel: Feel

    public init(
        id: UUID = UUID(),
        sourceRange: MediaTimeRange,
        amount: Double = 0.15,
        kind: Kind,
        feel: Feel = .natural
    ) {
        self.id = id
        self.sourceRange = sourceRange
        self.amount = min(max(amount.isFinite ? amount : 0.15, 0.02), 1)
        self.kind = kind
        self.feel = feel
    }

    public var start: Double { sourceRange.start.seconds }
    public var end: Double { sourceRange.end.seconds }
}

/// Pure and deterministic so preview, export and the timeline thumbnail all show the same move.
public enum CameraMotionEvaluator {
    public static func zoom(at sourceTime: Double, recipes: [CameraMotionRecipe]) -> Double {
        guard let recipe = recipes.last(where: {
            sourceTime >= $0.start - 0.0001 && sourceTime <= $0.end + 0.0001
        }) else { return 1 }
        let length = max(0.001, recipe.sourceRange.duration.seconds)
        let progress = min(max((sourceTime - recipe.start) / length, 0), 1)
        let amount = min(max(recipe.amount, 0.02), 1)

        switch recipe.kind {
        case .pushIn:
            return 1 + amount * curve(progress, feel: recipe.feel)
        case .pullOut:
            return 1 + amount * (1 - curve(progress, feel: recipe.feel))
        case .punch:
            let envelope: Double
            if progress < 0.22 {
                envelope = curve(progress / 0.22, feel: recipe.feel)
            } else if progress <= 0.72 {
                envelope = 1
            } else {
                envelope = 1 - curve((progress - 0.72) / 0.28, feel: recipe.feel)
            }
            return 1 + amount * envelope
        }
    }

    /// Sample points that keep AVFoundation's linear ramps visually close to the authored curve.
    public static func sampleTimes(for recipe: CameraMotionRecipe) -> [Double] {
        let count = recipe.kind == .punch ? 12 : 8
        return (0...count).map {
            recipe.start + recipe.sourceRange.duration.seconds * Double($0) / Double(count)
        }
    }

    private static func curve(_ value: Double, feel: CameraMotionRecipe.Feel) -> Double {
        let t = min(max(value, 0), 1)
        switch feel {
        case .calm:
            // Smootherstep: zero velocity and acceleration at both ends.
            return t * t * t * (t * (t * 6 - 15) + 10)
        case .natural:
            return t * t * (3 - 2 * t)
        case .energetic:
            // Fast commitment without an artificial overshoot.
            return 1 - pow(1 - t, 3)
        }
    }
}
