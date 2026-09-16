import Foundation

/// The AI's memory of a project: what was asked and what it did, one session at a time.
///
/// Kept with the project so the AI picks up where it left off tomorrow, and outside undo so taking
/// back an edit does not make the AI forget it was asked. A new session is a clean slate; older
/// sessions stay readable.
public struct AIConversation: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var startedAt: Date
    public var turns: [AITurn]

    public init(id: UUID = UUID(), startedAt: Date = .now, turns: [AITurn] = []) {
        self.id = id
        self.startedAt = startedAt
        self.turns = turns
    }
}

public struct AITurn: Hashable, Sendable, Codable {
    public var instruction: String
    public var summary: String
    /// One line per change made, as the changes list shows them.
    public var changes: [String]
    public var at: Date

    public init(instruction: String, summary: String, changes: [String], at: Date = .now) {
        self.instruction = instruction
        self.summary = summary
        self.changes = changes
        self.at = at
    }
}

extension Project {
    /// The session the AI is in; nil before the first request.
    public var currentAIConversation: AIConversation? { aiConversations.last }

    /// Adds a turn to the current session, starting one when there is none.
    public mutating func remember(_ turn: AITurn) {
        if aiConversations.isEmpty { aiConversations.append(AIConversation()) }
        aiConversations[aiConversations.count - 1].turns.append(turn)
        // Enough to be useful, bounded so a project file does not grow forever.
        if aiConversations[aiConversations.count - 1].turns.count > 40 {
            aiConversations[aiConversations.count - 1].turns.removeFirst()
        }
        if aiConversations.count > 20 { aiConversations.removeFirst() }
    }

    /// Starts a clean session. An empty current session is reused rather than stacked.
    public mutating func startAIConversation() {
        if let last = aiConversations.last, last.turns.isEmpty { return }
        aiConversations.append(AIConversation())
    }
}

extension EditDocument {
    /// An earlier request in this session, as the model reads it.
    public struct Turn: Codable, Sendable, Equatable {
        public var asked: String
        public var did: String
        public var changes: [String]?
    }

    /// The last requests of the current session, newest last, trimmed to stay small.
    static func history(of project: Project) -> [Turn]? {
        guard let turns = project.currentAIConversation?.turns, !turns.isEmpty else { return nil }
        return turns.suffix(8).map { turn in
            Turn(
                asked: String(turn.instruction.prefix(300)),
                did: String(turn.summary.prefix(300)),
                changes: turn.changes.isEmpty ? nil : Array(turn.changes.prefix(12)).map { String($0.prefix(80)) }
            )
        }
    }
}
