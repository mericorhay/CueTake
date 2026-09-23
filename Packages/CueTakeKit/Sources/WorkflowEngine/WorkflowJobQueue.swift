import Domain
import Foundation

public enum WorkflowJobStatus: String, Hashable, Sendable, Codable {
    case queued
    case running
    case waitingForUser
    case paused
    case succeeded
    case failed
    case cancelled

    public var isResumable: Bool {
        switch self {
        case .queued, .waitingForUser, .paused: true
        case .running, .succeeded, .failed, .cancelled: false
        }
    }
}

public struct WorkflowRunJournalEntry: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case enqueued, started, stepStarted, stepCompleted, stepSkipped
        case waitingForUser, checkpoint, recovered, retryScheduled, paused, failed, completed, cancelled
    }

    public let id: UUID
    public var sequence: Int
    public var date: Date
    public var kind: Kind
    public var stepID: WorkflowStep.ID?
    public var stepType: String?
    public var stepIndex: Int
    public var iterationIndex: Int?
    public var message: String?

    public init(
        id: UUID = UUID(),
        sequence: Int = 0,
        date: Date = .now,
        kind: Kind,
        stepID: WorkflowStep.ID? = nil,
        stepType: String? = nil,
        stepIndex: Int,
        iterationIndex: Int? = nil,
        message: String? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.date = date
        self.kind = kind
        self.stepID = stepID
        self.stepType = stepType
        self.stepIndex = stepIndex
        self.iterationIndex = iterationIndex
        self.message = message
    }
}

/// A durable pointer into a workflow. Project media stays in ProjectStore; the queue stores only
/// its id and the immutable workflow snapshot, so a queue file can never duplicate gigabytes of
/// footage.
public struct WorkflowJob: Identifiable, Hashable, Sendable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public let id: UUID
    public var projectID: Project.ID
    public var workflowID: WorkflowDefinition.ID
    public var state: WorkflowRunState
    public var status: WorkflowJobStatus
    public var attempt: Int
    public var maxAttempts: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var lastError: String?
    public var journal: [WorkflowRunJournalEntry]

    public init(
        id: UUID = UUID(),
        projectID: Project.ID,
        state: WorkflowRunState,
        maxAttempts: Int = 3,
        createdAt: Date = .now
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.projectID = projectID
        workflowID = state.definition.id
        self.state = state
        status = .queued
        attempt = 0
        self.maxAttempts = max(1, maxAttempts)
        self.createdAt = createdAt
        updatedAt = createdAt
        lastError = nil
        journal = []
        append(.enqueued)
    }

    public var progress: Double {
        let count = state.definition.steps.count
        guard count > 0 else { return 1 }
        return min(1, max(0, Double(state.nextStepIndex) / Double(count)))
    }

    mutating func append(
        _ kind: WorkflowRunJournalEntry.Kind,
        step: WorkflowStep? = nil,
        message: String? = nil
    ) {
        journal.append(WorkflowRunJournalEntry(
            sequence: journal.count,
            kind: kind,
            stepID: step?.id,
            stepType: step?.kind.typeName,
            stepIndex: state.nextStepIndex,
            iterationIndex: state.iterationIndex == 0 ? nil : state.iterationIndex,
            message: message
        ))
        updatedAt = .now
    }
}

public enum WorkflowJobQueueError: Error, Hashable, Sendable {
    case notFound(UUID)
    case notRunnable(UUID)
}

