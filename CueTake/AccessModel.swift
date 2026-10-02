import Analytics
import DesignSystem
import Domain
import Foundation
import Observation
import Persistence
import SettingsFeature

/// A refused attempt, for the paywall to open on.
struct AccessRequest: Identifiable, Hashable {
    let id = UUID()
    let point: AccessPoint
    let decision: AccessDecision
}

/// The plan the creator is on and what they have used this period, asked before anything paid runs.
///
/// A period is what the allowance is counted over. On the free plan it is the calendar month. On
/// CueTake+ it is the subscription's own billing period: someone who subscribes on the 16th has a
/// full allowance from the 16th and a fresh one on the 16th of the next month, when the App Store
/// renews, not on the 1st. Counts are kept per period, so taking CueTake+ starts a clean count and
/// going back to the free plan finds that month's free count where it was left.
///
/// Counts live in the Keychain, which outlives deleting the app, so reinstalling does not reset an
/// allowance. The plan is `free` until the store says otherwise (`setPlan`).
///
/// Counted on the phone. A determined user can get around a phone-side count, so the server will
/// have to count too once requests carry the account; this is what the app shows and enforces.
@MainActor @Observable
final class AccessModel {
    private(set) var plan: Plan
    /// Uses by period, then by meter key. See `periodKey`.
    private var periods: [String: [String: Int]]
    /// The CueTake+ billing period in force: from the last charge to the next renewal. Nil on the
    /// free plan, and on CueTake+ without a subscription (the test account), which counts by month.
    private var subscription: (start: Date, end: Date)?
    /// The last refused attempt. Whoever shows the paywall reads it and sets it back to nil.
    var request: AccessRequest?

    /// Set when the store confirms a subscription; nil until then.
    private var purchasedPlan: Plan?
    private let keychain = KeychainStore(account: "cuetake.usage.v1")
    /// Set while the test account is signed in (see `AppModel.signInForReview`).
    static let reviewKey = "cuetake.review.access"
    /// The billing period as last heard from the store, for a launch before it answers again.
    private static let periodStartKey = "cuetake.plus.period.start"
    private static let periodEndKey = "cuetake.plus.period.end"

    /// Runs on a refusal the user caused, with the words to show until there is a paywall.
    var onRefused: ((String) -> Void)?

    /// Runs when a use on the free plan leaves three or fewer for the month, with the words to
    /// show ("AI edit: 2 left this month"), so the limit card is never the first they hear of it.
    var onLow: ((String) -> Void)?

    /// What the Keychain holds: every recent period's counts.
    private struct Saved: Codable {
        var periods: [String: [String: Int]]
    }

