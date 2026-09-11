import Domain
import Testing
@testable import WorkflowEngine

private struct SegmentScriptHandler: WorkflowStepHandler {
    func canHandle(_ kind: WorkflowStepKind) -> Bool { kind == .segmentScript }

    func run(_ step: WorkflowStep, project: Project) async throws -> Project {
        var project = project
        project.title = "segmented"
        return project
    }
}

struct WorkflowRunnerTests {
    @Test func pausesForTheUserThenResumesAndSkipsUnsupportedSteps() async throws {
        let definition = WorkflowDefinition(name: "Test", steps: [
            WorkflowStep(kind: .segmentScript),
            WorkflowStep(kind: .record(RecordStepOptions())),
            WorkflowStep(kind: .unsupported(type: "fromTheFuture")),
        ])
        let runner = WorkflowRunner(handlers: [SegmentScriptHandler()])
        var project = Project(title: "draft", localeIdentifier: "en-US")

        var pausedState: WorkflowRunState?
        for try await event in runner.run(WorkflowRunState(definition: definition), project: project) {
            if case .needsUser(_, let state, let current) = event {
                pausedState = state
                project = current
            }
        }
        let state = try #require(pausedState)
        #expect(state.nextStepIndex == 1)
        #expect(project.title == "segmented")

        var skipped = 0
        var finished: Project?
        for try await event in runner.run(state.advanced(), project: project) {
            switch event {
            case .stepSkipped: skipped += 1
            case .finished(let result): finished = result
            default: break
            }
        }
        #expect(skipped == 1)
        #expect(finished?.title == "segmented")
    }

    @Test func missingHandlerFails() async {
        let definition = WorkflowDefinition(name: "Test", steps: [WorkflowStep(kind: .generateCaptions)])
        let runner = WorkflowRunner(handlers: [])

        await #expect(throws: WorkflowError.noHandler(stepType: "generateCaptions")) {
            for try await _ in runner.run(WorkflowRunState(definition: definition), project: Project(title: "t", localeIdentifier: "en-US")) {}
        }
    }
}
