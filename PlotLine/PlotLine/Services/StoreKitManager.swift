//
//  StoreKitManager.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 12/5/25.
//

import StoreKit
import Combine

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    private let monthlyProductID  = "plus_monthly"
    private let lifetimeProductID = "plus_lifetime" // optional

    @Published var monthlyProduct: Product?
    @Published var isEntitled = false
    @Published var plan: String? = nil            // "trial", "monthly", "lifetime"
    @Published var trialEndsAt: Date? = nil

    private var updatesTask: Task<Void, Never>?

    init() {

        updatesTask = Task<Void, Never> { await self.observeTransactions() }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async throws {
        let productIDs: Set<String> = [monthlyProductID, lifetimeProductID]
        let products = try await Product.products(for: productIDs)
        self.monthlyProduct = products.first(where: { $0.id == monthlyProductID })
        try? await refreshEntitlements()
    }

    func refreshEntitlements() async throws {
        var foundEntitlement = false
        var currentPlan: String? = nil
        var trialEnd: Date? = nil

        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result {
                if t.productType == .autoRenewable && t.productID == monthlyProductID {
                    foundEntitlement = true
                    currentPlan = try? await classifyMonthlyPlan()

                    // Best-effort trial end from current transaction
                    if monthlyProduct?.subscription?.introductoryOffer != nil {
                        if let exp = t.expirationDate {
                            trialEnd = exp
                        }
                    }
                } else if t.productType == .nonConsumable && t.productID == lifetimeProductID {
                    foundEntitlement = true
                    currentPlan = "lifetime"
                    trialEnd = nil
                }
            }
        }

        // Server-granted lifetime comps
        if let server = try? await PaymentAPI.fetchStatus(username: currentUsername()),
           server.plan == "lifetime" {
            foundEntitlement = true
            currentPlan = "lifetime"
            trialEnd = nil
        }

        self.isEntitled = foundEntitlement
        self.plan = currentPlan
        self.trialEndsAt = trialEnd
    }

    private func classifyMonthlyPlan() async throws -> String {
        guard let m = monthlyProduct else { return "monthly" }
        if m.subscription?.introductoryOffer?.paymentMode == .freeTrial {
            return "trial"
        }
        return "monthly"
    }

    func purchaseMonthly() async throws {
        guard let product = monthlyProduct else { throw PurchaseError.missingProduct }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction: Transaction = try checkVerified(verification)
            await transaction.finish()

            try? await refreshEntitlements()

            try? await PaymentAPI.syncAppleEntitlement(
                username: currentUsername(),
                originalTransactionID: transaction.originalID,
                appAccountToken: transaction.appAccountToken
            )

        case .pending: break
        case .userCancelled: throw PurchaseError.userCancelled
        @unknown default: throw PurchaseError.unknown
        }
    }

    func restore() async {
        try? await AppStore.sync()
        try? await refreshEntitlements()
    }

    private func observeTransactions() async {
        for await update in Transaction.updates {
            if case .verified(let t) = update {
                await t.finish()
                try? await refreshEntitlements()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw PurchaseError.unverified
        case .verified(let safe): return safe
        }
    }

    private func currentUsername() -> String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    enum PurchaseError: Error { case missingProduct, unverified, userCancelled, unknown }
}
