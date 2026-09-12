import Domain
import Foundation

/// Where a run is. Codable so a half-finished workflow survives the app being closed
/// (e.g. the user stops at the recording step and comes back tomorrow).
public struct WorkflowRunState: Hashable, Sendable, Codable {
    public var definition: WorkflowDefinition
    public var nextStepIndex: Int

    public init(definition: WorkflowDefinition, nextStepIndex: Int = 0) {
        self.definition = definition
        self.nextStepIndex = nextStepIndex
    }

    public var nextStep: WorkflowStep? {
        definition.steps.indices.contains(nextStepIndex) ? definition.steps[nextStepIndex] : nil
    }

    public var isFinished: Bool { nextStep == nil }

    /// Call after the UI completes a step that `requiresUser`.
    public func advanced() -> WorkflowRunState {
        WorkflowRunState(definition: definition, nextStepIndex: nextStepIndex + 1)
    }
}

public enum WorkflowRunEvent: Sendable {
    case stepStarted(WorkflowStep)
    case stepCompleted(WorkflowStep, Project)
    case stepSkipped(WorkflowStep, reason: WorkflowSkipReason)
    /// The run stops here. Resume with `state.advanced()` once the UI finished the step.
    case needsUser(WorkflowStep, state: WorkflowRunState, project: Project)
    case finished(Project)
}

public enum WorkflowSkipReason: Hashable, Sendable {
    case disabled
    case unsupported
}

public enum WorkflowError: Error, Hashable, Sendable {
    case noHandler(stepType: String)
}

/// Executes one kind of step. The app registers handlers that call AI, speech and media engines,
/// which keeps WorkflowEngine independent of every capability module.
public protocol WorkflowStepHandler: Sendable {
    func canHandle(_ kind: WorkflowStepKind) -> Bool
    func run(_ step: WorkflowStep, project: Project) async throws -> Project
}

public struct WorkflowRunner: Sendable {
    public var handlers: [any WorkflowStepHandler]

    public init(handlers: [any WorkflowStepHandler]) {
        self.handlers = handlers
    }

    /// Runs steps in order until the workflow finishes or a step needs the user.
    /// Cancelling iteration cancels the run.
    public func run(_ state: WorkflowRunState, project: Project) -> AsyncThrowingStream<WorkflowRunEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: WorkflowRunEvent.self)
        let task = Task {
            do {
                try await execute(state, project: project, continuation: continuation)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func execute(
        _ initialState: WorkflowRunState,
        project initialProject: Project,
        continuation: AsyncThrowingStream<WorkflowRunEvent, any Error>.Continuation
    ) async throws {
        var state = initialState
        var project = initialProject

        while let step = state.nextStep {
            try Task.checkCancellation()

            if !step.isEnabled {
                continuation.yield(.stepSkipped(step, reason: .disabled))
            } else if case .unsupported = step.kind {
                continuation.yield(.stepSkipped(step, reason: .unsupported))
            } else if step.kind.requiresUser {
                continuation.yield(.needsUser(step, state: state, project: project))
                return
            } else {
                guard let handler = handlers.first(where: { $0.canHandle(step.kind) }) else {
                    throw WorkflowError.noHandler(stepType: step.kind.typeName)
                }
                continuation.yield(.stepStarted(step))
                project = try await handler.run(step, project: project)
                continuation.yield(.stepCompleted(step, project))
            }
            state = state.advanced()
        }

        continuation.yield(.finished(project))
    }
}
