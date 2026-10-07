//
//  PaywallView.swift
//  PlotLine
//
//  Shown instead of the app when the account has no active membership (see RootView).
//  Their data stays saved and comes back as soon as they subscribe.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    /// opened from the free-week banner or Membership screen (the app is still unlocked)
    var isSheet = false

    @EnvironmentObject var session: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StoreKitManager.shared
    @ObservedObject private var membership = MembershipManager.shared

    @State private var inFlight = false
    @State private var errorMessage: String?
    @State private var showingDeleteAccount = false

    private let features: [(String, String)] = [
        ("chart.pie.fill", "Budgets, spending and subscriptions in one place"),
        ("chart.line.uptrend.xyaxis", "Investing portfolio, watchlist and ratings"),
        ("leaf.fill", "Nutrition tracking, meals and grocery lists"),
        ("target", "Goals, calendar and friends"),
        ("sparkles", "AI help with budgets, receipts and food photos"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: AuthStyle.spacing) {
                AuthHero(title: "PlotLine Plus", subtitle: subtitle, logoSize: 64)
                    .padding(.top, 24)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(features, id: \.1) { icon, text in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon)
                                .foregroundColor(AuthStyle.accent)
                                .frame(width: 22)
                            Text(text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .authCard()

                if let problem = errorMessage ?? membership.purchaseProblem {
                    AuthMessage(text: problem)
                }

                VStack(spacing: 10) {
                    AuthPrimaryButton(title: store.isEligibleForTrial ? "Start free trial" : "Subscribe",
                                      isLoading: inFlight,
                                      isEnabled: store.monthlyProduct != nil) {
                        Task { await run { try await store.purchase() } }
                    }
                    Text(priceTerms)
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                }

                Button("Restore Purchases") {
                    Task { await run { try await store.restore() } }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AuthStyle.accent)
                .disabled(inFlight)

                Text(Self.renewalTerms)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                LegalFooterLinks()

                if isSheet {
                    Button("Not now") { dismiss() }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 24) {
                        Button("Sign out") { session.signOut() }
                        Button("Delete account") { showingDeleteAccount = true }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, AuthStyle.spacing)
            .padding(.bottom, AuthStyle.spacing)
            .animation(.easeOut(duration: 0.2), value: errorMessage)
        }
        .background(Color(.systemBackground))
        .task { await store.loadProducts() }
        .sheet(isPresented: $showingDeleteAccount) {
            DeleteAccountView()
                .environmentObject(session)
        }
    }

    private var subtitle: String {
        if let status = membership.status, status.plan != "none" { return status.summary }
        return "PlotLine is a membership app. Subscribe to use everything."
    }

    private var priceTerms: String {
        guard let product = store.monthlyProduct else { return "Loading prices…" }
        var trial: String?
        if store.isEligibleForTrial, let period = product.subscription?.introductoryOffer?.period {
            trial = Self.periodText(value: period.value, unit: period.unit)
        }
        return Self.priceTerms(price: product.displayPrice, trialPeriod: trial)
    }

    static func priceTerms(price: String, trialPeriod: String?) -> String {
        guard let trialPeriod else { return "\(price)/month" }
        return "\(trialPeriod) free, then \(price)/month"
    }

    static func periodText(value: Int, unit: Product.SubscriptionPeriod.Unit) -> String {
        let name: String
        switch unit {
        case .day: name = "day"
        case .week: name = "week"
        case .month: name = "month"
        case .year: name = "year"
        @unknown default: name = "period"
        }
        return "\(value) \(name)\(value == 1 ? "" : "s")"
    }

    // required next to an auto-renewing subscription's purchase button
    static let renewalTerms = "Payment is charged to your Apple ID. The subscription renews automatically each month unless you cancel at least 24 hours before the current period (or free trial) ends. Manage or cancel it anytime in Settings > Apple ID > Subscriptions."

    private func run(_ action: () async throws -> MembershipStatus?) async {
        guard !inFlight else { return }
        inFlight = true
        errorMessage = nil
        defer { inFlight = false }
        do {
            let status = try await action()
            if let status, !status.active {
                errorMessage = status.summary
            } else if status != nil, isSheet {
                dismiss()
            }
        } catch {
            errorMessage = (error as? PaymentAPIError)?.errorDescription ?? "Something went wrong with the App Store. Please try again."
        }
    }
}

#Preview {
    PaywallView()
        .environmentObject(AuthViewModel())
}
