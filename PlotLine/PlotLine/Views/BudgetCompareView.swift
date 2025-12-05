import SwiftUI

private enum BCColor {
    static let surface = Color(.secondarySystemBackground)
    static let border = Color.black.opacity(0.06)
    static let accent = Color.blue
    static let textSecondary = Color.secondary
    static let danger = Color.red
    static let success = Color.green
}
private enum BCSpacing {
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}
private enum BCRadius { static let md: CGFloat = 12 }

private struct Card: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(BCSpacing.md)
            .background(BCColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BCRadius.md))
            .overlay(RoundedRectangle(cornerRadius: BCRadius.md).stroke(BCColor.border))
    }
}
private extension View { func bcCard() -> some View { modifier(Card()) } }

struct BudgetCompareView: View {
    @State private var currentIncome: String = ""
    @State private var newIncome: String = ""
    @State private var newCity: String = ""
    @State private var newState: String = ""
    
    @State private var currentBudget: [String: Double] = [:]
    @State private var proposedBudget: [String: Double] = [:]
    @State private var isLoading = false
    @State private var error: String?
    @State private var successMessage: String?
    @State private var quizPayload: [String: Any] = [:]
    
    private let excludedCats: Set<String> = ["401(k)", "401(k) Contribution"]
    private var visibleCurrent: [String: Double] {
        currentBudget.filter { !excludedCats.contains($0.key) }
    }
    private var visibleProposed: [String: Double] {
        proposedBudget.filter { !excludedCats.contains($0.key) }
    }


    
    private var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    private var totalCurrent: Double { visibleCurrent.values.reduce(0, +) }
    private var totalProposed: Double { visibleProposed.values.reduce(0, +) }
    
