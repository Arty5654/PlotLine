import SwiftUI

struct PaymentView: View {
    @StateObject private var storeKit = StoreKitManager.shared
    @State private var status: SubscriptionStatus?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                planCardFromStoreKit
                actionButtons
                footer
            }
            .padding(20)
        }
        .navigationTitle("Membership")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                isLoading = true
                defer { isLoading = false }
                do {
                    try await storeKit.loadProducts()
                    try? await storeKit.refreshEntitlements()
                    status = try? await PaymentAPI.fetchStatus(username: username) // optional: reflect server status too
                } catch {
                    self.error = "Could not load membership."
                }
            }
        }
    }

    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    private var planCardFromStoreKit: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text((storeKit.plan ?? "None").capitalized)
                    .font(.headline)
                Spacer()
                Text(priceLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
            }
            if storeKit.plan == "trial", let d = storeKit.trialEndsAt {
                Text("Trial ends on \(d.formatted(date: .abbreviated, time: .omitted))")
                    .font(.footnote).foregroundColor(.secondary)
            }
            if let e = error {
                Text(e).font(.footnote).foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var priceLabel: String {
        if storeKit.plan == "lifetime" { return "Free" } // your comp plan
        if let p = storeKit.monthlyProduct?.displayPrice { return "\(p)/mo" }
        return "$5/mo"
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    do { try await storeKit.purchaseMonthly() }
                    catch { self.error = "Purchase failed or cancelled." }
                }
            } label: {
                Text(primaryCTA)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || storeKit.plan == "lifetime")

            Button("Restore Purchases") {
                Task { await storeKit.restore() }
            }
            .buttonStyle(.bordered)
        }
    }

    private var primaryCTA: String {
        if storeKit.plan == "lifetime" { return "Lifetime unlocked" }
        if storeKit.plan == "trial" { return "Continue free trial" }
        return "Start free trial – then $5/mo"
    }

    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PlotLine Plus")
                .font(.title2).bold()
            Text("30-day free trial, then $5/month. First 1,000 users get lifetime free.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private func planCard(_ status: SubscriptionStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(status.plan.capitalized)
                    .font(.headline)
                Spacer()
                Text(status.monthlyPrice == 0 ? "Free" : "$\(status.monthlyPrice, specifier: "%.0f")/mo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
            }
            if let msg = status.message {
                Text(msg)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let grace = status.graceEndsAt, status.plan == "grace" {
                Text("Free month ends on \(grace)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if let trial = status.trialEndsAt {
                Text("Trial ends on \(trial)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var actionButton: some View {
        Button {
            if shouldStartTrial {
                Task { await claim() }
            } else if canCancel {
                Task { await cancel() }
            }
        } label: {
            Text(buttonTitle)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading || status?.plan == "lifetime")
    }
    
    private var buttonTitle: String {
        if status?.plan == "lifetime" { return "Lifetime unlocked" }
        if canCancel { return "Cancel subscription" }
        if shouldStartTrial { return "Start free trial" }
        return "Activate offer"
    }
    
    private func errorView(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            Text(text).foregroundColor(.primary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Billing summary")
                .font(.headline)
            Text("• 30-day free trial, cancel anytime before it ends")
            Text("• $5/month after trial (unless lifetime free)")
            Text("• Charges handled securely via your App Store/Play billing (coming soon)")
        }
        .font(.footnote)
        .foregroundColor(.secondary)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func loadStatus() async {
        isLoading = true
        defer { isLoading = false }
        do {
            status = try await PaymentAPI.fetchStatus(username: username)
            error = nil
        } catch {
            self.error = "Could not load membership. Please try again."
        }
    }
    
    private func claim() async {
        isLoading = true
        defer { isLoading = false }
        do {
            status = try await PaymentAPI.claim(username: username)
            error = nil
        } catch {
            self.error = "Could not activate offer. Please try again."
        }
    }

    private func cancel() async {
        isLoading = true
        defer { isLoading = false }
        do {
            status = try await PaymentAPI.cancel(username: username)
            error = nil
        } catch {
            self.error = "Could not cancel. Please try again."
        }
    }
    
    private var shouldStartTrial: Bool {
        guard let plan = status?.plan else { return true }
        return plan == "grace" || plan == "needs-trial" || plan == "expired"
    }
    
    private var canCancel: Bool {
        guard let plan = status?.plan else { return false }
        return plan == "trial" || plan == "paid"
    }
}

#Preview {
    NavigationStack { PaymentView() }
}
