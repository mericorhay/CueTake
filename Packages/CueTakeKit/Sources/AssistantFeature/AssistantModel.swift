import Domain
import Foundation
import Observation

/// A place in the app the assistant can send someone.
///
/// The assistant ends a reply with tokens like `[[go:editor]]`, and they become buttons. It is how
/// "where do I do that?" gets answered with the one thing better than directions: the door.
public enum AssistantDestination: String, CaseIterable, Hashable, Sendable {
    case create, `import`, editor, captions, export, projects, workflows, settings, studio

    var symbol: String {
        switch self {
        case .create: "plus.circle"
        case .import: "square.and.arrow.down"
        case .editor: "timeline.selection"
        case .captions: "captions.bubble"
        case .export: "square.and.arrow.up"
        case .projects: "square.grid.2x2"
        case .workflows: "flowchart"
        case .settings: "gearshape"
        case .studio: "camera"
        }
    }

    var titleKey: String.LocalizationValue {
        switch self {
        case .create: "assistant.go.create"
        case .import: "assistant.go.import"
        case .editor: "assistant.go.editor"
        case .captions: "assistant.go.captions"
        case .export: "assistant.go.export"
        case .projects: "assistant.go.projects"
        case .workflows: "assistant.go.workflows"
        case .settings: "assistant.go.settings"
        case .studio: "assistant.go.studio"
        }
    }

    /// Splits a reply into what to read and where to go. Unknown tokens are dropped rather than
    /// shown, so a model that invents one produces no broken button and no stray brackets.
    static func parse(_ reply: String) -> (text: String, destinations: [AssistantDestination]) {
        var destinations: [AssistantDestination] = []
        var text = reply
        let pattern = /\[\[go:([a-z]+)\]\]/
        for match in reply.matches(of: pattern) {
            if let destination = AssistantDestination(rawValue: String(match.output.1)),
               !destinations.contains(destination) {
                destinations.append(destination)
            }
        }
        text = text.replacing(pattern, with: "")
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), Array(destinations.prefix(2)))
    }
}

/// The assistant: its sessions, the one being read, and the message being written.
///
/// It does not know how to reach a model. Whoever owns it provides `send`, `save` and `delete`,
/// the same way every other feature in this app is handed its capabilities rather than finding
/// them — which is also what keeps the network, the prompt and the key out of the UI layer.
@MainActor
@Observable
public final class AssistantModel {
    public private(set) var sessions: [AssistantSession] = []
    public private(set) var currentID: AssistantSession.ID?
    public var draft = ""
    public private(set) var isSending = false
    public private(set) var failure: String?
    public var showsSessions = false
    /// Whether the build can reach the assistant at all.
    public var isConnected: Bool

    /// Sends the session and returns the reply text.
    @ObservationIgnored public var send: ((AssistantSession) async throws -> String)?
    @ObservationIgnored public var save: ((AssistantSession) -> Void)?
    @ObservationIgnored public var delete: ((AssistantSession.ID) -> Void)?
    @ObservationIgnored public var deleteAll: (() -> Void)?
    /// Where the user is right now, in a line or two, attached to each message they send.
    @ObservationIgnored public var context: (() -> String)?
    @ObservationIgnored public var onDestination: ((AssistantDestination) -> Void)?
    /// Turns a failure into a sentence. The app knows which failures are "not connected" and
    /// which are "offline"; the model only knows something went wrong.
    @ObservationIgnored public var describeFailure: ((any Error) -> String)?

    public init(isConnected: Bool) {
        self.isConnected = isConnected
    }

    public var current: AssistantSession? {
        currentID.flatMap { id in sessions.first { $0.id == id } }
    }

    public var messages: [AssistantMessage] {
        current?.messages ?? []
    }

    public func load(_ stored: [AssistantSession]) {
        sessions = stored
        if let currentID, !stored.contains(where: { $0.id == currentID }) {
            self.currentID = nil
        }
    }

    // MARK: - Sessions

    /// A new conversation. Not written to disk until something is said in it: a list full of
    /// empty sessions from every time someone opened the sheet is litter.
    public func newSession() {
        currentID = nil
        draft = ""
        failure = nil
        showsSessions = false
    }

    public func open(_ id: AssistantSession.ID) {
        currentID = id
        failure = nil
        showsSessions = false
    }

    public func remove(_ id: AssistantSession.ID) {
        sessions.removeAll { $0.id == id }
        if currentID == id { currentID = nil }
        delete?(id)
    }

    public func removeAll() {
        sessions.removeAll()
        currentID = nil
        deleteAll?()
    }

    // MARK: - Sending

    /// Starts a conversation with something already typed — what the journey map's "ask" field
    /// hands over.
    public func ask(_ text: String) {
        newSession()
        draft = text
        Task { await submit() }
    }

    public func submit() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        var session = current ?? AssistantSession(title: AssistantSession.title(from: text))
        session.messages.append(
            AssistantMessage(role: .user, text: text, context: context?())
        )
        session.updatedAt = .now
        store(session)
        draft = ""

        await request(session)
    }

    /// Sends the conversation again after a failure, without adding anything to it.
    public func retry() async {
        guard let session = current, session.messages.last?.role == .user else { return }
        await request(session)
    }

    private func request(_ outgoing: AssistantSession) async {
        guard let send else { return }
        isSending = true
        failure = nil

        do {
            let reply = try await send(outgoing)
            guard var session = sessions.first(where: { $0.id == outgoing.id }) else {
                isSending = false
                return
            }
            session.messages.append(AssistantMessage(role: .assistant, text: reply))
            session.updatedAt = .now
            store(session)
        } catch {
            failure = describeFailure?(error)
                ?? String(localized: "assistant.error.generic", bundle: .module)
        }
        isSending = false
    }

    private func store(_ session: AssistantSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
        currentID = session.id
        save?(session)
    }

    public func setFailure(_ message: String?) {
        failure = message
    }
}
