import Foundation
import StoreKit

@MainActor final class MembershipStore: ObservableObject {
    static let monthlyID = "satchel.plus.monthly"
    static let yearlyID = "satchel.plus.yearly"
    private let productIDs = [monthlyID, yearlyID]
    @Published private(set) var products: [Product] = []
    @Published private(set) var isMember = false
    @Published private(set) var entitlementsReady = false
    @Published private(set) var loading = false
    @Published var message: String?
    private var updatesTask: Task<Void, Never>?
    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.process(result)
            }
        }
        Task { await refreshEntitlements(); await finishPendingTransactions(); await loadProducts() }
    }
    deinit { updatesTask?.cancel() }
    func loadProducts() async {
        loading = true; message = nil; defer { loading = false }
        do {
            let available = try await Product.products(for: productIDs)
            products = productIDs.compactMap { id in
                available.first { product in
                    guard product.id == id, let period = product.subscription?.subscriptionPeriod, period.value == 1 else { return false }
                    return id == Self.monthlyID ? period.unit == .month : period.unit == .year
                }
            }
            if products.count < productIDs.count { message = "Subscription products are not available yet. Please try again later." }
        } catch { message = "Subscription products could not be loaded. Please try again." }
    }
    func purchase(_ product: Product) async {
        guard productIDs.contains(product.id), !loading else { return }
        loading = true; defer { loading = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let transaction) = result, productIDs.contains(transaction.productID) {
                    if transaction.revocationDate == nil && (transaction.expirationDate.map { $0 > Date() } ?? false) { isMember = true; entitlementsReady = true }
                    await transaction.finish(); await refreshEntitlements()
                    message = isMember ? "Your membership is active." : "Your purchase was received. Check your membership status again shortly."
                } else { message = "The purchase could not be verified." }
            case .pending: message = "Your purchase is pending approval."
            case .userCancelled: break
            @unknown default: message = "The purchase could not be completed."
            }
        } catch { message = "The purchase could not be completed. Please try again." }
    }
    func restore() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do { try await AppStore.sync(); await refreshEntitlements(); message = isMember ? "Your membership is active." : "No active membership was found." }
        catch { message = "Purchases could not be restored. Please try again." }
    }
    private func process(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result, productIDs.contains(transaction.productID) else { return }
        if transaction.revocationDate == nil && (transaction.expirationDate.map { $0 > Date() } ?? false) { isMember = true; entitlementsReady = true }
        await transaction.finish(); await refreshEntitlements()
    }
    private func finishPendingTransactions() async {
        for await result in Transaction.unfinished { await process(result) }
    }
    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, productIDs.contains(transaction.productID), transaction.revocationDate == nil else { continue }
            active = true
        }
        isMember = active; entitlementsReady = true
    }
}
