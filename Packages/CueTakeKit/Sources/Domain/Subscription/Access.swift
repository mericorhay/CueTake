import Foundation

/// What the creator pays for.
public enum Plan: String, Hashable, Sendable, Codable {
    case free
    case pro
}

/// Every place the app asks whether something paid may run.
///
/// Two kinds. Metered: allowed on both plans a number of times a month, many more on Pro. Those
/// are the features that cost money on the server each time (a model call, a stock search). Pro
/// only: the finishing touches that make a video look produced. Everything else in the app —
/// recording, the prompter, editing by hand, on-device captions, a single export — is not here and
/// is never limited.
public enum AccessPoint: Hashable, Sendable {
    // Metered on both plans.
    case aiEdit
    case assistantMessage
    case scriptWriting
    case captionTranslation
    case workflowRun
    // Pro only, some also metered on Pro.
    case stockBroll
    case cloudListening
    case videoStyle(VideoStyle)
    case soundDesign
    case beatSync
    case brandTemplate
    case multiPlatformExport
    case highResolutionExport
    case highResolutionCapture
    /// Opening a suflör report. Every report is kept on either plan; reading it is CueTake+.
    case suflorReport

    /// The name a month's count is kept under; nil for what is not counted.
    public var meterKey: String? {
        switch self {
        case .aiEdit: "aiEdit"
        case .assistantMessage: "assistantMessage"
        case .scriptWriting: "scriptWriting"
        case .captionTranslation: "captionTranslation"
        case .workflowRun: "workflowRun"
        case .stockBroll: "stockBroll"
        case .cloudListening: "cloudListening"
        default: nil
        }
    }
}

/// The answer for one attempt.
public enum AccessDecision: Hashable, Sendable {
    case allowed
    /// Needs Pro.
    case proOnly
    /// This month's allowance on the current plan is used up.
    case limitReached(limit: Int)

    public var isAllowed: Bool { self == .allowed }
}

/// How many times each metered feature has been used this month.
public struct UsageLedger: Hashable, Sendable, Codable {
    /// `2026-09`: counts from an earlier month are dropped when the month turns.
    public var month: String
    public var counts: [String: Int]

    public init(month: String = UsageLedger.month(of: .now), counts: [String: Int] = [:]) {
        self.month = month
        self.counts = counts
    }

    public static func month(of date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC") ?? .gmt, from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// The ledger as it stands at `date`: empty again in a new month.
    public func current(at date: Date = .now) -> UsageLedger {
        let now = Self.month(of: date)
        return now == month ? self : UsageLedger(month: now)
    }

    public func used(_ point: AccessPoint) -> Int {
        point.meterKey.map { counts[$0] ?? 0 } ?? 0
    }

    public mutating func record(_ point: AccessPoint) {
        guard let key = point.meterKey else { return }
        counts[key, default: 0] += 1
    }

    public mutating func refund(_ point: AccessPoint) {
        guard let key = point.meterKey, let count = counts[key], count > 0 else { return }
        counts[key] = count - 1
    }
}

/// The rules: what needs Pro, and how much of each metered feature a month buys.
public enum AccessPolicy {
    /// Styles anyone can use; the rest need Pro.
    public static let freeStyles: Set<VideoStyle> = [.minimal, .vlog]

    public static func isProOnly(_ point: AccessPoint) -> Bool {
        switch point {
        case .aiEdit, .assistantMessage, .scriptWriting, .captionTranslation, .workflowRun: false
        case .videoStyle(let style): !freeStyles.contains(style)
        case .stockBroll, .cloudListening, .soundDesign, .beatSync, .brandTemplate,
             .multiPlatformExport, .highResolutionExport, .highResolutionCapture, .suflorReport: true
        }
    }

    /// Uses a month allows on `plan`; nil for no limit.
    public static func monthlyLimit(_ point: AccessPoint, plan: Plan) -> Int? {
        switch (point, plan) {
        case (.aiEdit, .free): 5
        case (.aiEdit, .pro): 150
        case (.assistantMessage, .free): 30
        case (.assistantMessage, .pro): 1500
        case (.scriptWriting, .free): 10
        case (.scriptWriting, .pro): 500
        case (.captionTranslation, .free): 2
        case (.captionTranslation, .pro): 60
        case (.workflowRun, .free): 10
        case (.workflowRun, .pro): nil
        // Pro only, and still fair-use metered there: each one costs a server call.
        case (.stockBroll, .pro): 40
        case (.cloudListening, .pro): 300
        default: nil
        }
    }

    public static func decide(_ point: AccessPoint, plan: Plan, ledger: UsageLedger) -> AccessDecision {
        if plan == .free, isProOnly(point) { return .proOnly }
        if let limit = monthlyLimit(point, plan: plan), ledger.used(point) >= limit {
            return .limitReached(limit: limit)
        }
        return .allowed
    }

    /// Uses left this month, or nil for no limit. For a Pro-only feature on the free plan, 0.
    public static func remaining(_ point: AccessPoint, plan: Plan, ledger: UsageLedger) -> Int? {
        if plan == .free, isProOnly(point) { return 0 }
        guard let limit = monthlyLimit(point, plan: plan) else { return nil }
        return max(0, limit - ledger.used(point))
    }
}

extension WorkflowStepKind {
    /// What running this step spends, when it spends anything.
    public var accessPoint: AccessPoint? {
        switch self {
        case .stockBroll: .stockBroll
        case .soundDesign: .soundDesign
        case .beatSync: .beatSync
        case .brandTemplate: .brandTemplate
        case .aiEdit: .aiEdit
        case .applyStyle(let options): .videoStyle(options.style)
        default: nil
        }
    }
}
