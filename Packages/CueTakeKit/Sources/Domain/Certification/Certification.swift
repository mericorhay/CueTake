import Foundation

/// The three public certificates, from the first to the hardest.
public enum CertificationLevel: String, CaseIterable, Codable, Sendable, Comparable {
    case creator
    case advancedCreator
    case workflowSpecialist

    /// Hours of active work: editing, recording, running workflows. Time the app sat open does
    /// not count.
    public var requiredHours: Double {
        switch self {
        case .creator: 20
        case .advancedCreator: 40
        case .workflowSpecialist: 60
        }
    }

    /// Finished projects: exported at least once.
    public var requiredProjects: Int {
        switch self {
        case .creator: 8
        case .advancedCreator: 15
        case .workflowSpecialist: 25
        }
    }

    /// Editing tasks that must each have been done at least once.
    public var requiredTasks: [CertificationTask] {
        switch self {
        case .creator: []
        case .advancedCreator, .workflowSpecialist: CertificationTask.allCases
        }
    }

    /// Workflow runs that finished.
    public var requiredWorkflowRuns: Int {
        self == .workflowSpecialist ? 10 : 0
    }

    /// A project looked at by someone who knows the craft.
    public var requiresReview: Bool { self == .workflowSpecialist }

    /// The one before it, which must be held first.
    public var previous: CertificationLevel? {
        switch self {
        case .creator: nil
        case .advancedCreator: .creator
        case .workflowSpecialist: .advancedCreator
        }
    }

    public static func < (a: Self, b: Self) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// Editing a creator is expected to have done, each proved by the project it left behind.
public enum CertificationTask: String, CaseIterable, Codable, Sendable {
    /// A take recorded reading a script.
    case prompterTake
    /// A clip cleaned against its script.
    case cleanup
    case captions
    case transition
    /// A background replaced or kept around a person.
    case background
    case colorLook
    case textBehindPerson
    /// Music shaped with a volume curve.
    case volumeCurve
    /// A second video over the first.
    case layeredVideo
    /// A version of a project kept by name.
    case namedVersion
    case workflowRun
}

/// Everything a creator has done toward the certificates, kept on the phone.
public struct CertificationProgress: Codable, Hashable, Sendable {
    /// Identifies this install in certificate ids. Not the person: nothing here says who they are.
    public var installID: UUID
    public var activeSeconds: Double
    /// Projects exported at least once, by id, so exporting one project ten times counts once.
    public var finishedProjects: Set<UUID>
    public var workflowRuns: Int
    public var tasks: [CertificationTask: Date]
    public var earned: [CertificationLevel: Date]
    /// Signed certificates from the server, by level.
    public var signed: [CertificationLevel: SignedCertificate]
    public var reviewRequested: Date?
    /// The name printed on certificates, as the creator wrote it. Nil prints none.
    public var holderName: String?
    /// The latest review of a finished project, as the server signed it.
    public var review: SignedReview?

    /// When time was last counted, and when the person last did something.
    public var lastTick: Date?
    public var lastActivity: Date?

    public init(installID: UUID = UUID()) {
        self.installID = installID
        activeSeconds = 0
        finishedProjects = []
        workflowRuns = 0
        tasks = [:]
        earned = [:]
        signed = [:]
    }

    /// Longer than this without a touch, a recording or playback is not work.
    public static let idleLimit: TimeInterval = 120
    /// The most one tick can add, so a phone that slept between ticks does not bank the night.
    public static let longestTick: TimeInterval = 60

    public var activeHours: Double { activeSeconds / 3600 }

    // MARK: - Counting

    /// Something was done: an edit, a take, a play.
    public mutating func noteActivity(at now: Date) {
        lastActivity = now
    }

    /// Counts the time since the last tick, if the person was working through it.
    ///
    /// - Parameter working: the app is in front and on a screen where work happens.
    public mutating func tick(at now: Date, working: Bool) {
        defer { lastTick = now }
        guard working, let lastTick, let lastActivity else { return }
        guard now.timeIntervalSince(lastActivity) <= Self.idleLimit else { return }
        let gap = now.timeIntervalSince(lastTick)
        guard gap > 0 else { return }
        activeSeconds += min(gap, Self.longestTick)
    }

    public mutating func noteFinished(project: UUID) {
        finishedProjects.insert(project)
    }

    public mutating func noteWorkflowRun(at now: Date) {
        workflowRuns += 1
        complete(.workflowRun, at: now)
    }

    public mutating func complete(_ task: CertificationTask, at now: Date) {
        if tasks[task] == nil { tasks[task] = now }
    }

    /// Marks every task the project shows was done.
    public mutating func observe(_ project: Project, at now: Date) {
        for task in Self.tasks(shownBy: project) { complete(task, at: now) }
    }

