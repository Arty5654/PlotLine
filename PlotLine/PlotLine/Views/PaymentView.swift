import SwiftUI

struct PaymentView: View {
    @State private var status: SubscriptionStatus?
    @State private var isLoading = false
    @State private var error: String?
    
    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if let status {
                    planCard(status)
                } else if isLoading {
                    ProgressView("Loading…")
                } else if let error {
                    errorView(error)
                }
                actionButton
                footer
            }
            .padding(20)
        }
        .navigationTitle("Membership")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await loadStatus() } }
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
            Task { await claim() }
        } label: {
            Text(buttonTitle)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading || status?.plan == "lifetime")
    }
    
    private var buttonTitle: String {
        if status?.plan == "lifetime" { return "Lifetime unlocked" }
        if status?.plan == "trial" { return "Activate free trial" }
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
}

#Preview {
    NavigationStack { PaymentView() }
}
