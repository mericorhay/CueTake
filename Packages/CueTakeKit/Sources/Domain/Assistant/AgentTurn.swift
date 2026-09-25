import Foundation

/// The AI editor working in rounds: it asks to look at the video or to make changes, the app does
/// it and answers, and it goes on until it says it is finished.
///
/// The app carries out every tool on the real editor and keeps the conversation; the server only
/// holds the model's key and prompt, and sees the conversation again on every round. Nothing here
/// is the provider's format: the server translates, so the model behind it can change.
public struct AgentRequest: Codable, Sendable {
    public var instruction: String
    /// The video as it was when the request was made. Later versions come back in tool results.
    public var document: EditDocument
    /// The whole video in one picture, when there is footage to show.
    public var sheet: AgentImage?
    /// Everything after the opening: the model's calls and the app's answers, in order.
    public var turns: [AgentTurn]

    public init(instruction: String, document: EditDocument, sheet: AgentImage?, turns: [AgentTurn]) {
        self.instruction = instruction
        self.document = document
        self.sheet = sheet
        self.turns = turns
    }
}

/// One picture of the finished video: base64 JPEG and what it shows.
public struct AgentImage: Codable, Sendable, Equatable {
    public var jpeg: String
    /// Seconds of the finished video it shows, one for each tile of a sheet.
    public var at: [Double]

    public init(jpeg: String, at: [Double]) {
        self.jpeg = jpeg
        self.at = at
    }
}

public struct AgentTurn: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable {
        /// The model: what it said and the tools it called.
        case assistant
        /// The app: what each call did.
        case tool
    }

    public var role: Role
    public var text: String?
    public var calls: [AgentCall]?
    public var results: [AgentResult]?
    /// Pictures that came with the results, in the order the results mention them.
    public var images: [AgentImage]?

    public static func assistant(_ text: String?, calls: [AgentCall]) -> AgentTurn {
        AgentTurn(role: .assistant, text: text, calls: calls)
    }

    public static func tool(_ results: [AgentResult], images: [AgentImage]) -> AgentTurn {
        AgentTurn(role: .tool, results: results, images: images.isEmpty ? nil : images)
    }
}

/// A tool the model asked for. `input` is its arguments as the model wrote them, JSON text.
public struct AgentCall: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var input: String

    public init(id: String, name: String, input: String) {
        self.id = id
        self.name = name
        self.input = input
    }
}

public struct AgentResult: Codable, Sendable, Equatable {
    /// The call it answers.
    public var id: String
    public var text: String
    /// The video after the call, when it changed it. Only the latest one is kept in the
    /// conversation; older ones are dropped to keep each round small.
    public var document: EditDocument?

    public init(id: String, text: String, document: EditDocument? = nil) {
        self.id = id
        self.text = text
        self.document = document
    }
}

/// The model's answer to one round.
public struct AgentReply: Codable, Sendable, Equatable {
    public var text: String?
    public var calls: [AgentCall]
    public var model: String?

    public init(text: String?, calls: [AgentCall], model: String? = nil) {
        self.text = text
        self.calls = calls
        self.model = model
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        calls = (try? c.decodeIfPresent([AgentCall].self, forKey: .calls)) ?? []
        model = try? c.decodeIfPresent(String.self, forKey: .model)
    }
}
