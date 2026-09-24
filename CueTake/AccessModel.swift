import DesignSystem
import Domain
import Foundation
import Observation
import Persistence

/// A refused attempt, for the paywall to open on.
struct AccessRequest: Identifiable, Hashable {
    let id = UUID()
    let point: AccessPoint
    let decision: AccessDecision
}

/// The plan the creator is on and what they have used this month, asked before anything paid runs.
///
/// Counts live in the Keychain, which outlives deleting the app, so reinstalling does not reset a
/// month's allowance. The plan is `free` until the store says otherwise (`setPlan`), except in
/// TestFlight, which starts on Pro so testers are not stopped; Settings there can switch to the
/// free plan to see the limits.
///
/// Counted on the phone. A determined user can get around a phone-side count, so the server will
/// have to count too once requests carry the account; this is what the app shows and enforces.
@MainActor @Observable
final class AccessModel {
    private(set) var plan: Plan
    private(set) var ledger: UsageLedger
    /// The last refused attempt. Whoever shows the paywall reads it and sets it back to nil.
    var request: AccessRequest?

    /// Set when the store confirms a subscription; nil until then.
    private var purchasedPlan: Plan?
    private let keychain = KeychainStore(account: "cuetake.usage.v1")
    static let testFreeKey = "cuetake.plan.testFree"

    /// Runs on a refusal the user caused, with the words to show until there is a paywall.
    var onRefused: ((String) -> Void)?

    init() {
        if let text = keychain.read(), let data = text.data(using: .utf8),
           let saved = try? JSONDecoder().decode(UsageLedger.self, from: data) {
            ledger = saved.current()
        } else {
            ledger = UsageLedger()
        }
        plan = Self.resolvedPlan(purchased: nil)
    }

    /// TestFlight builds carry a sandbox receipt.
    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    private static func resolvedPlan(purchased: Plan?) -> Plan {
        if let purchased { return purchased }
        if isTestFlight { return UserDefaults.standard.bool(forKey: testFreeKey) ? .free : .pro }
        return .free
    }

    /// The store's answer: `.pro` while a subscription is active, `.free` when it has ended.
    func setPlan(_ plan: Plan) {
        purchasedPlan = plan
        self.plan = Self.resolvedPlan(purchased: plan)
    }

    /// TestFlight only: behave as the free plan, to see the limits.
    var testsFreePlan = UserDefaults.standard.bool(forKey: AccessModel.testFreeKey) {
        didSet {
            UserDefaults.standard.set(testsFreePlan, forKey: Self.testFreeKey)
            plan = Self.resolvedPlan(purchased: purchasedPlan)
        }
    }

    func decision(_ point: AccessPoint) -> AccessDecision {
        AccessPolicy.decide(point, plan: plan, ledger: ledger.current())
    }

    func remaining(_ point: AccessPoint) -> Int? {
        AccessPolicy.remaining(point, plan: plan, ledger: ledger.current())
    }

    /// Whether `point` may run now; counts it when it may. Refused, it records the request for the
    /// paywall and, unless `quietly`, says why.
    @discardableResult
    func use(_ point: AccessPoint, quietly: Bool = false) -> Bool {
        ledger = ledger.current()
        let decision = AccessPolicy.decide(point, plan: plan, ledger: ledger)
        guard decision.isAllowed else {
            if !quietly {
                request = AccessRequest(point: point, decision: decision)
                onRefused?(Self.message(for: decision))
            }
            return false
        }
        ledger.record(point)
        save()
        return true
    }

    /// Gives a use back when the attempt failed on our side (offline, the server down).
    func refund(_ point: AccessPoint) {
        ledger = ledger.current()
        ledger.refund(point)
        save()
    }

    static func message(for decision: AccessDecision) -> String {
        switch decision {
        case .allowed: ""
        case .proOnly: AppLocalization.string("access.proOnly")
        case .limitReached(let limit): AppLocalization.string("access.limit \(limit)")
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(ledger), let text = String(data: data, encoding: .utf8) else { return }
        _ = keychain.save(text)
    }
}
