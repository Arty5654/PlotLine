//
//  BudgetQuizView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 4/16/25.
//

import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

// ---------- Design tokens to match other screens ----------
private enum PLColor {
    static let surface        = Color(.secondarySystemBackground)
    static let cardBorder     = Color.black.opacity(0.06)
    static let textPrimary    = Color.primary
    static let textSecondary  = Color.secondary
    static let accent         = Color.blue
    static let danger         = Color.red
    static let warning        = Color.orange
}

extension Notification.Name {
    static let budgetQuizCompleted = Notification.Name("budgetQuizCompleted")
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
private struct OutlineButton: ButtonStyle {
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
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}

struct BudgetQuizView: View {
    static let defaultCategories = [
        "Rent", "Groceries", "Subscriptions", "Eating Out",
        "Entertainment", "Utilities", "Savings", "Miscellaneous",
        "Transportation", "Roth IRA", "Car Insurance",
        "Health Insurance", "Brokerage"
    ]
    
    let US_STATES: [USState] = [
        .init(name: "Alabama", code: "AL"), .init(name: "Alaska", code: "AK"),
        .init(name: "Arizona", code: "AZ"), .init(name: "Arkansas", code: "AR"),
        .init(name: "California", code: "CA"), .init(name: "Colorado", code: "CO"),
        .init(name: "Connecticut", code: "CT"), .init(name: "Delaware", code: "DE"),
        .init(name: "District of Columbia", code: "DC"), .init(name: "Florida", code: "FL"),
        .init(name: "Georgia", code: "GA"), .init(name: "Hawaii", code: "HI"),
        .init(name: "Idaho", code: "ID"), .init(name: "Illinois", code: "IL"),
        .init(name: "Indiana", code: "IN"), .init(name: "Iowa", code: "IA"),
        .init(name: "Kansas", code: "KS"), .init(name: "Kentucky", code: "KY"),
        .init(name: "Louisiana", code: "LA"), .init(name: "Maine", code: "ME"),
        .init(name: "Maryland", code: "MD"), .init(name: "Massachusetts", code: "MA"),
        .init(name: "Michigan", code: "MI"), .init(name: "Minnesota", code: "MN"),
        .init(name: "Mississippi", code: "MS"), .init(name: "Missouri", code: "MO"),
        .init(name: "Montana", code: "MT"), .init(name: "Nebraska", code: "NE"),
        .init(name: "Nevada", code: "NV"), .init(name: "New Hampshire", code: "NH"),
        .init(name: "New Jersey", code: "NJ"), .init(name: "New Mexico", code: "NM"),
        .init(name: "New York", code: "NY"), .init(name: "North Carolina", code: "NC"),
        .init(name: "North Dakota", code: "ND"), .init(name: "Ohio", code: "OH"),
        .init(name: "Oklahoma", code: "OK"), .init(name: "Oregon", code: "OR"),
        .init(name: "Pennsylvania", code: "PA"), .init(name: "Rhode Island", code: "RI"),
        .init(name: "South Carolina", code: "SC"), .init(name: "South Dakota", code: "SD"),
        .init(name: "Tennessee", code: "TN"), .init(name: "Texas", code: "TX"),
        .init(name: "Utah", code: "UT"), .init(name: "Vermont", code: "VT"),
        .init(name: "Virginia", code: "VA"), .init(name: "Washington", code: "WA"),
        .init(name: "West Virginia", code: "WV"), .init(name: "Wisconsin", code: "WI"),
        .init(name: "Wyoming", code: "WY")
    ]
    
    @State private var allCategories: [String] = defaultCategories
    @State private var yearlyIncome = ""
    @State private var retirement = ""
    @State private var retirementTip = false
    @State private var numberOfDependents = ""
    
    @State private var primaryGoal = "Balanced"
    @State private var savingsPriority = "Medium"
    @State private var housingSituation = ""
    @State private var carOwnership = "One Car"
    @State private var eatingOutFrequency = "Sometimes"


    
    // Debt
    @State private var hasDebt = false
    @State private var debts: [DebtItem] = []
    var debtEntriesValid: Bool {
        guard hasDebt else { return true }
        return debts.allSatisfy { !$0.name.isEmpty && Double($0.principal) != nil }
    }
    
