import UIKit
import AIServices
import Analytics
import DesignSystem
import Domain
import Foundation
import Observation
import SettingsFeature
import StoreKit
import SuflorFeature

/// CueTake+ through the App Store: the product, the purchase, and whether it is active now.
///
/// The App Store is the only judge of the plan. Every launch reads the current entitlements, and a
/// listener follows renewals, refunds and expiries while the app runs, so a lapsed subscription
/// drops back to the free plan without the user doing anything.
@MainActor @Observable
final class PlusStore {
    static let monthlyID = "com.orhay.cuetake.plus.monthly"

    private(set) var product: Product?
    private(set) var isPurchasing = false
    private(set) var isActive = false

    /// Tells the plan what the store says.
    @ObservationIgnored var onChange: ((Bool) -> Void)?
    @ObservationIgnored private var updates: Task<Void, Never>?

    /// "7,49 $" in the viewer's currency and format; nil until the product has loaded.
    var price: String? { product?.displayPrice }

    /// "7 days free", when App Store Connect has a free trial and this Apple Account can still
    /// take it. Nil otherwise: the paywall then shows the price alone.
    private(set) var trial: String?

    /// When the current period ends, and whether it renews then or stops. Nil on the free plan.
    private(set) var renewal: (date: Date, renews: Bool)?

    /// The last answer, for the next launch: a subscriber is Plus from the first frame, not after
    /// the store has been asked, and an offline start does not look like a lapsed subscription.
    private static let activeKey = "cuetake.plus.active"
    static var wasActive: Bool { UserDefaults.standard.bool(forKey: activeKey) }

    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task {
            await loadProduct()
            await refresh()
        }
    }

    func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [Self.monthlyID]).first
        await readTrial()
    }

    /// The introductory free trial, worded for the paywall, when there is one to take.
    private func readTrial() async {
        guard let subscription = product?.subscription,
              let offer = subscription.introductoryOffer,
              offer.paymentMode == .freeTrial,
              await subscription.isEligibleForIntroOffer
        else {
            trial = nil
            return
        }
        let count = offer.period.value
        trial = switch offer.period.unit {
        case .day: AppLocalization.string("plus.trial.days \(count)")
        case .week: AppLocalization.string("plus.trial.weeks \(count)")
        case .month: AppLocalization.string("plus.trial.months \(count)")
        case .year: AppLocalization.string("plus.trial.years \(count)")
        @unknown default: nil
        }
    }

    /// Whether a verified, unrevoked CueTake+ transaction is current.
    func refresh() async {
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  transaction.productID == Self.monthlyID,
                  transaction.revocationDate == nil
            else { continue }
            if let expiry = transaction.expirationDate, expiry < .now { continue }
            active = true
        }
        isActive = active
        UserDefaults.standard.set(active, forKey: Self.activeKey)
        await readRenewal(active: active)
        // Taking the trial uses it up: the paywall stops offering it.
        if active { trial = nil }
        onChange?(active)
    }

    /// The period's end and whether it renews, from the subscription's status.
    private func readRenewal(active: Bool) async {
        guard active else {
            renewal = nil
            return
        }
        if product == nil { await loadProduct() }
        guard let statuses = try? await product?.subscription?.status else { return }
        for status in statuses {
            guard case .verified(let info) = status.renewalInfo,
                  case .verified(let transaction) = status.transaction,
                  transaction.productID == Self.monthlyID,
                  let end = transaction.expirationDate
            else { continue }
            renewal = (end, info.willAutoRenew)
            return
        }
    }

    /// Apple's own sheet for an offer code: the codes handed out to creators and in campaigns.
    func redeemOfferCode() async {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }
        try? await AppStore.presentOfferCodeRedeemSheet(in: scene)
        await refresh()
    }

    enum Outcome {
        case purchased, cancelled, pending, failed
    }

    func purchase() async -> Outcome {
        await loadProduct()
        guard let product, !isPurchasing else { return .failed }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else { return .failed }
                await transaction.finish()
                await refresh()
                return .purchased
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    /// Asks the App Store for this Apple ID's purchases again, for a new phone or a reinstall.
    func restore() async -> Bool {
        try? await AppStore.sync()
        await refresh()
        return isActive
    }

    static let termsURL = URL(string: "https://mericorhay.github.io/CueTake/#terms")!
    static let privacyURL = URL(string: "https://mericorhay.github.io/CueTake/#privacy")!
}

extension AppModel {
    /// Starts following the subscription, and lets the store decide the plan from now on.
    func startPlusStore() {
        // What the store said last time, until it answers again.
        if PlusStore.wasActive { access.setPlan(.pro) }
        plusStore.onChange = { [weak self] active in
            self?.access.setPlan(active ? .pro : .free)
            self?.rememberForAnalytics()
            if active { self?.suflorModel.reportLocked = false }
        }
        plusStore.start()
    }

    /// The way into CueTake+: the App Store's own purchase sheet.
    func upgradeToPlus() {
        Task {
            let outcome = await plusStore.purchase()
            Analytics.track("plus_purchase", ["outcome": .text(String(describing: outcome))])
            switch outcome {
            case .purchased: show(notice: AppLocalization.string("plus.welcome"))
            case .pending: show(notice: AppLocalization.string("plus.pending"))
            case .failed: show(notice: AppLocalization.string("plus.failed"))
            case .cancelled: break
            }
        }
    }

    func redeemPlusCode() {
        Task {
            await plusStore.redeemOfferCode()
            Analytics.track("plus_offer_code", ["active": .flag(plusStore.isActive)])
            if plusStore.isActive { show(notice: AppLocalization.string("plus.welcome")) }
        }
    }

    /// "Renews 25 October" or "Ends 25 October", for the CueTake+ card.
    var plusRenewalLine: String? {
        guard let renewal = plusStore.renewal else { return nil }
        let date = renewal.date.formatted(.dateTime.day().month(.wide).locale(AppLocalization.locale))
        return renewal.renews
            ? AppLocalization.string("plus.renews \(date)")
            : AppLocalization.string("plus.ends \(date)")
    }

    /// Signs in the test account: our server checks the name and password, and on a match every
    /// CueTake+ tool opens on this phone without a purchase.
    func signInForReview(username: String, password: String) async -> ReviewAccess.Result {
        do {
            guard try await dependencies.assistantClient.reviewSignIn(username: username, password: password) else {
                Analytics.track("review_sign_in", ["ok": false])
                return .wrongCredentials
            }
            access.hasReviewAccess = true
            Analytics.track("review_sign_in", ["ok": true])
            return .signedIn
        } catch {
            return .unavailable
        }
    }

    func restorePlus() {
        Task {
            let active = await plusStore.restore()
            Analytics.track("plus_restore", ["found": .flag(active)])
            show(notice: AppLocalization.string(active ? "plus.restored" : "plus.nothingToRestore"))
        }
    }
}
