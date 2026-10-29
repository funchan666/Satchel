import Foundation
import StoreKit

enum SubscriptionProductIDs {
    static let monthly = "coins_1.99"
    static let yearly = "conis_4.99"
}

@MainActor final class MembershipStore: ObservableObject {
    static let monthlyID = SubscriptionProductIDs.monthly
    static let yearlyID = SubscriptionProductIDs.yearly
    private let productIDs = [monthlyID, yearlyID]
    private static let legacyIDs: Set<String> = ["clipo.plus.monthly", "clipo.plus.yearly", "satchel.plus.monthly", "satchel.plus.yearly"]
    static let allEntitlementIDs: Set<String> = legacyIDs.union([monthlyID, yearlyID])
    @Published private(set) var products: [Product] = []
    @Published private(set) var isMember = false
    @Published private(set) var entitlementsReady = false
    @Published private(set) var loading = false
    @Published var message: String?
    private var updatesTask: Task<Void, Never>?
    private let tokenFile: URL?
    private var purchaseTokens: Set<UUID> = []
    private var tokenStorageAvailable = false
    init() {
        tokenFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Satchel", isDirectory: true).appendingPathComponent("membership-purchase-tokens.json")
        if let tokenFile {
            do {
                if FileManager.default.fileExists(atPath: tokenFile.path) {
                    purchaseTokens = try JSONDecoder().decode(Set<UUID>.self, from: Data(contentsOf: tokenFile))
                }
                tokenStorageAvailable = true
            } catch { tokenStorageAvailable = false }
        }
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
        // Save the source before starting StoreKit so a relaunch cannot mistake
        // an unfinished B-side purchase for an A-side purchase.
        let accountToken = UUID()
        guard rememberPurchaseToken(accountToken) else {
            message = "The purchase could not be completed. Please try again."
            return
        }
        do {
            switch try await product.purchase(options: [.appAccountToken(accountToken)]) {
            case .success(let result):
                if case .verified(let transaction) = result, productIDs.contains(transaction.productID), transaction.appAccountToken == accountToken {
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
        guard case .verified(let transaction) = result, Self.allEntitlementIDs.contains(transaction.productID) else { return }
        if !Self.legacyIDs.contains(transaction.productID) {
            // Shared IDs may belong to a B-side order. Unknown tokens stay
            // unfinished until their original owner can reconcile them.
            guard let token = transaction.appAccountToken, purchaseTokens.contains(token) else { return }
        }
        if transaction.revocationDate == nil && (transaction.expirationDate.map { $0 > Date() } ?? false) { isMember = true; entitlementsReady = true }
        await transaction.finish(); await refreshEntitlements()
    }
    private func finishPendingTransactions() async {
        for await result in Transaction.unfinished { await process(result) }
    }
    private func rememberPurchaseToken(_ token: UUID) -> Bool {
        guard tokenStorageAvailable, let tokenFile else { return false }
        var updated = purchaseTokens
        updated.insert(token)
        do {
            try FileManager.default.createDirectory(at: tokenFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: tokenFile, options: .atomic)
            purchaseTokens = updated
            return true
        } catch { tokenStorageAvailable = false; return false }
    }
    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, Self.allEntitlementIDs.contains(transaction.productID), transaction.revocationDate == nil else { continue }
            active = true
        }
        isMember = active; entitlementsReady = true
    }
}