    init() {
        let data = keychain.read().flatMap { $0.data(using: .utf8) }
        if let data, let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            periods = saved.periods
        } else if let data, let month = try? JSONDecoder().decode(UsageLedger.self, from: data) {
            // Written by a version that counted one calendar month for everyone.
            periods = [month.month: month.counts]
        } else {
            periods = [:]
        }
        let start = UserDefaults.standard.double(forKey: Self.periodStartKey)
        let end = UserDefaults.standard.double(forKey: Self.periodEndKey)
        if start > 0, end > start {
            subscription = (Date(timeIntervalSince1970: start), Date(timeIntervalSince1970: end))
        } else {
            subscription = nil
        }
        plan = Self.resolvedPlan(purchased: nil)
    }

    /// TestFlight builds carry a sandbox receipt.
    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    private static func resolvedPlan(purchased: Plan?) -> Plan {
        if purchased == .pro { return .pro }
        // The test account opens everything; anyone else, App Review included, starts on the free
        // plan and can find the purchase.
        if UserDefaults.standard.bool(forKey: reviewKey) { return .pro }
        return purchased ?? .free
    }

    /// The store's answer: `.pro` while a subscription is active, with the billing period it is in
    /// (from the last charge to the next renewal), and `.free` when it has ended.
    ///
    /// A nil `period` with `.pro` keeps the period already known: that is the launch before the
    /// store has answered, not a subscription without one.
    func setPlan(_ plan: Plan, period: (start: Date, end: Date)? = nil) {
        purchasedPlan = plan
        if plan == .free {
            subscription = nil
            UserDefaults.standard.removeObject(forKey: Self.periodStartKey)
            UserDefaults.standard.removeObject(forKey: Self.periodEndKey)
        } else if let period {
            subscription = period
            UserDefaults.standard.set(period.start.timeIntervalSince1970, forKey: Self.periodStartKey)
            UserDefaults.standard.set(period.end.timeIntervalSince1970, forKey: Self.periodEndKey)
        }
        self.plan = Self.resolvedPlan(purchased: plan)
    }

    /// The test account is signed in: every CueTake+ tool is open.
    var hasReviewAccess = UserDefaults.standard.bool(forKey: AccessModel.reviewKey) {
        didSet {
            UserDefaults.standard.set(hasReviewAccess, forKey: Self.reviewKey)
            plan = Self.resolvedPlan(purchased: purchasedPlan)
        }
    }

    /// The name the period in force is counted under: `plus-2026-10-16` for the billing period
    /// that began with that day's charge, `2026-10` for a calendar month. A renewal is a new
    /// charge, so a new name and a fresh count.
    private var periodKey: String {
        if plan == .pro, let subscription {
            let parts = Self.utcCalendar.dateComponents([.year, .month, .day], from: subscription.start)
            return String(format: "plus-%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
        return UsageLedger.month(of: .now)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// This period's counts.
    var ledger: UsageLedger {
        let key = periodKey
        return UsageLedger(month: key, counts: periods[key] ?? [:])
    }

    func decision(_ point: AccessPoint) -> AccessDecision {
        AccessPolicy.decide(point, plan: plan, ledger: ledger)
    }

    func remaining(_ point: AccessPoint) -> Int? {
        AccessPolicy.remaining(point, plan: plan, ledger: ledger)
    }

    /// Whether `point` may run now; counts it when it may. Refused, it records the request for the
    /// paywall and, unless `quietly`, says why.
    @discardableResult
    func use(_ point: AccessPoint, quietly: Bool = false) -> Bool {
        var ledger = self.ledger
        let decision = AccessPolicy.decide(point, plan: plan, ledger: ledger)
        guard decision.isAllowed else {
            Analytics.track("feature_refused", ["feature": .text(point.analyticsName), "reason": .text(decision.analyticsName), "shown": .flag(!quietly)])
            if !quietly {
                Analytics.track("paywall_shown", ["feature": .text(point.analyticsName), "reason": .text(decision.analyticsName), "plan": .text(plan.rawValue)])
                request = AccessRequest(point: point, decision: decision)
                onRefused?(Self.message(for: decision))
            }
            return false
        }
        ledger.record(point)
        save(ledger)
        Analytics.track("feature_used", ["feature": .text(point.analyticsName), "used_this_month": .int(ledger.used(point))])
        if !quietly, plan == .free, let left = AccessPolicy.remaining(point, plan: plan, ledger: ledger), left <= 3 {
            onLow?(left == 0
                ? AppLocalization.string("access.noneLeft \(point.title)")
                : AppLocalization.string("access.left \(point.title) \(left)"))
        }
        return true
    }

    /// Gives a use back when the attempt failed on our side (offline, the server down).
    func refund(_ point: AccessPoint) {
        var ledger = self.ledger
        ledger.refund(point)
        save(ledger)
    }

    /// When the allowance starts again: on CueTake+ the day the subscription renews, otherwise
    /// the first of next month (UTC, like the count).
    var resetsAt: Date {
        if plan == .pro, let subscription, subscription.end > .now { return subscription.end }
        let start = Self.utcCalendar.dateInterval(of: .month, for: .now)?.end
        return start ?? Date.now.addingTimeInterval(30 * 86_400)
    }

    static func message(for decision: AccessDecision) -> String {
        switch decision {
        case .allowed: ""
        case .proOnly: AppLocalization.string("access.proOnly")
        case .limitReached(let limit): AppLocalization.string("access.limit \(limit)")
        }
    }

    /// Writes this period's counts, keeping the two most recent periods of each kind (their names
    /// sort by date), so the Keychain entry stays small.
    private func save(_ ledger: UsageLedger) {
        var kept = periods
        kept[ledger.month] = ledger.counts
        let months = Set(kept.keys.filter { !$0.hasPrefix("plus-") }.sorted().suffix(2))
        let billing = Set(kept.keys.filter { $0.hasPrefix("plus-") }.sorted().suffix(2))
        periods = kept.filter { months.contains($0.key) || billing.contains($0.key) }
        guard let data = try? JSONEncoder().encode(Saved(periods: periods)), let text = String(data: data, encoding: .utf8) else { return }
        _ = keychain.save(text)
    }
}

extension AppModel {
    /// Settings' CueTake+ card: the plan, each counted feature's use this month, and on the free
    /// plan the tools only CueTake+ has.
    var plusUsage: PlusUsage {
        let ledger = access.ledger
        let plan = access.plan
        let counted: [AccessPoint] = [.aiEdit, .assistantMessage, .scriptWriting, .captionTranslation, .workflowRun, .stockBroll, .cloudListening]
        let rows = counted.map { point in
            PlusUsage.Row(
                id: point.meterKey ?? point.title,
                title: point.title,
                used: ledger.used(point),
                limit: AccessPolicy.monthlyLimit(point, plan: plan),
                locked: plan == .free && AccessPolicy.isProOnly(point)
            )
        }
        let plusOnly: [AccessPoint] = [.iCloudBackup, .suflorReport, .videoStyle(.energetic), .soundDesign, .beatSync, .brandTemplate, .multiPlatformExport, .highResolutionCapture, .highResolutionExport]
        return PlusUsage(
            isPlus: plan == .pro,
            rows: rows,
            plusTools: plan == .free ? plusOnly.map(\.title) : [],
            resetsAt: access.resetsAt,
            price: plusStore.price,
            trial: plusStore.trial,
            renewal: plusRenewalLine
        )
    }
}
