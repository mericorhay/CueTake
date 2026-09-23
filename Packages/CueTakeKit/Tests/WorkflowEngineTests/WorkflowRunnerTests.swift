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

private actor ContextRecorder {
    private(set) var values: [WorkflowValue] = []
    func append(_ value: WorkflowValue) { values.append(value) }
}

private struct ContextHandler: ContextualWorkflowStepHandler {
    let recorder: ContextRecorder
    func canHandle(_ kind: WorkflowStepKind) -> Bool { kind == .segmentScript }
    func run(_ step: WorkflowStep, project: Project, context: WorkflowExecutionContext) async throws -> Project {
        if let value = context.variables["clip"] { await recorder.append(value) }
        return project
    }
}

struct WorkflowRunnerTests {
    @Test func schemaTwoDocumentsMigrateWithoutLosingTheirLinearSteps() throws {
        let json = """
        {"schemaVersion":2,"name":"Old","steps":[{"type":"segmentScript"}]}
        """
        let workflow = try WorkflowDefinition.decode(json: json)
        #expect(workflow.schemaVersion == WorkflowDefinition.currentSchemaVersion)
        #expect(workflow.variables.isEmpty)
        #expect(workflow.steps.first?.kind == .segmentScript)
    }

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

    @Test func conditionsAndForEachAreDeterministicAndResumable() async throws {
        let recorder = ContextRecorder()
        let repeated = WorkflowStep(
            kind: .segmentScript,
            when: WorkflowCondition(variable: "enabled"),
            forEach: WorkflowForEach(source: "clips", itemVariable: "clip")
        )
        let skipped = WorkflowStep(
            kind: .segmentScript,
            when: WorkflowCondition(variable: "missing")
        )
        let definition = WorkflowDefinition(
            name: "Graph",
            variables: [
                "enabled": .bool(true),
                "clips": .array([.string("a"), .string("b"), .string("c")]),
            ],
            steps: [repeated, skipped]
        )
        let registry = try WorkflowStepRegistry(registrations: [
            .init(type: "segmentScript", handler: ContextHandler(recorder: recorder)),
            .init(type: "export", handler: ExportHandler()),
        ])
        let runner = WorkflowRunner(registry: registry)
        var completed = 0
        var conditionSkips = 0

        for try await event in runner.run(
            WorkflowRunState(definition: definition, iterationIndex: 1),
            project: Project(title: "t", localeIdentifier: "en-US")
        ) {
            switch event {
            case .stepCompleted: completed += 1
            case .stepSkipped(_, .conditionFalse): conditionSkips += 1
            default: break
            }
        }

        #expect(completed == 3) // loop elements b/c, then the mandatory export
        #expect(conditionSkips == 1)
        let recorded = await recorder.values
        #expect(recorded == [.string("b"), .string("c")])
    }

    @Test func registryRejectsDuplicateToolTypes() {
        #expect(throws: WorkflowStepRegistry.RegistryError.duplicate("export")) {
            _ = try WorkflowStepRegistry(registrations: [
                .init(type: "export", handler: ExportHandler()),
                .init(type: "export", handler: ExportHandler()),
            ])
        }
    }
}

struct WorkflowJobQueueTests {
    @Test func persistsCheckpointAndRecoversAnInterruptedRun() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "workflow-jobs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let definition = WorkflowDefinition(name: "Durable", steps: [WorkflowStep(kind: .segmentScript)])
        let projectID = UUID()
        let queue = try WorkflowJobQueue(root: folder)
        let enqueued = try await queue.enqueue(workflow: definition, projectID: projectID)
        _ = try await queue.start(enqueued.id)
        let checkpoint = WorkflowRunState(definition: definition, nextStepIndex: 1)
        _ = try await queue.checkpoint(enqueued.id, state: checkpoint, kind: .stepCompleted, step: definition.steps[0])

        // A fresh actor simulates a new app process reading the same directory.
        let relaunched = try WorkflowJobQueue(root: folder)
        let recovered = try await relaunched.recoverInterrupted()
        let job = try #require(recovered.first)
        #expect(job.status == .queued)
        #expect(job.state.nextStepIndex == 1)
        #expect(job.journal.contains { $0.kind == .recovered })
    }

    @Test func failuresRetryOnlyUpToTheConfiguredLimit() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "workflow-retry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let definition = WorkflowDefinition(name: "Retry", steps: [])
        let queue = try WorkflowJobQueue(root: folder)
        let job = try await queue.enqueue(workflow: definition, projectID: UUID(), maxAttempts: 2)
        let first = try await queue.start(job.id)
        let scheduled = try await queue.fail(job.id, state: first.state, error: "offline")
        #expect(scheduled.status == .queued)
        let second = try await queue.start(job.id)
        let failed = try await queue.fail(job.id, state: second.state, error: "offline")
        #expect(failed.status == .failed)
        #expect(failed.attempt == 2)
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
