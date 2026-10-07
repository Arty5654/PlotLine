import SwiftUI
import StoreKit

// Membership & Billing (from Profile): your plan, managing the App Store subscription, restoring
struct PaymentView: View {
    @ObservedObject private var membership = MembershipManager.shared
    @ObservedObject private var store = StoreKitManager.shared
    @State private var inFlight = false
    @State private var message: String?
    @State private var showManageSubscriptions = false
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                planCard
                actionButtons
                footer
            }
            .padding(20)
        }
        .navigationTitle("Membership")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await membership.refresh()
            await store.loadProducts()
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .sheet(isPresented: $showPaywall) {
            PaywallView(isSheet: true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PlotLine Plus")
                .font(.title2).bold()
            Text("A free week when you join, then your first month free when you subscribe. The first 1,000 accounts are free forever.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planName: String {
        switch membership.status?.plan {
        case "lifetime": return "Lifetime"
        case "free-week": return "Free week"
        case "trial": return "Free month"
        case "monthly": return "Monthly"
        case .some: return "No membership"
        case nil: return "Loading…"
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(planName)
                    .font(.headline)
                Spacer()
                if membership.status?.isLifetime == true {
                    Text("Free")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                } else if let price = store.monthlyProduct?.displayPrice {
                    Text("\(price)/mo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                }
            }
            if let status = membership.status {
                Text(status.summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let message {
                Text(message).font(.footnote).foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            if membership.status?.isSubscribed == true {
                Button {
                    showManageSubscriptions = true
                } label: {
                    Text("Manage subscription")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else if let status = membership.status, !status.isLifetime {
                Button {
                    showPaywall = true
                } label: {
                    Text("Subscribe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Restore Purchases") {
                Task { await restore() }
            }
            .buttonStyle(.bordered)
            .disabled(inFlight)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Billing")
                .font(.headline)
            Text(PaywallView.renewalTerms)
            Text("Deleting your PlotLine account doesn't cancel the App Store subscription.")
        }
        .font(.footnote)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func restore() async {
        inFlight = true
        message = nil
        defer { inFlight = false }
        do {
            _ = try await store.restore()
        } catch {
            message = (error as? PaymentAPIError)?.errorDescription ?? "Couldn't restore purchases. Please try again."
        }
    }
}

#Preview {
    NavigationStack { PaymentView() }
}
