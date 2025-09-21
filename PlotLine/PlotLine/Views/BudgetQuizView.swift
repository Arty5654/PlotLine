//
//  BudgetQuizView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 4/16/25.
//

import SwiftUI
import CoreLocation

struct BudgetQuizView: View {
    static let defaultCategories = [
        "Rent", "Groceries", "Subscriptions", "Eating Out",
        "Entertainment", "Utilities", "Savings", "Miscellaneous", "Transportation", "401(k)", "Roth IRA", "Car Insurance", "Health Insurance", "Brokerage"
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
    // For the "?" next to 401k Contribution
    @State private var retirementTip = false
    @State private var numberOfDependents = ""
    
    // Debts
    @State private var hasDebt = false
    @State private var debts: [DebtItem] = []
    var debtEntriesValid: Bool {
        guard hasDebt else { return true }
        return debts.allSatisfy { !$0.name.isEmpty && Double($0.principal) != nil }
    }
    
    // Detected location or manual input
    @State private var city = ""
    @State private var state = ""
    @State private var manualCity = ""
    @State private var manualState = ""
    @State private var useDeviceLocation = true
    
    
    @State private var spendingStyle = "Medium"

    @State private var selectedCategories: Set<String> = Set(defaultCategories)
    @State private var customCategory = ""

    @State private var isLoading = false
    @State private var showError = false

    @Environment(\.dismiss) var dismiss
    @StateObject private var locationManager = LocationManager()
    
    // For known costs
    @State private var knownCosts: [String: String] = [:]
    
    // Loading screen
    @State private var showLoadingSheet = false
    

    var username: String {
        UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Income & Household")) {
                    TextField("Yearly Income ($)", text: $yearlyIncome)
                        .keyboardType(.decimalPad)
                        .onChange(of: yearlyIncome) { newValue in
                            yearlyIncome = newValue.filter { "0123456789.".contains($0) }
                        }
                    HStack(spacing: 8) {
                        TextField("Contribution to 401(k) (Percentage)", text: $retirement)
                            .keyboardType(.decimalPad)
                            .onChange(of: retirement) { newValue in
                                retirement = newValue.filter { "0123456789.".contains($0) }
                            }
                        Button {
                            retirementTip = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .imageScale(.medium)
                                .foregroundColor(.blue)
                                .accessibilityLabel("What contribution percentage should I choose?")
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .popover(isPresented: $retirementTip, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("401(k) Contribution Tip")
                                .font(.headline)
                            Text("A common target is 10-15% of your gross income. Ensure to contribute enough to get your employer’s full match (it’s essentially free money).")
                            
                        }
                        .padding()
                        .frame(maxWidth: 320)
                        
                    }
                    TextField("Number of Dependents", text: $numberOfDependents)
                        .keyboardType(.numberPad)
                        .onChange(of: numberOfDependents) { newValue in
                            numberOfDependents = newValue.filter { "0123456789".contains($0) }
                        }
                    
                    //.pickerStyle(SegmentedPickerStyle())
                    
                }
                
                Section(header: Text("Debt")) {
                    Toggle("I have debt to payoff", isOn: $hasDebt)
                        .onChange(of: hasDebt) { on in
                            if !on { debts.removeAll()}
                        }
                    if hasDebt {
                        ForEach($debts) { $debt in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Name (e.g., Chase Credit Card)", text: $debt.name)

                                HStack {
                                    TextField("Remaining Balance ($)", text: $debt.principal)
                                        .keyboardType(.decimalPad)
                                        .onChange(of: debt.principal) { v in
                                            debt.principal = v.filter { "0123456789.".contains($0) }
                                        }
                                    TextField("APR (%)", text: $debt.apr)
                                        .keyboardType(.decimalPad)
                                        .onChange(of: debt.apr) { v in
                                            debt.apr = v.filter { "0123456789.".contains($0) }
                                        }
                                }

                                TextField("Minimum Monthly Payment ($)", text: $debt.minPayment)
                                    .keyboardType(.decimalPad)
                                    .onChange(of: debt.minPayment) { v in
                                        debt.minPayment = v.filter { "0123456789.".contains($0) }
                                    }

                                DatePicker("Next Payment Due", selection: $debt.dueDate, displayedComponents: .date)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { idx in debts.remove(atOffsets: idx) }

                        Button {
                            debts.append(DebtItem())
                        } label: {
                            Label("Add Debt", systemImage: "plus.circle.fill")
                        }
                    }
                    
                }
                
                Section(header: Text("What is your Spending Style?")) {
                    Picker("Spending Style", selection: $spendingStyle) {
                        Text("Low").tag("Low")
                        Text("Medium").tag("Medium")
                        Text("High").tag("High")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(header: Text("Location")) {
                    Toggle("Use My Location", isOn: $useDeviceLocation)
                        .onChange(of: useDeviceLocation) { enabled in
                            if enabled {
                                getLocation()
                            }
                        }
                    
                    // Detected or manual
                    if useDeviceLocation {
                        Text("Detected: \(city), \(state)")
                            //.foregroundColor(.secondary)
                    } else {
                        TextField("City", text: $manualCity)
                        //TextField("State", text: $manualState)
                        Picker("State", selection: $manualState) {
                            Text("Select a state").tag("")
                            ForEach(US_STATES) { states in
                                Text(states.name).tag(states.code)
                            }
                        }
                    }
                }
                
                Section(header: Text("Known Monthly Costs (Optional)")) {
                    ForEach(Array(selectedCategories).sorted(), id: \.self) { category in
                        TextField("\(category) ($)", text: Binding(
                            get: { knownCosts[category] ?? "" },
                            set: { knownCosts[category] = $0.filter { "0123456789.".contains($0) } }
                        ))
                        .keyboardType(.decimalPad)
                    }
                }

                Section(header: Text("Select Budget Categories")) {
                    ForEach(allCategories.sorted(), id: \.self) { category in
                        Toggle(category, isOn: Binding(
                            get: { selectedCategories.contains(category) },
                            set: { isSelected in
                                if isSelected {
                                    selectedCategories.insert(category)
                                } else {
                                    selectedCategories.remove(category)
                                }
                            }
                        ))
                    }

                    HStack {
                        TextField("Custom Category", text: $customCategory)
                        Button("Add") {
                            let trimmed = customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty && !allCategories.contains(trimmed) {
                                allCategories.append(trimmed)
                                selectedCategories.insert(trimmed)
                                customCategory = ""
                            }
                        }
                    }
                }
                // Loading Screen
                .sheet(isPresented: $showLoadingSheet) {
                    VStack(spacing: 16) {
                        ProgressView("Generating Budget...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding()
                        Text("This may take a few seconds.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .presentationDetents([.fraction(0.25)])
                }

                Section {
                    if isLoading {
                        ProgressView("Generating Budget...")
                    } else {
                        Button("Generate Budget") {
                            Task {
                                await generateBudgetFromLLM()
                            }
                        }
                        .disabled(
                            yearlyIncome.isEmpty || retirement.isEmpty ||
                            numberOfDependents.isEmpty ||
                            (useDeviceLocation ? city.isEmpty || state.isEmpty : manualCity.isEmpty || manualState.isEmpty) ||
                            !debtEntriesValid
                        )

                    }
                }
            }
            .navigationTitle("Budget Quiz")
            .alert("Something went wrong", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            }
        }
        .onAppear {
//            if useDeviceLocation {
//                getLocation()
            //}
            loadSavedQuiz()
            // No prior quiz and toggle switch is on, show location
            if useDeviceLocation && city.isEmpty && state.isEmpty {
                getLocation()
            }
        }
    }

    // MARK: - LLM Budget Gen
    func generateBudgetFromLLM() async {
        let url = URL(string: "http://localhost:8080/api/llm/budget")!
        
        let iso = ISO8601DateFormatter()
        let debtsPayload: [[String: Any]] = hasDebt ? debts.map { d in
            return [
                "name": d.name,
                "principal": Double(d.principal) ?? 0.0,
                "apr": Double(d.apr) ?? 0.0,             // APR as % number (e.g., 22.99)
                "minPayment": Double(d.minPayment) ?? 0.0,
                "dueDate": iso.string(from: d.dueDate)
                // TODO: Maybe might need this instead
                // "dueDay": Calendar.current.component(.day, from: d.dueDate)
            ]
        } : []
        
        // Use either manual or detected location
        let finalCity = useDeviceLocation ? city : manualCity
        let finalState = useDeviceLocation ? state : manualState
        let payload: [String: Any] = [
            "username": username,
            "yearlyIncome": yearlyIncome,
            "401(k) Contribution": retirement,
            "dependents": numberOfDependents,
            "city": finalCity,
            "state": finalState,
            "spendingStyle": spendingStyle,
            "useDeviceLocation": useDeviceLocation,
            "categories": Array(selectedCategories.sorted()),
            "knownCosts": knownCosts.compactMapValues { Double($0) },
            "hasDebt": hasDebt,
            "debts": debtsPayload
        ]
        
        //print("Categories: \(Array(selectedCategories.sorted()))")
        
        print("Sending categories to backend:", Array(selectedCategories))

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        DispatchQueue.main.async {
            isLoading = true
            showLoadingSheet = true
        }

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

    func saveBudgetToBackend(_ budget: [String: Double]) async {
        do {
            // Save monthly budget
            try await postBudget(username: username, type: "monthly", budget: budget)

            // Save weekly budget (monthly / 4)
            let weekly = budget.mapValues { $0 / 4.0 }
            try await postBudget(username: username, type: "weekly", budget: weekly)
            
            // Reset weekly/monthly costs after each quiz
            await resetCostsToSelectedCategories()

            // Save completion flag
            UserDefaults.standard.set(true, forKey: "budgetQuizCompleted")

            DispatchQueue.main.async {
                isLoading = false
                dismiss()
            }
        } catch {
            print("Error saving budget: \(error)")
            DispatchQueue.main.async {
                showError = true
                isLoading = false
            }
        }
    }

    func postBudget(username: String, type: String, budget: [String: Double]) async throws {
        let url = URL(string: "http://localhost:8080/api/budget")!
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
    
    // Get previous quiz information prefilled
    func loadSavedQuiz() {
        guard let url = URL(string: "http://localhost:8080/api/llm/budget/last/\(username)") else { return }

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
                            allCategories = Array(Set(allCategories).union(cats))
                            selectedCategories = Set(cats)
                        }
                        if let kc = dict["knownCosts"] as? [String: Double] {
                            // convert back to String for the text fields
                            knownCosts = kc.mapValues { String($0) }
                        }
                        
                        // Bool for using device location or not
                        if let flag = dict["useDeviceLocation"] as? Bool {
                            useDeviceLocation = flag
                            if flag { getLocation() }
                        }
                        manualCity  = String(dict["city"]  as? String ?? "")
                        manualState = String(dict["state"] as? String ?? "")
                        
                        // Get Debts
                        if let hasDebtSaved = dict["hasDebt"] as? Bool {
                            hasDebt = hasDebtSaved
                        }
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
                    }
                }
            } catch {
                print("No previous quiz data: \(error)")
            }
        }
    }
    
    // POST /api/costs
    func postCosts(username: String, type: String, costs: [String: Double]) async throws {
        let url = URL(string: "http://localhost:8080/api/costs")!
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

    // Reset costs for both weekly & monthly to zeros for the quiz-selected categories
    func resetCostsToSelectedCategories() async {
        // zero map from selected categories
        var zeros = Dictionary(uniqueKeysWithValues: selectedCategories.map { ($0, 0.0) })

        // If you want debt lines (if the user entered debts) to also appear in costs:
        if hasDebt {
            for d in debts where !d.name.trimmingCharacters(in: .whitespaces).isEmpty {
                zeros["Debt - \(d.name)"] = 0.0
            }
        }

        do {
            try await postCosts(username: username, type: "monthly", costs: zeros)
            try await postCosts(username: username, type: "weekly",  costs: zeros)
            print("Costs reset to zeros for selected categories.")
        } catch {
            print("Failed to reset costs: \(error)")
        }
    }

    // MARK: - Location
    func getLocation() {
        locationManager.requestLocation { cityName, stateName in
            self.city = cityName
            self.state = stateName
        }
    }
}

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
                DispatchQueue.main.async {
                    self.completion?(city, state)
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error:", error)
    }
}
    
   

    
    

struct USState: Identifiable {
    let id = UUID()
    let name: String
    let code: String
}

struct DebtItem: Identifiable, Codable {
    var id = UUID()
    var name: String = ""            // e.g., “Chase Credit Card”
    var principal: String = ""       // store as String for TextField; convert before sending
    var apr: String = ""             // APR as percentage string, e.g., “22.99”
    var minPayment: String = ""      // optional minimum payment per month
    var dueDate: Date = Date()       // next payment due (or target payoff date)
}



#Preview {
    BudgetQuizView()
}