    // Location
    @State private var city = ""
    @State private var state = ""
    @State private var manualCity = ""
    @State private var manualState = ""
    @State private var useDeviceLocation = true
    
    // Style
    @State private var spendingStyle = "Medium"
    
    // Categories & known costs
    @State private var selectedCategories: Set<String> = Set(defaultCategories)
    @State private var customCategory = ""
    @State private var knownCosts: [String: String] = [:]
    
    // Loading / errors
    @State private var isLoading = false
    @State private var showError = false
    @State private var showLoadingSheet = false
    
    // 401K dups, dont need to show it since the budet already accounts for it
    private let trackerExclusions: Set<String> = [
        "401(k)", "401k", "401(k) Contribution", "401k Contribution"
    ]
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var locationManager = LocationManager()
    
    var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }
    
    private func optionRow(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
        }
        .contentShape(Rectangle())
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: PLSpacing.lg) {
                
                // Header
//                VStack(alignment: .leading, spacing: PLSpacing.sm) {
//                    Text("Budget Quiz")
//                        .font(.headline).bold()
//                    Text("Tell us a bit about you so we can generate a smart starting budget.")
//                        .font(.subheadline)
//                        .foregroundColor(PLColor.textSecondary)
//                }
//                .plCard()
                
                // Income & household
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("Income & Household")
                        .font(.headline)
                    
                    TextField("Yearly Income ($)", text: $yearlyIncome)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: yearlyIncome) { v in yearlyIncome = v.filter { "0123456789.".contains($0) } }
                    
                    HStack(spacing: PLSpacing.sm) {
                        TextField("401(k) Contribution (%)", text: $retirement)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: retirement) { v in retirement = v.filter { "0123456789.".contains($0) } }
                        Button {
                            retirementTip = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .imageScale(.medium)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $retirementTip, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("401(k) Contribution Tip").font(.headline)
                                Text("A common target is 10–15% of your gross income. At minimum, try to capture your employer match.")
                                    .font(.subheadline)
                                    .foregroundColor(PLColor.textSecondary)
                            }
                            .padding()
                            .frame(maxWidth: 320)
                        }
                    }
                    
                    TextField("Number of Dependents", text: $numberOfDependents)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: numberOfDependents) { v in numberOfDependents = v.filter { "0123456789".contains($0) } }
                }
                .plCard()
                
                // Debt
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("Debt")
                        .font(.headline)
                    Toggle("I have debt to payoff", isOn: $hasDebt)
                        .onChange(of: hasDebt) { on in if !on { debts.removeAll() } }
                    
                    if hasDebt {
                        LazyVStack(spacing: PLSpacing.sm) {
                            ForEach($debts) { $debt in
                                DebtRow(debt: $debt)
                                    .plCard()
                            }
                            .onDelete { idx in debts.remove(atOffsets: idx) }
                            
                            Button {
                                debts.append(DebtItem())
                            } label: {
                                Label("Add Debt", systemImage: "plus.circle.fill")
                                    .labelStyle(.titleAndIcon)
                            }
                            .tint(.green)
                        }
                    }
                }
                .plCard()
                
                // Spending style
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("Spending Style")
                        .font(.headline)
                    Picker("Spending Style", selection: $spendingStyle) {
                        Text("Low").tag("Low")
                        Text("Medium").tag("Medium")
                        Text("High").tag("High")
                    }
                    .pickerStyle(.segmented)
                }
                .plCard()
                
                // Goals & Priorities
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("Goals & Priorities")
                        .font(.headline)

                    Picker(selection: $primaryGoal) {
                        optionRow("Build an emergency fund", isSelected: primaryGoal == "Emergency Fund").tag("Emergency Fund")
                        optionRow("Pay down debt", isSelected: primaryGoal == "Pay Down Debt").tag("Pay Down Debt")
                        optionRow("Save for a big purchase", isSelected: primaryGoal == "Big Purchase").tag("Big Purchase")
                        optionRow("Maximize investing", isSelected: primaryGoal == "Maximize Investing").tag("Maximize Investing")
                        optionRow("Balance everything", isSelected: primaryGoal == "Balanced").tag("Balanced")
                    } label: {
                        HStack {
                            Text("Select Goal")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(PLColor.accent)
                    }
                    .pickerStyle(.navigationLink)

                    Text("Savings Priority")
                        .font(.headline)

                    Picker("", selection: $savingsPriority) {
                        Text("Low").tag("Low")
                        Text("Medium").tag("Medium")
                        Text("High").tag("High")
                    }
                    .pickerStyle(.segmented)
                }
                .plCard()




                
                // Location
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("Location")
                        .font(.headline)
                    Toggle("Use My Location", isOn: $useDeviceLocation)
                        .onChange(of: useDeviceLocation) { enabled in
                            if enabled { getLocation() }
                        }
                    
                    if useDeviceLocation {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                            Text(city.isEmpty && state.isEmpty ? "Detecting…" : "Detected: \(city), \(state)")
                                .foregroundColor(PLColor.textSecondary)
                        }
                        .font(.subheadline)
                    } else {
                        TextField("City", text: $manualCity)
                            .textFieldStyle(.roundedBorder)
                        Picker("State", selection: $manualState) {
                            Text("Select a state").tag("")
                            ForEach(US_STATES) { st in Text(st.name).tag(st.code) }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }
                .plCard()
                
                // Lifestyle details
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("Lifestyle Details")
                        .font(.headline)

                    Picker(selection: $housingSituation) {
                        optionRow("Renting", isSelected: housingSituation == "Renting").tag("Renting")
                        optionRow("Own with mortgage", isSelected: housingSituation == "Own with Mortgage").tag("Own with Mortgage")
                        optionRow("Own free and clear", isSelected: housingSituation == "Own Free and Clear").tag("Own Free and Clear")
                        optionRow("Live with parents / roommates", isSelected: housingSituation == "Live with Others").tag("Live with Others")
                        optionRow("Other", isSelected: housingSituation == "Other").tag("Other")
                    } label: {
                        HStack {
                            Text("Select Housing")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(PLColor.accent)
                    }
                    .pickerStyle(.navigationLink)
                        
                    


                    Picker(selection: $carOwnership) {
                        optionRow("No car", isSelected: carOwnership == "No Car").tag("No Car")
                        optionRow("One car", isSelected: carOwnership == "One Car").tag("One Car")
                        optionRow("Multiple cars", isSelected: carOwnership == "Multiple Cars").tag("Multiple Cars")
                    } label: {
                        HStack {
                            Text("Select Transportation")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(PLColor.accent)
                    }
                    .pickerStyle(.navigationLink)



                    Picker(selection: $eatingOutFrequency) {
                        optionRow("Rarely", isSelected: eatingOutFrequency == "Rarely").tag("Rarely")
                        optionRow("Sometimes", isSelected: eatingOutFrequency == "Sometimes").tag("Sometimes")
                        optionRow("Often", isSelected: eatingOutFrequency == "Often").tag("Often")
                    } label: {
                        HStack {
                            Text("Select Eating Out Frequency")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(PLColor.accent)
                    }
                    .pickerStyle(.navigationLink)
                    
                }
                .plCard()

                
                // Known monthly costs (optional)
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("Known Monthly Costs (Optional)")
                        .font(.headline)
                    LazyVStack(spacing: PLSpacing.sm) {
                        ForEach(Array(selectedCategories.subtracting(trackerExclusions)).sorted(), id: \.self) { category in
                            TextField("\(category) ($)", text: Binding(
                                get: { knownCosts[category] ?? "" },
                                set: { knownCosts[category] = $0.filter { "0123456789.".contains($0) } }
                            ))
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .plCard()
                
                // Category selection
                VStack(alignment: .leading, spacing: PLSpacing.sm) {
                    Text("Select Budget Categories")
                        .font(.headline)
                    
                    // Simple, readable toggle list for now (can switch to chips later)
                    LazyVStack(spacing: 8) {
                        ForEach(allCategories.filter { !trackerExclusions.contains($0) }.sorted(), id: \.self) { category in
                            Toggle(category, isOn: Binding(
                                get: { selectedCategories.contains(category) },
                                set: { isSelected in
                                    if isSelected { selectedCategories.insert(category) }
                                    else { selectedCategories.remove(category) }
                                }
                            ))
                        }
                    }
                    
                    HStack(spacing: PLSpacing.sm) {
                        TextField("Custom Category", text: $customCategory)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let trimmed = customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty && !allCategories.contains(trimmed) && !trackerExclusions.contains(trimmed) {
                                allCategories.append(trimmed)
                                selectedCategories.insert(trimmed)
                                customCategory = ""
                            }
                        }
                        .buttonStyle(OutlineButton(tint: PLColor.accent))
                    }
                }
                .plCard()
                
                // Actions
                VStack(spacing: PLSpacing.sm) {
                    Button {
                        Task { await generateBudgetFromLLM() }
                    } label: {
                        Text(isLoading ? "Generating…" : "Generate Budget")
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(
                        isLoading ||
                        yearlyIncome.isEmpty || retirement.isEmpty || numberOfDependents.isEmpty ||
                        primaryGoal.isEmpty || savingsPriority.isEmpty ||
                        (useDeviceLocation ? (city.isEmpty || state.isEmpty) : (manualCity.isEmpty || manualState.isEmpty)) ||
                        !debtEntriesValid
                    )
                }
            }
            .padding(.horizontal, PLSpacing.lg)
            .padding(.vertical, PLSpacing.lg)
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Budget Quiz").font(.headline)
            }
//            ToolbarItemGroup(placement: .keyboard) {
//                Spacer()
//                Button("Done") { hideKeyboard() }
//            }
        }
        .tint(PLColor.accent)
        .alert("Something went wrong", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        }
        // Loading bottom-sheet (same behavior, just declared at root)
        .sheet(isPresented: $showLoadingSheet) {
            VStack(spacing: 16) {
                ProgressView("Generating Budget...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
                Text("This may take a few seconds.")
                    .font(.subheadline)
                    .foregroundColor(PLColor.textSecondary)
            }
            .presentationDetents([.fraction(0.25)])
        }
        .onAppear {
            loadSavedQuiz()
            if useDeviceLocation && city.isEmpty && state.isEmpty {
                getLocation()
            }
        }
        .onTapGesture { hideKeyboard() }
    }
    
    // MARK: - LLM Budget Gen (logic unchanged)
    func generateBudgetFromLLM() async {
        let url = URL(string: "\(BackendConfig.baseURLString)/api/llm/budget")!
        
        let iso = ISO8601DateFormatter()
        let debtsPayload: [[String: Any]] = hasDebt ? debts.map { d in
            [
                "name": d.name,
                "principal": Double(d.principal) ?? 0.0,
                "apr": Double(d.apr) ?? 0.0,
                "minPayment": Double(d.minPayment) ?? 0.0,
                "dueDate": iso.string(from: d.dueDate)
            ]
        } : []
        
        let finalCity = useDeviceLocation ? city : manualCity
        let finalState = useDeviceLocation ? state : manualState

        let knownCostsPayload: [String: Double] = knownCosts.reduce(into: [:]) { result, entry in
            if let val = parseAmount(entry.value) {
                result[entry.key] = val
            }
        }

        let payload: [String: Any] = [
            "username": username,
            "yearlyIncome": yearlyIncome,
            "401(k) Contribution": retirement,
            "dependents": numberOfDependents,
            "city": finalCity,
            "state": finalState,
            "spendingStyle": spendingStyle,
            "primaryGoal": primaryGoal,
            "savingsPriority": savingsPriority,
            "housingSituation": housingSituation,
            "carOwnership": carOwnership,
            "eatingOutFrequency": eatingOutFrequency,
            "useDeviceLocation": useDeviceLocation,
            "categories": Array(selectedCategories.subtracting(trackerExclusions).sorted()),
            "knownCosts": knownCostsPayload,
            "hasDebt": hasDebt,
            "debts": debtsPayload
        ]

        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        
        DispatchQueue.main.async {
            isLoading = true
            showLoadingSheet = true
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
                await saveBudgetToBackend(decoded)
            } else {
                throw URLError(.badServerResponse)
            }
        } catch {
            print("Error generating budget: \(error)")
            DispatchQueue.main.async {
                showError = true
                isLoading = false
                showLoadingSheet = false
            }
        }
    }

    private func parseAmount(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }
    
    func saveBudgetToBackend(_ budget: [String: Double]) async {
        do {
            try await postBudget(username: username, type: "monthly", budget: budget)
            let weekly = budget.mapValues { $0 / 4.0 }
            try await postBudget(username: username, type: "weekly", budget: weekly)
            await resetCostsToSelectedCategories()
            UserDefaults.standard.set(true, forKey: "budgetQuizCompleted")
            // Notify observers (e.g., BudgetView) to refresh state immediately
            NotificationCenter.default.post(name: .budgetQuizCompleted, object: nil)
            
            DispatchQueue.main.async {
                isLoading = false
                showLoadingSheet = false
                dismiss()
            }
        } catch {
            print("Error saving budget: \(error)")
            DispatchQueue.main.async {
                showError = true
                isLoading = false
                showLoadingSheet = false
            }
        }
    }
    
    func postBudget(username: String, type: String, budget: [String: Double]) async throws {
        let url = URL(string: "\(BackendConfig.baseURLString)/api/budget")!
        let payload: [String: Any] = [
            "username": username,
            "type": type,
            "budget": budget
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        _ = try await URLSession.shared.data(for: request)
    }
    
    func loadSavedQuiz() {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/llm/budget/last/\(username)") else { return }
        Task {
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
                if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    await MainActor.run {
                        yearlyIncome        = String(describing: dict["yearlyIncome"]  ?? "")
                        retirement          = String(describing: dict["401(k) Contribution"] ?? "")
                        numberOfDependents  = String(describing: dict["dependents"]    ?? "")
                        city                = String(dict["city"] as? String ?? "")
                        state               = String(dict["state"] as? String ?? "")
                        spendingStyle       = String(dict["spendingStyle"] as? String ?? "Medium")
                        
                        if let cats = dict["categories"] as? [String] {
                            let filtered = cats.filter { !trackerExclusions.contains($0) }
                            allCategories = Array(Set(allCategories).union(filtered))
                            selectedCategories = Set(filtered)
                        }
                        if let kc = dict["knownCosts"] as? [String: Double] {
                            knownCosts = kc.mapValues { String($0) }
                        }
                        if let flag = dict["useDeviceLocation"] as? Bool {
                            useDeviceLocation = flag
                            if flag { getLocation() }
                        }
                        manualCity  = String(dict["city"]  as? String ?? "")
                        manualState = String(dict["state"] as? String ?? "")
                        
                        if let hasDebtSaved = dict["hasDebt"] as? Bool { hasDebt = hasDebtSaved }
                        if let savedDebts = dict["debts"] as? [[String: Any]] {
                            let iso = ISO8601DateFormatter()
                            debts = savedDebts.map { d in
                                let name = d["name"] as? String ?? ""
                                let principalStr = String(describing: d["principal"] ?? "")
                                let aprStr = String(describing: d["apr"] ?? "")
                                let minStr = String(describing: d["minPayment"] ?? "")
                                let dueStr = d["dueDate"] as? String ?? ""
                                let due = iso.date(from: dueStr) ?? Date()
                                return DebtItem(name: name,
                                                principal: principalStr,
                                                apr: aprStr,
                                                minPayment: minStr,
                                                dueDate: due)
                            }
                        }
                        
                        if let goal = dict["primaryGoal"] as? String, !goal.isEmpty, primaryGoal == "Balanced" {
                            primaryGoal = goal
                        }
                        if let priority = dict["savingsPriority"] as? String, !priority.isEmpty, savingsPriority == "Medium" {
                            savingsPriority = priority
                        }
                        if let housing = dict["housingSituation"] as? String, !housing.isEmpty, housingSituation.isEmpty {
                            housingSituation = housing
                        }
                        if let car = dict["carOwnership"] as? String, !car.isEmpty, carOwnership == "One Car" {
                            carOwnership = car
                        }
                        if let eating = dict["eatingOutFrequency"] as? String, !eating.isEmpty, eatingOutFrequency == "Sometimes" {
                            eatingOutFrequency = eating
                        }
                    }
                }
            } catch { print("No previous quiz data: \(error)") }
        }
    }
    
    func postCosts(username: String, type: String, costs: [String: Double]) async throws {
        let url = URL(string: "\(BackendConfig.baseURLString)/api/costs")!
        let payload: [String: Any] = [
            "username": username,
            "type": type,
            "costs": costs
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        _ = try await URLSession.shared.data(for: req)
    }
    
    func resetCostsToSelectedCategories() async {
        var zeros = Dictionary(
            uniqueKeysWithValues: selectedCategories
                .subtracting(trackerExclusions)
                .map { ($0, 0.0) }
        )
        if hasDebt {
            for d in debts where !d.name.trimmingCharacters(in: .whitespaces).isEmpty {
                zeros["Debt - \(d.name)"] = 0.0
            }
        }
        do {
            try await postCosts(username: username, type: "monthly", costs: zeros)
            try await postCosts(username: username, type: "weekly",  costs: zeros)
            print("Costs reset to zeros for selected categories.")
        } catch { print("Failed to reset costs: \(error)") }
    }
    
    func getLocation() {
        locationManager.requestLocation { cityName, stateName in
            self.city = cityName
            self.state = stateName
        }
    }
}