    var body: some View {
        ScrollView {
            VStack(spacing: BCSpacing.lg) {
                header
                inputs
                comparisonCard
                applyCard
            }
            .padding(BCSpacing.lg)
        }
        .navigationTitle("Compare Budgets")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await loadInitialData() } }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plan a Move or Raise")
                .font(.title3).bold()
            Text("Compare your current budget to a projected one with a new income and/or location.")
                .font(.subheadline)
                .foregroundColor(BCColor.textSecondary)
        }
    }
    
    private var inputs: some View {
        VStack(alignment: .leading, spacing: BCSpacing.md) {
            Text("Inputs").font(.headline)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Current Income").font(.caption).foregroundColor(BCColor.textSecondary)
                    TextField("e.g., 75000", text: $currentIncome)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading) {
                    Text("New Income").font(.caption).foregroundColor(BCColor.textSecondary)
                    TextField("e.g., 90000", text: $newIncome)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Location change (optional)").font(.caption).foregroundColor(BCColor.textSecondary)
                TextField("City", text: $newCity)
                    .textFieldStyle(.roundedBorder)
                TextField("State (e.g., CA)", text: $newState)
                    .textFieldStyle(.roundedBorder)
            }
            
            if let err = error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(BCColor.danger)
                    Text(err).foregroundColor(.primary)
                }.font(.footnote)
            }
            
            Button {
                Task { await recomputeProposal() }
            } label: {
                Text("Update Projection")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || currentBudget.isEmpty)
        }
        .bcCard()
    }
    
    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: BCSpacing.md) {
            Text("Comparison").font(.headline)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Current").font(.caption).foregroundColor(BCColor.textSecondary)
                    Text(currency(totalCurrent)).font(.headline)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Proposed").font(.caption).foregroundColor(BCColor.textSecondary)
                    Text(currency(totalProposed)).font(.headline)
                        .foregroundColor(totalProposed > totalCurrent ? BCColor.danger : BCColor.success)
                }
            }
            
            Divider()
            
            ForEach(sortedCategories(), id: \.self) { cat in
                let cur = visibleCurrent[cat] ?? 0
                let prop = visibleProposed[cat] ?? 0
                HStack {
                    Text(cat)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(currency(cur)).font(.caption).foregroundColor(BCColor.textSecondary)
                        Text(currency(prop)).font(.headline)
                    }
                }
            }
        }
        .bcCard()
    }
    
    private var applyCard: some View {
        VStack(alignment: .leading, spacing: BCSpacing.sm) {
            Text("Apply this budget?")
                .font(.headline)
            if let successMessage {
                Text(successMessage)
                    .font(.footnote)
                    .foregroundColor(BCColor.success)
            }
            Button {
                Task { await applyBudget() }
            } label: {
                Text("Replace my budget with proposed")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(proposedBudget.isEmpty || isLoading)
        }
        .bcCard()
    }
    
    // MARK: - Helpers
    private func currency(_ v: Double) -> String {
        String(format: "$%.0f", v)
    }
    
    private func sortedCategories() -> [String] {
        Array(Set(visibleCurrent.keys).union(visibleProposed.keys)).sorted()
    }
    
    private func recomputeProposal() async {
        await MainActor.run {
            self.error = nil
            self.isLoading = true
        }
        defer {
            Task { await MainActor.run { self.isLoading = false } }
        }

        guard let baseIncome = Double(currentIncome) else {
            await MainActor.run { self.error = "Current income missing or invalid." }
            return
        }
        let targetIncome = Double(newIncome) ?? baseIncome

        var payload = quizPayload
        payload["username"] = username
        payload["yearlyIncome"] = targetIncome
        if !newCity.trimmingCharacters(in: .whitespaces).isEmpty { payload["city"] = newCity }
        if !newState.trimmingCharacters(in: .whitespaces).isEmpty { payload["state"] = newState }

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: "http://localhost:8080/api/llm/budget") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        do {
            let (respData, _) = try await URLSession.shared.data(for: req)
            if let decoded = try? JSONDecoder().decode([String: Double].self, from: respData) {
                await MainActor.run {
                    self.proposedBudget = decoded.filter { !excludedCats.contains($0.key) }
                }
            } else {
                await MainActor.run { self.error = "Could not generate proposed budget." }
            }
        } catch {
            await MainActor.run { self.error = "Could not generate proposed budget." }
        }
    }
    
    private func loadInitialData() async {
        async let current = loadCurrentBudget()
        async let quiz = loadQuizData()
        _ = await (current, quiz)
        await recomputeProposal()
    }
    
    private func loadCurrentBudget() async {
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "http://localhost:8080/api/budget/\(username)/monthly") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            if let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let budget = decoded["budget"] as? [String: Double] {

                // Update state on the main actor
                await MainActor.run {
                    self.currentBudget = budget.filter { !excludedCats.contains($0.key) }
                }

                // Now that state is set, run the async recompute
                await recomputeProposal()
            }
        } catch {
            await MainActor.run { self.error = "Could not load current budget." }
        }
    }

    
    private func loadQuizData() async {
        guard let url = URL(string: "http://localhost:8080/api/llm/budget/last/\(username)") else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                await MainActor.run {
                    self.quizPayload = dict
                    if let inc = dict["yearlyIncome"] {
                        self.currentIncome = String(describing: inc)
                        if self.newIncome.isEmpty { self.newIncome = self.currentIncome }
                    }
                    if let city = dict["city"] as? String { self.newCity = city }
                    if let state = dict["state"] as? String { self.newState = state }
                }
            }
        } catch { }
    }
    
    private func applyBudget() async {
        isLoading = true
        defer { isLoading = false }
        guard let url = URL(string: "http://localhost:8080/api/budget") else { return }
        let cleanedMonthly = proposedBudget.filter { !excludedCats.contains($0.key) }
        let weeklyBudget = cleanedMonthly.mapValues { $0 / 4.0 }

        let payload: [String: Any] = [
            "username": username,
            "type": "monthly",
            "budget": cleanedMonthly
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        
        do {
            _ = try await URLSession.shared.data(for: req)
            // also save weekly scaled version
            let weeklyBudget = proposedBudget.mapValues { $0 / 4.0 }
            let weeklyPayload: [String: Any] = [
                "username": username,
                "type": "weekly",
                "budget": weeklyBudget
            ]
            if let wdata = try? JSONSerialization.data(withJSONObject: weeklyPayload) {
                var wreq = URLRequest(url: url)
                wreq.httpMethod = "POST"
                wreq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                wreq.httpBody = wdata
                _ = try? await URLSession.shared.data(for: wreq)
            }
            await MainActor.run { self.successMessage = "Budget replaced successfully." }
        } catch {
            await MainActor.run { self.error = "Could not save budget." }
        }
    }
}
