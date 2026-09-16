import Foundation
import Testing
@testable import Domain
@testable import EditorFeature

@MainActor
struct AIMemoryTests {
    private func model() -> EditorModel {
        EditorModel(project: Project(title: "t", localeIdentifier: "en", segments: [Segment(role: .hook, script: "hi")]))
    }

    @Test func theAIRemembersTheSessionAndUndoDoesNotErase() throws {
        let model = model()
        model.record("editor.change.ai", symbol: "sparkles")
        model.project.title = "Changed"
        model.project.remember(AITurn(instruction: "Make it punchy", summary: "Tightened pauses", changes: ["Cut 3 pauses"]))

        let document = model.document()
        #expect(document.history?.count == 1)
        #expect(document.history?.first?.asked == "Make it punchy")
        #expect(document.history?.first?.changes == ["Cut 3 pauses"])

        model.undo()
        #expect(model.project.title == "t")
        #expect(model.aiSessionTurns.count == 1)

        model.startNewAISession()
        #expect(model.aiSessionNumber == 2)
        #expect(model.aiSessionTurns.isEmpty)
        #expect(model.document().history == nil)
        // An empty session is reused, not stacked.
        model.startNewAISession()
        #expect(model.project.aiConversations.count == 2)
    }

    @Test func memoryIsSavedWithTheProject() throws {
        var project = Project(title: "t", localeIdentifier: "en")
        project.remember(AITurn(instruction: "a", summary: "b", changes: []))
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(decoded.aiConversations.first?.turns.first?.instruction == "a")

        // Projects from before memory still open.
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Project(title: "old", localeIdentifier: "en"))) as? [String: Any])
        json.removeValue(forKey: "aiConversations")
        let old = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.aiConversations.isEmpty)
    }
}
