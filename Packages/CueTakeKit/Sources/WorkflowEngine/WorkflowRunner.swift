import Domain
import Foundation

/// Where a run is. Codable so a half-finished workflow survives the app being closed
/// (e.g. the user stops at the recording step and comes back tomorrow).
public struct WorkflowRunState: Hashable, Sendable, Codable {
    public var definition: WorkflowDefinition
    public var nextStepIndex: Int
    /// Zero-based element inside the current `forEach`. Persisting it prevents a recovered job
    /// from repeating elements that already completed.
    public var iterationIndex: Int
    public var variables: [String: WorkflowValue]

    public init(
        definition: WorkflowDefinition,
        nextStepIndex: Int = 0,
        iterationIndex: Int = 0,
        variables: [String: WorkflowValue]? = nil
    ) {
        self.definition = definition
        self.nextStepIndex = nextStepIndex
        self.iterationIndex = iterationIndex
        self.variables = variables ?? definition.variables
    }

    public var nextStep: WorkflowStep? {
        definition.steps.indices.contains(nextStepIndex) ? definition.steps[nextStepIndex] : nil
    }

    public var isFinished: Bool { nextStep == nil }

    /// Call after the UI completes a step that `requiresUser`.
    public func advanced() -> WorkflowRunState {
        WorkflowRunState(
            definition: definition,
            nextStepIndex: nextStepIndex + 1,
            variables: variables
        )
    }

    public func advancedIteration() -> WorkflowRunState {
        WorkflowRunState(
            definition: definition,
            nextStepIndex: nextStepIndex,
            iterationIndex: iterationIndex + 1,
            variables: variables
        )
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
    case conditionFalse
    case emptyLoop
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

/// Rich context for handlers registered by the v3 engine. Old handlers continue to work through
/// `WorkflowStepHandler`; a new tool can opt in when it needs variables or the current loop item.
public struct WorkflowExecutionContext: Hashable, Sendable {
    public var variables: [String: WorkflowValue]
    public var iterationIndex: Int?

    public init(variables: [String: WorkflowValue], iterationIndex: Int? = nil) {
        self.variables = variables
        self.iterationIndex = iterationIndex
    }
}

public protocol ContextualWorkflowStepHandler: WorkflowStepHandler {
    func run(_ step: WorkflowStep, project: Project, context: WorkflowExecutionContext) async throws -> Project
}

public extension ContextualWorkflowStepHandler {
    func run(_ step: WorkflowStep, project: Project) async throws -> Project {
        try await run(step, project: project, context: WorkflowExecutionContext(variables: [:]))
    }
}

/// One resolution point for all executable tools. Registration order no longer leaks into normal
/// dispatch, and duplicate type registrations are rejected at construction time.
public struct WorkflowStepRegistry: Sendable {
    public enum RegistryError: Error, Hashable, Sendable { case duplicate(String) }

    public struct Registration: Sendable {
        public var type: String
        public var handler: any WorkflowStepHandler

        public init(type: String, handler: any WorkflowStepHandler) {
            self.type = type
            self.handler = handler
        }
    }

    private var handlers: [String: any WorkflowStepHandler]
    private var legacyHandlers: [any WorkflowStepHandler]

    public init(registrations: [Registration]) throws {
        var handlers: [String: any WorkflowStepHandler] = [:]
        for registration in registrations {
            guard handlers[registration.type] == nil else { throw RegistryError.duplicate(registration.type) }
            handlers[registration.type] = registration.handler
        }
        self.handlers = handlers
        legacyHandlers = []
    }

    /// Compatibility bridge while feature-owned handlers move to explicit registrations.
    public init(legacyHandlers: [any WorkflowStepHandler]) {
        handlers = [:]
        self.legacyHandlers = legacyHandlers
    }

    public func handler(for kind: WorkflowStepKind) -> (any WorkflowStepHandler)? {
        handlers[kind.typeName] ?? legacyHandlers.first { $0.canHandle(kind) }
    }

    public var registeredTypes: [String] { handlers.keys.sorted() }
}

public struct WorkflowToolDescriptor: Hashable, Sendable {
    public var type: String
    public var requiresUser: Bool

    public init(type: String, requiresUser: Bool) {
        self.type = type
        self.requiresUser = requiresUser
    }
}

public enum WorkflowToolRegistry {
    public static let builtIns: [WorkflowToolDescriptor] = WorkflowStepKind.knownTypes.map { type in
        let kind = WorkflowStepKind.make(type: type)
        return WorkflowToolDescriptor(type: type, requiresUser: kind.requiresUser)
    }
}

public struct WorkflowRunner: Sendable {
    public var registry: WorkflowStepRegistry

    public init(handlers: [any WorkflowStepHandler]) {
        registry = WorkflowStepRegistry(legacyHandlers: handlers)
    }

    public init(registry: WorkflowStepRegistry) {
        self.registry = registry
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
            } else if let condition = step.when, !condition.evaluate(in: state.variables) {
                continuation.yield(.stepSkipped(step, reason: .conditionFalse))
            } else if step.kind.requiresUser {
                continuation.yield(.needsUser(step, state: state, project: project))
                return
            } else {
                guard let handler = registry.handler(for: step.kind) else {
                    throw WorkflowError.noHandler(stepType: step.kind.typeName)
                }

                let items: [WorkflowValue?]
                if let loop = step.forEach {
                    let values = state.variables[loop.source]?.arrayValue ?? []
                    guard !values.isEmpty else {
                        continuation.yield(.stepSkipped(step, reason: .emptyLoop))
                        state = state.advanced()
                        continue
                    }
                    items = values.map(Optional.some)
                } else {
                    items = [nil]
                }

                let resumeIndex = min(state.iterationIndex, items.count)
                for index in resumeIndex..<items.count {
                    var variables = state.variables
                    if let loop = step.forEach, let item = items[index] {
                        variables[loop.itemVariable] = item
                    }
                    let context = WorkflowExecutionContext(
                        variables: variables,
                        iterationIndex: step.forEach == nil ? nil : index
                    )
                    continuation.yield(.stepStarted(step))
                    if let contextual = handler as? any ContextualWorkflowStepHandler {
                        project = try await contextual.run(step, project: project, context: context)
                    } else {
                        project = try await handler.run(step, project: project)
                    }
                    continuation.yield(.stepCompleted(step, project))
                    state = state.advancedIteration()
                }
            }
            state = state.advanced()
        }

        continuation.yield(.finished(project))
    }
}
