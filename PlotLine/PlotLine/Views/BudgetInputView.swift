import SwiftUI
import Foundation

// ---------- Design tokens (match WeeklyMonthlyCostView) ----------
private enum PLColor {
    static let surface        = Color(.secondarySystemBackground)
    static let cardBorder     = Color.black.opacity(0.06)
    static let textPrimary    = Color.primary
    static let textSecondary  = Color.secondary
    static let accent         = Color(red: 0.32, green: 0.67, blue: 0.97) // lighter accent to improve readability
    static let success        = Color.green
    static let danger         = Color.red
    static let warning        = Color.orange
}
private enum PLSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}
private enum PLRadius {
    static let md: CGFloat = 12
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PLSpacing.md)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: PLRadius.md)
                    .stroke(PLColor.cardBorder)
            )
    }
}
private extension View { func plCard() -> some View { modifier(CardModifier()) } }

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(PLColor.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}
private struct OutlinedButton: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: PLRadius.md)
                    .stroke(tint.opacity(configuration.isPressed ? 0.6 : 1))
            )
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}
private struct DestructiveButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(PLColor.danger.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}

// ---------- View ----------
// Common categories available across budget views
private let budgetCommonCategories = [
    // Defaults
    "Rent", "Groceries", "Subscriptions", "Eating Out",
    "Entertainment", "Utilities", "Savings", "Miscellaneous",
    "Transportation", "Roth IRA", "Car Insurance",
    "Health Insurance", "Brokerage",
    // Additional common
    "Gas", "Phone", "Internet", "Gym", "Clothing",
    "Personal Care", "Education", "Childcare", "Pet Care",
    "Home Maintenance", "Gifts", "Donations", "Travel",
    "Baby Supplies", "Hobbies", "Shopping", "Coffee",
    "Alcohol & Bars", "Home Decor", "Electronics",
    "Medical", "Dental", "Vision", "Therapy",
    "Parking", "Tolls", "Laundry", "Haircuts",
    "Streaming Services", "Gaming", "Music", "Books"
]

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
                
                // Header
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("Create Your Monthly Budget")
                        .font(.headline).bold()
                }
                .plCard()
                
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
                                    budgetItems.append(BudgetItem(category: cat, amount: ""))
                                    regenerateBudgetFromUI(auto: true)
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
                        Text("Tip: Leave a new category blank to auto-generate amounts. If you enter a number, it won’t regenerate unless you tap Regenerate.")
                            .font(.footnote)
                            .foregroundColor(PLColor.textSecondary)
                        if isRegenerating {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.8)
                                Text("Generating updated budget…")
                                    .font(.footnote)
                                    .foregroundColor(PLColor.accent)
                            }
                        }
                    }
                }
                .plCard()
                
                // Buttons
                VStack(spacing: PLSpacing.sm) {
                    Button("Save Budget", action: attemptSaveBudget)
                        .buttonStyle(PrimaryButton())
                        .disabled(isRegenerating)
                    Button("Regenerate with New Categories") {
                        regenerateBudgetFromUI()
                    }
                        .buttonStyle(OutlinedButton(tint: PLColor.accent))
                    HStack(spacing: PLSpacing.sm) {
                        Button("Clear All", action: clearAllBudget)
                            .buttonStyle(DestructiveButton())
                        Button("Revert to LLM Budget", action: revertToOriginalBudget)
                            .buttonStyle(OutlinedButton(tint: PLColor.warning))
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
        .tint(PLColor.accent)
        .alert(item: $activeAlert2) { alertType in
            switch alertType {
            case .warning:
                return Alert(
                    title: Text("⚠️ Budgeting Warning"),
                    message: Text(budgetingWarnings),
                    primaryButton: .default(Text("Proceed Anyway"), action: { saveBudget() }),
                    secondaryButton: .cancel()
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
                .onChange(of: item.amount) { newValue in
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
        // If any blanks, regenerate to fill them before saving
        let empties = budgetItems.filter { $0.amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !empties.isEmpty {
            regenerateBudgetFromUI()
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
            // If the new field is blank (default), auto-regenerate to include it
            regenerateBudgetFromUI(auto: true)
        }
        newCategory = ""
    }
    private func removeCategory(item: BudgetItem) {
        budgetItems.removeAll { $0.id == item.id }
    }
    private func deleteItems(at offsets: IndexSet) {
        budgetItems.remove(atOffsets: offsets)
    }

    // Call backend to regenerate using last quiz + current categories/known costs
    private func regenerateBudgetFromUI(auto: Bool = false) {
        isRegenerating = true
        let cats = budgetItems.map { $0.category }
        var known: [String: Double] = [:]
        for item in budgetItems {
            if let v = Double(item.amount) {
                known[item.category] = v
            }
        }
        let payload: [String: Any] = [
            "username": username,
            "categories": cats,
            "knownCosts": known
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: URL(string: "\(BackendConfig.baseURLString)/api/llm/budget/regen")!)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data = data,
                  let decoded = try? JSONDecoder().decode([String: Double].self, from: data)
            else {
                DispatchQueue.main.async { self.isRegenerating = false }
                return
            }
            DispatchQueue.main.async {
                // Ensure all requested categories are present (LLM may omit)
                var merged: [BudgetItem] = []
                for cat in cats {
                    if let val = decoded[cat] {
                        merged.append(BudgetItem(category: cat, amount: String(format: "%.2f", val)))
                    } else {
                        // Keep existing amount (likely blank) to let user fill or regen later
                        if let existing = self.budgetItems.first(where: { $0.category == cat }) {
                            merged.append(existing)
                        } else {
                            merged.append(BudgetItem(category: cat, amount: ""))
                        }
                    }
                }
                // Include any extra keys returned by the backend that weren't in cats (except 401k)
                let extra = decoded.filter { key, _ in !cats.contains(key) && !is401kKey(key) }
                for (k,v) in extra {
                    merged.append(BudgetItem(category: k, amount: String(format: "%.2f", v)))
                }
                self.budgetItems = merged
                self.isRegenerating = false
            }
        }.resume()
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
        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error {
                print("❌ fetch budget:", error.localizedDescription)
                DispatchQueue.main.async { self.budgetItems = Self.defaultBudgetCategories }
                return
            }
            guard let data = data, !data.isEmpty else {
                DispatchQueue.main.async { self.budgetItems = Self.defaultBudgetCategories }
                return
            }
            do {
                let decoded = try JSONDecoder().decode(BudgetResponse.self, from: data)
                let filtered = decoded.budget
                    .filter { !self.is401kKey($0.key) }
                    .map { BudgetItem(category: $0.key, amount: String($0.value)) }
                DispatchQueue.main.async {
                    self.budgetItems = filtered
                }
            } catch {
                print("❌ decode budget:", error)
                DispatchQueue.main.async { self.budgetItems = Self.defaultBudgetCategories }
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
        URLSession.shared.dataTask(with: req) { _, resp, err in
            guard err == nil else { return }
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
        URLSession.shared.dataTask(with: req) { _,_,_ in
            DispatchQueue.main.async {
                self.budgetItems = Self.defaultBudgetCategories
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
        URLSession.shared.dataTask(with: req) { _,_,_ in
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
    case saved, cleared, warning
    var id: String {
        switch self {
        case .saved: return "saved"
        case .cleared: return "cleared"
        case .warning: return "warning"
        }
    }
}

struct IncomeResponse: Codable {
    let username: String
    let income: Double
    let rent: Double
}