/// File-backed, actor-isolated queue. Every transition is written atomically before returning, so
/// the UI can safely show a state that is already recoverable after a crash or process eviction.
public actor WorkflowJobQueue {
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public static func inApplicationSupport(fileManager: FileManager = .default) throws -> WorkflowJobQueue {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try WorkflowJobQueue(root: base.appending(path: "WorkflowJobs", directoryHint: .isDirectory))
    }

    public func enqueue(
        workflow: WorkflowDefinition,
        projectID: Project.ID,
        variables: [String: WorkflowValue] = [:],
        maxAttempts: Int = 3
    ) throws -> WorkflowJob {
        var merged = workflow.variables
        merged.merge(variables) { _, runtime in runtime }
        let job = WorkflowJob(
            projectID: projectID,
            state: WorkflowRunState(definition: workflow, variables: merged),
            maxAttempts: maxAttempts
        )
        try write(job)
        try? pruneFinished(keeping: 100)
        return job
    }

    public func all() -> [WorkflowJob] {
        files().compactMap(read).sorted { $0.updatedAt > $1.updatedAt }
    }

    public func job(id: WorkflowJob.ID) -> WorkflowJob? { read(url(for: id)) }

    public func resumable(workflowID: WorkflowDefinition.ID, projectID: Project.ID) -> WorkflowJob? {
        all().first { $0.workflowID == workflowID && $0.projectID == projectID && $0.status.isResumable }
    }

    /// Running means the previous process disappeared before writing a terminal state. Put those
    /// jobs back in the queue at their last durable checkpoint.
    @discardableResult
    public func recoverInterrupted() throws -> [WorkflowJob] {
        var recovered: [WorkflowJob] = []
        for file in files() {
            guard var job = read(file), job.status == .running else { continue }
            job.status = .queued
            job.append(.recovered, message: "Recovered after interruption")
            try write(job)
            recovered.append(job)
        }
        return recovered
    }

    public func start(_ id: WorkflowJob.ID) throws -> WorkflowJob {
        var job = try require(id)
        guard job.status == .queued || job.status == .paused || job.status == .waitingForUser else {
            throw WorkflowJobQueueError.notRunnable(id)
        }
        job.status = .running
        job.attempt += 1
        job.lastError = nil
        job.append(.started)
        try write(job)
        return job
    }

    public func checkpoint(
        _ id: WorkflowJob.ID,
        state: WorkflowRunState,
        kind: WorkflowRunJournalEntry.Kind = .checkpoint,
        step: WorkflowStep? = nil,
        message: String? = nil
    ) throws -> WorkflowJob {
        var job = try require(id)
        job.state = state
        job.append(kind, step: step, message: message)
        try write(job)
        return job
    }

    public func waitForUser(_ id: WorkflowJob.ID, state: WorkflowRunState, step: WorkflowStep) throws {
        var job = try require(id)
        job.state = state
        job.status = .waitingForUser
        job.append(.waitingForUser, step: step)
        try write(job)
    }

    public func pause(_ id: WorkflowJob.ID, state: WorkflowRunState) throws {
        var job = try require(id)
        job.state = state
        job.status = .paused
        job.append(.paused)
        try write(job)
    }

    /// Failed attempts below the limit return to `queued`; the cursor is unchanged, making retry
    /// idempotent at the queue level and leaving tool-specific idempotency to the registered tool.
    public func fail(_ id: WorkflowJob.ID, state: WorkflowRunState, error: String) throws -> WorkflowJob {
        var job = try require(id)
        job.state = state
        job.lastError = error
        if job.attempt < job.maxAttempts {
            job.status = .queued
            job.append(.retryScheduled, message: error)
        } else {
            job.status = .failed
            job.append(.failed, message: error)
        }
        try write(job)
        return job
    }

    public func complete(_ id: WorkflowJob.ID, state: WorkflowRunState) throws {
        var job = try require(id)
        job.state = state
        job.status = .succeeded
        job.append(.completed)
        try write(job)
    }

    public func cancel(_ id: WorkflowJob.ID) throws {
        var job = try require(id)
        job.status = .cancelled
        job.append(.cancelled)
        try write(job)
    }

    public func retry(_ id: WorkflowJob.ID) throws -> WorkflowJob {
        var job = try require(id)
        guard job.status == .failed else { throw WorkflowJobQueueError.notRunnable(id) }
        job.status = .queued
        job.attempt = 0
        job.lastError = nil
        job.append(.retryScheduled)
        try write(job)
        return job
    }

    /// Keeps diagnostics useful without allowing successful run records to grow forever. Failed
    /// and resumable work is never removed automatically.
    public func pruneFinished(keeping limit: Int) throws {
        let terminal = all()
            .filter { $0.status == .succeeded || $0.status == .cancelled }
            .sorted { $0.updatedAt > $1.updatedAt }
        for job in terminal.dropFirst(max(0, limit)) {
            try FileManager.default.removeItem(at: url(for: job.id))
        }
    }

    private func require(_ id: UUID) throws -> WorkflowJob {
        guard let job = read(url(for: id)) else { throw WorkflowJobQueueError.notFound(id) }
        return job
    }

    private func url(for id: UUID) -> URL {
        root.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
    }

    private func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
    }

    private func read(_ url: URL) -> WorkflowJob? {
        guard let data = try? Data(contentsOf: url),
              let job = try? decoder.decode(WorkflowJob.self, from: data),
              job.schemaVersion <= WorkflowJob.currentSchemaVersion
        else { return nil }
        return job
    }

    private func write(_ job: WorkflowJob) throws {
        try encoder.encode(job).write(to: url(for: job.id), options: .atomic)
    }
}
