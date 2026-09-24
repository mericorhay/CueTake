import Foundation

/// One workflow as the home screen lists it.
public struct HomeWorkflow: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// A short line under the name: how many steps, or what it does.
    public var meta: String?

    public init(id: UUID, name: String, meta: String?) {
        self.id = id
        self.name = name
        self.meta = meta
    }

    /// Two letters for the badge: the first letters of the first two words.
    public var initials: String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "WF" : letters
    }
}
