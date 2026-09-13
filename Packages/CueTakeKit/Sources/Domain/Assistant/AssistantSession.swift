import Foundation

/// One conversation with the assistant.
///
/// Sessions are the whole memory model, on purpose. There is no profile the assistant builds up
/// about the user and no cross-conversation recall: what it knows is what is in this session,
/// which is also exactly what the user can see, scroll back through, and delete.
public struct AssistantSession: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var title: String
    public var messages: [AssistantMessage]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String = "", messages: [AssistantMessage] = [], createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// What the list shows under the title: the last thing said, by either side.
    public var preview: String {
        messages.last?.text ?? ""
    }

    /// A title from the first thing the user asked, the way a person would label the conversation
    /// if they bothered: the first few words, not a timestamp.
    public static func title(from text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).prefix(6)
        let joined = words.joined(separator: " ")
        return words.count < text.split(whereSeparator: \.isWhitespace).count ? joined + "…" : joined
    }
}

public struct AssistantMessage: Identifiable, Hashable, Sendable, Codable {
    public enum Role: String, Hashable, Sendable, Codable {
        case user
        case assistant
    }

    public let id: UUID
    public var role: Role
    /// What the user typed, or what the assistant answered. Exactly what is drawn.
    public var text: String
    /// Where the user was when they asked — screen and project, in a line or two. Sent with the
    /// message and kept with it, so that replaying the conversation sends the same bytes every
    /// time: the history is append-only, and a context that was re-read on every request would
    /// make every earlier turn different from what the model actually saw.
    public var context: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        context: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.context = context
        self.createdAt = createdAt
    }
}
