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
        "Entertainment", "Utilities", "Savings", "Investments", "Transportation", "Miscellaneous"
    ]
    @State private var allCategories: [String] = defaultCategories
    
    @State private var yearlyIncome = ""
    @State private var numberOfDependents = ""
    
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
                    TextField("Number of Dependents", text: $numberOfDependents)
                        .keyboardType(.numberPad)
                        .onChange(of: numberOfDependents) { newValue in
                            numberOfDependents = newValue.filter { "0123456789".contains($0) }
                        }
                    
                    .pickerStyle(SegmentedPickerStyle())
                    
                }
                
                Section(header: Text("How aggressively do you want to save?")) {
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
                        TextField("State", text: $manualState)
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
                        .disabled(yearlyIncome.isEmpty || numberOfDependents.isEmpty || (city.isEmpty && !useDeviceLocation))
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
        
        // Use either manual or detected location
        let finalCity = useDeviceLocation ? city : manualCity
        let finalState = useDeviceLocation ? state : manualState
        let payload: [String: Any] = [
            "username": username,
            "yearlyIncome": yearlyIncome,
            "dependents": numberOfDependents,
            "city": finalCity,
            "state": finalState,
            "spendingStyle": spendingStyle,
            "useDeviceLocation": useDeviceLocation,
            "categories": Array(selectedCategories.sorted()),
            "knownCosts": knownCosts.compactMapValues { Double($0) }
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
                    }
                }
            } catch {
                print("No previous quiz data: \(error)")
            }
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


#Preview {
    BudgetQuizView()
}
