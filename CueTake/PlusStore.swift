import DesignSystem
import Domain
import Foundation
import Observation
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

    /// "4,99 $" in the viewer's currency and format; nil until the product has loaded.
    var price: String? { product?.displayPrice }

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
        onChange?(active)
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
        plusStore.onChange = { [weak self] active in
            self?.access.setPlan(active ? .pro : .free)
            if active { self?.suflorModel.reportLocked = false }
        }
        plusStore.start()
    }

    /// The way into CueTake+: the App Store's own purchase sheet.
    func upgradeToPlus() {
        Task {
            switch await plusStore.purchase() {
            case .purchased: show(notice: AppLocalization.string("plus.welcome"))
            case .pending: show(notice: AppLocalization.string("plus.pending"))
            case .failed: show(notice: AppLocalization.string("plus.failed"))
            case .cancelled: break
            }
        }
    }

    func restorePlus() {
        Task {
            let active = await plusStore.restore()
            show(notice: AppLocalization.string(active ? "plus.restored" : "plus.nothingToRestore"))
        }
    }
}
