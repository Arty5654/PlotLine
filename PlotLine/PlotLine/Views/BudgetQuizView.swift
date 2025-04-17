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
        "Entertainment", "Utilities", "Savings", "Investments", "Miscellaneous"
    ]
    @State private var allCategories: [String] = defaultCategories
    
    @State private var yearlyIncome = ""
    @State private var numberOfDependents = ""
    @State private var city = ""
    @State private var state = ""
    @State private var useDeviceLocation = true
    @State private var spendingStyle = "Medium"

    @State private var selectedCategories: Set<String> = Set(defaultCategories)
    @State private var customCategory = ""

    @State private var isLoading = false
    @State private var showError = false

    @Environment(\.dismiss) var dismiss
    @StateObject private var locationManager = LocationManager()

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
                            } else {
                                city = ""
                                state = ""
                            }
                        }

                    if !useDeviceLocation {
                        TextField("City", text: $city)
                        TextField("State", text: $state)
                    } else {
                        Text("Detected: \(city), \(state)")
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
            if useDeviceLocation {
                getLocation()
            }
        }
    }

    // MARK: - LLM Budget Gen
    func generateBudgetFromLLM() async {
        let url = URL(string: "http://localhost:8080/api/llm/budget")!
        let payload: [String: Any] = [
            "username": username,
            "yearlyIncome": yearlyIncome,
            "dependents": numberOfDependents,
            "city": city,
            "state": state,
            "spendingStyle": spendingStyle,
            "categories": Array(selectedCategories.sorted())
        ]
        
        //print("Categories: \(Array(selectedCategories.sorted()))")
        
        print("Sending categories to backend:", Array(selectedCategories))

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }

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

    private func postBudget(username: String, type: String, budget: [String: Double]) async throws {
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