// ---------- Rows & helpers ----------
private struct DebtRow: View {
    @Binding var debt: DebtItem
    var body: some View {
        VStack(alignment: .leading, spacing: PLSpacing.sm) {
            TextField("Name (e.g., Chase Credit Card)", text: $debt.name)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: PLSpacing.sm) {
                TextField("Remaining Balance ($)", text: $debt.principal)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: debt.principal) { v in debt.principal = v.filter { "0123456789.".contains($0) } }
                TextField("APR (%)", text: $debt.apr)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: debt.apr) { v in debt.apr = v.filter { "0123456789.".contains($0) } }
            }
            TextField("Minimum Monthly Payment ($)", text: $debt.minPayment)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: debt.minPayment) { v in debt.minPayment = v.filter { "0123456789.".contains($0) } }
            DatePicker("Next Payment Due", selection: $debt.dueDate, displayedComponents: .date)
        }
    }
}

// ---------- Location plumbing (unchanged) ----------
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((String, String) -> Void)?
    
    override init() {
        super.init()
        manager.delegate = self
    }
    
    func requestLocation(completion: @escaping (String, String) -> Void) {
        self.completion = completion
        manager.delegate = self
        
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            print("Location access denied")
            self.completion?("Permission", "Denied")
            return
        }
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            if let place = placemarks?.first {
                let city = place.locality ?? ""
                let state = place.administrativeArea ?? ""
                DispatchQueue.main.async { self.completion?(city, state) }
            }
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error:", error)
    }
}

// ---------- Models ----------
struct USState: Identifiable {
    let id = UUID()
    let name: String
    let code: String
}

struct DebtItem: Identifiable, Codable {
    var id = UUID()
    var name: String = ""
    var principal: String = ""
    var apr: String = ""
    var minPayment: String = ""
    var dueDate: Date = Date()
}

#if canImport(UIKit)
private extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

#Preview { BudgetQuizView() }
