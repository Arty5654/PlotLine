import SwiftUI
import Foundation

// a lighter blue than the rest of the app, for readability on this screen
private let budgetAccent = Color(red: 0.32, green: 0.67, blue: 0.97)

// ---------- View ----------
private let budgetCommonCategories = CategoryOptions.common

struct BudgetInputView: View {
    // MARK: State
    @State private var budgetItems: [BudgetItem] = []
    @State private var newCategory: String = ""
    @State private var showCategoryPicker = false

    @State private var activeAlert2: ActiveAlert2? = nil
    @State private var budgetingWarnings: String = ""
    
    @State private var userIncome: Double = 0.0
    @State private var userRent: Double = 0.0
    
    @State private var warningsAcknowledged: Bool = false
    @State private var isRegenerating: Bool = false
    @State private var aiLimitMessage: String = ""
    // saving replaces the whole budget, so it waits until the real one has loaded
    @State private var budgetLoaded = false
    /// Regenerate: built like the quiz (saved answers, transactions), checked on the review screen
    @StateObject private var regenModel = BudgetQuizModel()
    @State private var regenReview: RegenReview?
    @State private var regenError: String?
    /// new categories still blank when Save is tapped
    @State private var blankOnSave: [String] = []
    @EnvironmentObject private var calendarVM: CalendarViewModel

    private struct RegenReview: Identifiable {
        let id = UUID()
        let draft: BudgetQuizModel.Draft
        let newCategories: [String]
        let adjustable: Set<String>
    }
    
    // Exclude from progress math (still visible as budget lines)
    private let trackerExclusions: Set<String> = ["401(k)", "401(k) Contribution"]

    private var totalEntered: Double {
        budgetItems
            .filter { !trackerExclusions.contains($0.category) }
            .compactMap { Double($0.amount) }
            .reduce(0, +)
    }
    private var totalAllowance: Double {
        userIncome
    }
    private var remaining: Double { totalAllowance - totalEntered }
    private var progress: Double {
        guard totalAllowance > 0 else { return 0 }
        return min(max(totalEntered / totalAllowance, 0), 1)
    }

    private let username: String = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    var prefilledBudget: [String: Double]? = nil
    
    private static let defaultBudgetCategories: [BudgetItem] = [
        BudgetItem(category: "Rent", amount: ""),
        BudgetItem(category: "Groceries", amount: ""),
        BudgetItem(category: "Subscriptions", amount: ""),
        BudgetItem(category: "Eating Out", amount: ""),
        BudgetItem(category: "Entertainment", amount: ""),
        BudgetItem(category: "Utilities", amount: ""),
        BudgetItem(category: "Savings", amount: ""),
        BudgetItem(category: "Miscellaneous", amount: ""),
        BudgetItem(category: "Transportation", amount: ""),
        BudgetItem(category: "Roth IRA", amount: ""),
        BudgetItem(category: "Car Insurance", amount: ""),
        BudgetItem(category: "Health Insurance", amount: ""),
        BudgetItem(category: "Brokerage", amount: "")
    ]
    
    private var backendType: String { "monthly" }

