//
//  StoreKitManager.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 12/5/25.
//
//  Buying PlotLine Plus through the App Store. Every purchase, restore and renewal is sent to
//  the server, which checks Apple's signature and unlocks the account (see MembershipManager).
//

import StoreKit
import Combine

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    static let monthlyProductID = "plus_monthly"

    @Published private(set) var monthlyProduct: Product?
    /// Apple allows one free trial per Apple ID
    @Published private(set) var isEligibleForTrial = false

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { await self.observeTransactions() }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        if monthlyProduct == nil {
            do {
                monthlyProduct = try await Product.products(for: [Self.monthlyProductID]).first
            } catch {
                print("Couldn't load App Store products: \(error)")
            }
        }
        if let subscription = monthlyProduct?.subscription, subscription.introductoryOffer != nil {
            isEligibleForTrial = await subscription.isEligibleForIntroOffer
        } else {
            isEligibleForTrial = false
        }
    }

    /// Buy the membership. Returns the server's status, or nil if the person cancelled or the
    /// purchase is waiting for approval (Ask to Buy).
    func purchase() async throws -> MembershipStatus? {
        guard let product = monthlyProduct else {
            throw PaymentAPIError.custom("The App Store isn't available right now. Please try again.")
        }
        switch try await product.purchase() {
        case .success(let verification):
            return try await deliver(verification)
        case .pending, .userCancelled:
            return nil
        @unknown default:
            return nil
        }
    }

    /// Restore Purchases: refresh this Apple ID's purchases from the App Store and send them to the server.
    func restore() async throws -> MembershipStatus? {
        try await AppStore.sync()
        return try await syncCurrentEntitlements()
    }

    /// Sends the subscription active on this Apple ID (if any) to the server.
    @discardableResult
    func syncCurrentEntitlements() async throws -> MembershipStatus? {
        var latest: MembershipStatus?
        for await result in Transaction.currentEntitlements where result.unsafePayloadValue.productID == Self.monthlyProductID {
            latest = try await deliver(result)
        }
        return latest
    }

    // renewals, Ask to Buy approvals and purchases made on other devices
    private func observeTransactions() async {
        for await update in Transaction.updates {
            guard KeychainManager.loadToken() != nil else { continue } // sent after the next sign-in instead
            _ = try? await deliver(update)
        }
    }

    /// Hands a purchase to the server. It's only marked finished once the server has it (or has
    /// refused it), so a purchase made offline is retried on the next launch.
    private func deliver(_ result: VerificationResult<Transaction>) async throws -> MembershipStatus {
        guard case .verified(let transaction) = result else {
            throw PaymentAPIError.custom("This purchase couldn't be verified with the App Store.")
        }
        do {
            let status = try await PaymentAPI.syncApplePurchase(signedTransaction: result.jwsRepresentation)
            await transaction.finish()
            MembershipManager.shared.update(status)
            return status
        } catch PaymentAPIError.custom(let message) {
            await transaction.finish()
            throw PaymentAPIError.custom(message)
        }
    }
}
