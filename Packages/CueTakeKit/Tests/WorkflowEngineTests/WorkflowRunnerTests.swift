import Foundation
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

/// Every workflow ends with an export; the tests pass it through.
private struct ExportHandler: WorkflowStepHandler {
    func canHandle(_ kind: WorkflowStepKind) -> Bool { kind.isFinalExport }
    func run(_ step: WorkflowStep, project: Project) async throws -> Project { project }
}

struct WorkflowRunnerTests {
    @Test func pausesForTheUserThenResumesAndSkipsUnsupportedSteps() async throws {
        let definition = WorkflowDefinition(name: "Test", steps: [
            WorkflowStep(kind: .segmentScript),
            WorkflowStep(kind: .record(RecordStepOptions())),
            WorkflowStep(kind: .unsupported(type: "fromTheFuture")),
        ])
        let runner = WorkflowRunner(handlers: [SegmentScriptHandler(), ExportHandler()])
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

struct WorkflowDeliveryBodyTests {
    @Test func multipartCarriesFieldsAndTheWholeFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "delivery-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appending(path: "clip.mov")
        let bytes = Data((0..<3_000_000).map { UInt8($0 % 251) })
        try bytes.write(to: video)
        let body = folder.appending(path: "body")

        try WorkflowDeliveryClient.writeMultipart(
            to: body,
            boundary: "B",
            fields: [("title", "Merhaba \"dünya\"")],
            fileField: "video",
            file: video,
            fileName: "clip.mov"
        )
        let written = try Data(contentsOf: body)
        let text = String(decoding: written.prefix(200), as: UTF8.self)
        #expect(text.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nMerhaba"))
        #expect(written.count > bytes.count)
        #expect(String(decoding: written.suffix(9), as: UTF8.self) == "\r\n--B--\r\n")
        #expect(written.range(of: bytes) != nil)
    }
}