    static func tasks(shownBy project: Project) -> [CertificationTask] {
        var found: [CertificationTask] = []
        if project.segments.contains(where: { !$0.takes.isEmpty && !$0.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            found.append(.prompterTake)
        }
        if project.segments.contains(where: { $0.cleanup != nil }) { found.append(.cleanup) }
        if !project.captionCues.isEmpty { found.append(.captions) }
        if !project.transitions.isEmpty { found.append(.transition) }
        if project.effects.contains(where: { $0.background != nil }) { found.append(.background) }
        if project.effects.contains(where: { $0.filter != nil }) { found.append(.colorLook) }
        if project.overlays.contains(where: \.isBehindPerson) { found.append(.textBehindPerson) }
        if project.audio.contains(where: { !($0.volumeKeys ?? []).isEmpty }) { found.append(.volumeCurve) }
        if !project.videoLayers.isEmpty { found.append(.layeredVideo) }
        return found
    }

    // MARK: - Standing

    public struct Standing: Hashable, Sendable {
        public var level: CertificationLevel
        public var hours: Double
        public var projects: Int
        public var tasksDone: [CertificationTask]
        public var workflowRuns: Int
        public var reviewPassed: Bool
        public var holdsPrevious: Bool

        public var hoursFraction: Double { min(1, hours / level.requiredHours) }
        public var projectsFraction: Double { min(1, Double(projects) / Double(max(1, level.requiredProjects))) }
        public var tasksLeft: [CertificationTask] { level.requiredTasks.filter { !tasksDone.contains($0) } }

        /// Everything counted, as one number for the ring: each requirement weighs the same.
        public var fraction: Double {
            var parts = [hoursFraction, projectsFraction]
            if !level.requiredTasks.isEmpty {
                parts.append(Double(level.requiredTasks.count - tasksLeft.count) / Double(level.requiredTasks.count))
            }
            if level.requiredWorkflowRuns > 0 {
                parts.append(min(1, Double(workflowRuns) / Double(level.requiredWorkflowRuns)))
            }
            if level.requiresReview { parts.append(reviewPassed ? 1 : 0) }
            return parts.reduce(0, +) / Double(parts.count)
        }

        /// Every requirement met except, perhaps, the review.
        public var readyForReview: Bool {
            holdsPrevious && hours >= level.requiredHours && projects >= level.requiredProjects
                && tasksLeft.isEmpty && workflowRuns >= level.requiredWorkflowRuns
        }

        public var isMet: Bool { readyForReview && (!level.requiresReview || reviewPassed) }
    }

    public func standing(for level: CertificationLevel) -> Standing {
        Standing(
            level: level,
            hours: activeHours,
            projects: finishedProjects.count,
            tasksDone: CertificationTask.allCases.filter { tasks[$0] != nil },
            workflowRuns: workflowRuns,
            // Only a review the server signed counts; the phone cannot pass itself.
            reviewPassed: review?.passed ?? false,
            holdsPrevious: level.previous.map { earned[$0] != nil } ?? true
        )
    }

    /// Awards every level now met, in order, and says which ones are new.
    public mutating func award(at now: Date) -> [CertificationLevel] {
        var new: [CertificationLevel] = []
        for level in CertificationLevel.allCases where earned[level] == nil {
            guard standing(for: level).isMet else { break }
            earned[level] = now
            new.append(level)
        }
        return new
    }

    /// The highest level held.
    public var highest: CertificationLevel? { earned.keys.max() }

    /// The level being worked toward: the first not yet held.
    public var next: CertificationLevel? { CertificationLevel.allCases.first { earned[$0] == nil } }

    /// A short id for a certificate, the same every time it is shown.
    public func certificateID(for level: CertificationLevel) -> String? {
        guard let date = earned[level] else { return nil }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(installID.uuidString)|\(level.rawValue)|\(Int(date.timeIntervalSince1970))".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var id = ""
        for index in 0..<10 {
            if index == 5 { id.append("-") }
            id.append(letters[Int(hash % UInt64(letters.count))])
            hash /= UInt64(letters.count)
        }
        return "CT-" + id
    }
}

/// A finished project as the server's reviewer saw it, signed so the certificate server can trust
/// it came from the review and not from the phone.
public struct SignedReview: Codable, Hashable, Sendable {
    public var projectTitle: String
    public var score: Int
    public var passed: Bool
    public var strengths: [String]
    public var improvements: [String]
    public var date: Date
    public var payload: String
    public var signature: String

    public init(
        projectTitle: String,
        score: Int,
        passed: Bool,
        strengths: [String],
        improvements: [String],
        date: Date,
        payload: String,
        signature: String
    ) {
        self.projectTitle = projectTitle
        self.score = score
        self.passed = passed
        self.strengths = strengths
        self.improvements = improvements
        self.date = date
        self.payload = payload
        self.signature = signature
    }

    /// The score a project needs.
    public static let passingScore = 70
}

/// A certificate as the server signed it. `payload` is what was signed, as sent; `signature`
/// proves the server signed exactly that; `verifyURL` shows anyone who opens it whether it holds.
public struct SignedCertificate: Codable, Hashable, Sendable {
    public var payload: String
    public var signature: String
    public var verifyURL: URL

    public init(payload: String, signature: String, verifyURL: URL) {
        self.payload = payload
        self.signature = signature
        self.verifyURL = verifyURL
    }
}
