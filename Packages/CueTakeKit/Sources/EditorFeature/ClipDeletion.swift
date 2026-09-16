import Foundation

/// A clip that was just deleted, said once with a way back.
public struct ClipDeletion: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var title: String
    /// Texts, sounds, effects and videos that lay only over the deleted clip and went with it.
    public var alsoRemoved: Int
}