    private var availableBudgetCategories: [String] {
        let current = Set(budgetItems.map { $0.category.lowercased() })
        return budgetCommonCategories.filter { !current.contains($0.lowercased()) }.sorted()
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                
                // Summary Card
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    HStack {
                        Text("Budget Summary")
                            .font(.headline)
                        Spacer()
                        Text(totalAllowance > 0 ? "\(Int(progress * 100))%" : "—")
                            .font(.subheadline)
                            .foregroundColor(progress >= 1 ? PLColor.danger : PLColor.textSecondary)
                    }
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Monthly Target")
                                .font(.caption)
                                .foregroundColor(PLColor.textSecondary)
                            Text(totalAllowance > 0 ? "$\(totalAllowance, specifier: "%.2f")" : "—")
                                .font(.headline)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Entered")
                                .font(.caption)
                                .foregroundColor(PLColor.textSecondary)
                            Text("$\(totalEntered, specifier: "%.2f")")
                                .font(.headline)
                        }
                    }
                    ProgressView(value: progress)
                    let over = remaining < 0
                    Text(over
                         ? "Over by $\(abs(remaining), specifier: "%.2f")"
                         : "Left: $\(remaining, specifier: "%.2f")")
                        .font(.subheadline)
                        .foregroundColor(over ? PLColor.danger : PLColor.success)
                }
                .plCard()
                
                // Budget rows (no List => consistent, non-zoomed)
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("Lines")
                        .font(.headline)
                    
                    LazyVStack(spacing: PLSpacing.sm) {
                        ForEach($budgetItems) { $item in
                            BudgetRow(
                                item: $item,
                                onRemove: { removeCategory(item: item) },
                                onChangeAmount: { newVal in
                                    item.amount = sanitizeAmount(newVal)
                                }
                            )
                        }
                    }
                    
                    VStack(spacing: PLSpacing.xs) {
                        Menu {
                            ForEach(availableBudgetCategories, id: \.self) { cat in
                                Button(cat) {
                                    // starts blank: type an amount, or Regenerate to estimate it
                                    budgetItems.append(BudgetItem(category: cat, amount: ""))
                                }
                            }
                            Divider()
                            Button("Custom...") { showCategoryPicker = true }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.green)
                                Text("Add Category")
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(PLColor.textSecondary)
                            }
                            .padding(.vertical, 8)
                        }
                        .alert("Custom Category", isPresented: $showCategoryPicker) {
                            TextField("Category name", text: $newCategory)
                            Button("Add") { addCategory() }
                            Button("Cancel", role: .cancel) { newCategory = "" }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("New categories start blank. Type an amount, or tap Regenerate to estimate them from your spending and quiz answers.")
                            .font(.footnote)
                            .foregroundColor(PLColor.textSecondary)
                        if isRegenerating {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.8)
                                Text("Generating updated budget…")
                                    .font(.footnote)
                                    .foregroundColor(budgetAccent)
                            }
                        }
                    }
                }
                .plCard()
                
                // Buttons
                VStack(spacing: PLSpacing.sm) {
                    Button("Save Budget", action: attemptSaveBudget)
                        .buttonStyle(PrimaryButton(color: budgetAccent))
                        .disabled(isRegenerating)
                    Button("Regenerate with New Categories") {
                        Task { await regenerate() }
                    }
                    .disabled(isRegenerating)
                        .buttonStyle(OutlineButton(tint: budgetAccent))
                    HStack(spacing: PLSpacing.sm) {
                        Button("Clear All", action: clearAllBudget)
                            .buttonStyle(PrimaryButton(color: PLColor.danger))
                        Button("Revert to LLM Budget", action: revertToOriginalBudget)
                            .buttonStyle(OutlineButton(tint: PLColor.warning))
                    }
                }
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.lg)
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Monthly Budget")
                    .font(.headline)
            }
        }
        .tint(budgetAccent)
        .alert(item: $activeAlert2) { alertType in
            switch alertType {
            case .warning:
                return Alert(
                    title: Text("⚠️ Budgeting Warning"),
                    message: Text(budgetingWarnings),
                    primaryButton: .default(Text("Proceed Anyway"), action: { saveBudget() }),
                    secondaryButton: .cancel()
                )
            case .aiLimit:
                return Alert(
                    title: Text("Daily AI limit reached"),
                    message: Text(aiLimitMessage),
                    dismissButton: .default(Text("OK"))
                )
            case .saved:
                return Alert(
                    title: Text("Budget Saved"),
                    message: Text("Your monthly budget was saved successfully."),
                    dismissButton: .default(Text("OK"))
                )
            case .cleared:
                return Alert(
                    title: Text("Budget Cleared"),
                    message: Text("Your monthly budget was cleared and defaults restored."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .onAppear {
            if let prefilled = prefilledBudget {
                self.budgetItems = prefilled.map { BudgetItem(category: $0.key, amount: String($0.value)) }
            } else {
                fetchTakeHomeFromLastQuiz()
                fetchBudgetData()
            }
        }
        .sheet(item: $regenReview) { review in
            BudgetReviewView(model: regenModel, draft: review.draft, newCategories: review.newCategories,
                             adjustable: review.adjustable) {
                regenReview = nil // saving refreshes this page (.budgetQuizCompleted)
            }
            .environmentObject(calendarVM)
        }
        .confirmationDialog(blankOnSave.count == 1 ? "\(blankOnSave[0]) has no amount yet" : "\(blankOnSave.count) categories have no amount yet",
                            isPresented: Binding(get: { !blankOnSave.isEmpty }, set: { if !$0 { blankOnSave = [] } }),
                            titleVisibility: .visible) {
            Button("Regenerate to Estimate") { blankOnSave = []; Task { await regenerate() } }
            Button("Save at $0") {
                for index in budgetItems.indices where budgetItems[index].amount.trimmingCharacters(in: .whitespaces).isEmpty {
                    budgetItems[index].amount = "0"
                }
                blankOnSave = []
                attemptSaveBudget()
            }
            Button("Cancel", role: .cancel) { blankOnSave = [] }
        }
        .alert("Couldn't regenerate", isPresented: Binding(get: { regenError != nil }, set: { if !$0 { regenError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(regenError ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .budgetQuizCompleted)) { _ in
            // Refresh budget data after quiz generates new budget
            fetchTakeHomeFromLastQuiz()
            fetchBudgetData()
        }
    }
}

// ---------- Row ----------
private struct BudgetRow: View {
    @Binding var item: BudgetItem
    var onRemove: () -> Void
    var onChangeAmount: (String) -> Void
    
    var body: some View {
        HStack(spacing: PLSpacing.sm) {
            Text(item.category)
                .frame(width: 130, alignment: .leading)
            
            TextField("Amount ($)", text: $item.amount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: item.amount) { _, newValue in
                    onChangeAmount(newValue)
                }
            
            Spacer(minLength: PLSpacing.sm)
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(PLColor.danger)
            }
        }
    }
}

// ---------- Logic (unchanged APIs, tidied a bit) ----------
extension BudgetInputView {
    private func attemptSaveBudget() {
        // blanks: ask whether to estimate them (Regenerate) or save them at $0
        let empties = budgetItems.filter { $0.amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !empties.isEmpty {
            blankOnSave = empties.map(\.category)
            return
        }
        generateBudgetingWarnings()
        if budgetingWarnings.isEmpty {
            saveBudget()
        } else {
            activeAlert2 = .warning
        }
    }
    
    private func addCategory() {
        let trimmed = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !budgetItems.contains(where: { $0.category.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            budgetItems.append(BudgetItem(category: trimmed, amount: ""))
        }
        newCategory = ""
    }
    private func removeCategory(item: BudgetItem) {
        budgetItems.removeAll { $0.id == item.id }
    }
    private func deleteItems(at offsets: IndexSet) {
        budgetItems.remove(atOffsets: offsets)
    }

    /// Like the quiz: the saved answers, their transactions, and the categories on this page. Amounts
    /// already here stay as they are for the AI; blank (new) categories are estimated from real spending.
    /// The review screen shows it before anything is saved, and what to lower if it doesn't fit.
    private func regenerate() async {
        isRegenerating = true
        defer { isRegenerating = false }
        await regenModel.loadSavedQuiz()
        guard regenModel.hasSavedQuiz else {
            regenError = "Take the budget quiz first; regenerating starts from its answers."
            return
        }
        await regenModel.checkBank()
        await regenModel.loadPlan()
        if regenModel.hasCar && regenModel.commute.fuelPrice <= 0 { await regenModel.loadGasPrice() }
        var typed: [String: Double] = [:]
        for item in budgetItems {
            if let value = Double(item.amount.trimmingCharacters(in: .whitespaces)) { typed[item.category] = value }
        }
        let added = budgetItems.map(\.category).filter { typed[$0] == nil }
        regenModel.exactCategories = budgetItems.map(\.category)
        regenModel.newCategories = added
        do {
            let draft = try await regenModel.build(overrides: typed)
            regenReview = RegenReview(draft: draft, newCategories: added, adjustable: Set(typed.keys))
        } catch {
            if let limit = error as? AILimitError {
                aiLimitMessage = limit.message
                activeAlert2 = .aiLimit
            } else {
                regenError = "Please try again in a moment."
            }
        }
    }

    // Keep only digits and a single decimal point
    private func sanitizeAmount(_ input: String) -> String {
        var filtered = input.filter { "0123456789.".contains($0) }
        // enforce a single dot
        if let firstDot = filtered.firstIndex(of: ".") {
            let afterDot = filtered.index(after: firstDot)
            let remainder = filtered[afterDot...].replacingOccurrences(of: ".", with: "")
            filtered = String(filtered[..<afterDot]) + remainder
        }
        return filtered
    }
    
    private func fetchBudgetData() {
        let urlString = "\(BackendConfig.baseURLString)/api/budget/\(username)/\(backendType)"
        guard let url = URL(string: urlString) else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        URLSession.shared.dataTask(with: req) { data, response, error in
            // no budget yet: start from the default categories
            let status = (response as? HTTPURLResponse)?.statusCode
            if error == nil, status == 404 || (status.map { (200...299).contains($0) } == true && (data?.isEmpty ?? true)) {
                DispatchQueue.main.async {
                    self.budgetItems = Self.defaultBudgetCategories
                    self.budgetLoaded = true
                }
                return
            }
            if AppBanner.reportIfFailed("load your budget", data, response, error, retry: { fetchBudgetData() }) { return }
            do {
                let decoded = try JSONDecoder().decode(BudgetResponse.self, from: data ?? Data())
                let filtered = decoded.budget
                    .filter { !self.is401kKey($0.key) }
                    .map { BudgetItem(category: $0.key, amount: String($0.value)) }
                DispatchQueue.main.async {
                    self.budgetItems = filtered
                    self.budgetLoaded = true
                }
            } catch {
                AppBanner.report("load your budget", error, retry: { fetchBudgetData() })
            }
        }.resume()
    }
    
    private func fetchIncomeData() {
        let urlString = "\(BackendConfig.baseURLString)/api/income/\(username)"
        guard let url = URL(string: urlString) else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error { print("❌ income:", error.localizedDescription); return }
            guard let data = data, !data.isEmpty else { return }
            do {
                let decoded = try JSONDecoder().decode(IncomeResponse.self, from: data)
                DispatchQueue.main.async {
                    self.userIncome = decoded.income
                    self.userRent = decoded.rent
                }
            } catch { print("❌ decode income:", error) }
        }.resume()
    }
    
    private func saveBudget() {
        guard budgetLoaded else {
            AppBanner.shared.show("Your budget didn't load, so saving now could erase it.", retry: { fetchBudgetData() })
            return
        }
        let budgetDict = budgetItems.reduce(into: [String: Double]()) { result, item in
            guard !is401kKey(item.category) else { return }
            if let val = Double(item.amount) { result[item.category] = val }
        }
        let payload: [String: Any] = [
            "username": username,
            "type": backendType,
            "budget": budgetDict
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: URL(string: "\(BackendConfig.baseURLString)/api/budget")!)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = json
        URLSession.shared.dataTask(with: req) { data, resp, err in
            // on failure the amounts stay as typed, ready to save again
            if AppBanner.reportIfFailed("save your budget", data, resp, err, retry: { saveBudget() }) { return }
            DispatchQueue.main.async {
                self.activeAlert2 = .saved
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }.resume()
    }
    
    private func generateBudgetingWarnings() {
        budgetingWarnings = ""
        let rent = Double(budgetItems.first(where: { $0.category == "Rent" })?.amount ?? "0") ?? 0
        let savings = Double(budgetItems.first(where: { $0.category == "Savings" })?.amount ?? "0") ?? 0
        let eatingOut = Double(budgetItems.first(where: { $0.category == "Eating Out" })?.amount ?? "0") ?? 0
        
        if userIncome > 0 {
            if rent > userIncome * 0.3   { budgetingWarnings += "• Rent exceeds 30% of monthly income.\n" }
            if savings < userIncome * 0.1 { budgetingWarnings += "• Savings are below 10% of income.\n" }
            if totalAllowance > 0 && totalEntered > totalAllowance {
                budgetingWarnings += "• Your monthly budget is over by $\(String(format: "%.2f", totalEntered - totalAllowance)).\n"
            }
        }
        if eatingOut > 200 { budgetingWarnings += "• High eating out cost—consider cooking at home.\n" }
    }
    
    private func clearAllBudget() {
        let urlString = "\(BackendConfig.baseURLString)/api/budget/\(username)/\(backendType)"
        guard let url = URL(string: urlString) else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: req) { data, response, error in
            if AppBanner.reportIfFailed("clear your budget", data, response, error, retry: { clearAllBudget() }) { return }
            DispatchQueue.main.async {
                self.budgetItems = Self.defaultBudgetCategories
                self.budgetLoaded = true
                self.activeAlert2 = .cleared
            }
        }.resume()
    }
    
    private func revertToOriginalBudget() {
        let urlString = "\(BackendConfig.baseURLString)/api/llm/budget/revert/\(username)/\(backendType)"
        guard let url = URL(string: urlString) else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req) { data, response, error in
            if AppBanner.reportIfFailed("go back to your original budget", data, response, error, retry: { revertToOriginalBudget() }) { return }
            DispatchQueue.main.async { self.fetchBudgetData() }
        }.resume()
    }

    private func parseNumber(_ any: Any?) -> Double? {
        guard let any = any else { return nil }
        let s = String(describing: any)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(s)
    }
    
    private func is401kKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return lowered.contains("401k")
            || lowered.contains("401(k)")
            || lowered == "401k contribution"
            || lowered == "401(k) contribution"
    }
    
    private func fetchTakeHomeFromLastQuiz() {
        let url = URL(string: "\(BackendConfig.baseURLString)/api/llm/budget/last/\(username)")!
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error { print("quiz err:", error.localizedDescription); self.fetchIncomeData(); return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data, !data.isEmpty else {
                self.fetchIncomeData(); return
            }
            do {
                if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let net = parseNumber(obj["monthlyNet"]) {
                    DispatchQueue.main.async { self.userIncome = net }
                } else {
                    self.fetchIncomeData()
                }
            } catch {
                print("parse quiz json:", error)
                self.fetchIncomeData()
            }
        }.resume()
    }
}

// ---------- Alert enum (your existing model) ----------
fileprivate enum ActiveAlert2: Identifiable {
    case saved, cleared, warning, aiLimit
    var id: String {
        switch self {
        case .saved: return "saved"
        case .cleared: return "cleared"
        case .warning: return "warning"
        case .aiLimit: return "aiLimit"
        }
    }
}

struct IncomeResponse: Codable {
    let username: String
    let income: Double
    let rent: Double
}
