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
                    TextField("Number of Dependents", text: $numberOfDependents)
                        .keyboardType(.numberPad)
                    
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
                    ForEach(Self.defaultCategories, id: \.self) { category in
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
                            let trimmed = customCategory.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty {
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
                                await generateLLMBudget()
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
    func generateLLMBudget() async {
        guard let income = Double(yearlyIncome) else { return }
        isLoading = true

        let prompt: [String: Any] = [
            "username": username,
            "yearlyIncome": income,
            "dependents": numberOfDependents,
            "city": city,
            "state": state,
            "spendingStyle": spendingStyle,
            "categories": Array(selectedCategories)
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: prompt) else { return }

        var request = URLRequest(url: URL(string: "http://localhost:8080/api/llm/budget")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
                // Save to backend
                let payload: [String: Any] = [
                    "username": username,
                    "type": "monthly",
                    "budget": decoded
                ]
                let body = try? JSONSerialization.data(withJSONObject: payload)

                var saveReq = URLRequest(url: URL(string: "http://localhost:8080/api/budget")!)
                saveReq.httpMethod = "POST"
                saveReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                saveReq.httpBody = body

                _ = try? await URLSession.shared.data(for: saveReq)

                // Also save weekly
                let weeklyBudget = decoded.mapValues { $0 / 4 }
                let weeklyPayload: [String: Any] = [
                    "username": username,
                    "type": "weekly",
                    "budget": weeklyBudget
                ]
                let weeklyBody = try? JSONSerialization.data(withJSONObject: weeklyPayload)

                var weeklyReq = URLRequest(url: URL(string: "http://localhost:8080/api/budget")!)
                weeklyReq.httpMethod = "POST"
                weeklyReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                weeklyReq.httpBody = weeklyBody

                _ = try? await URLSession.shared.data(for: weeklyReq)

                // Set flag and dismiss
                UserDefaults.standard.set(true, forKey: "budgetQuizCompleted")

                DispatchQueue.main.async {
                    isLoading = false
                    dismiss()
                }
            } else {
                throw URLError(.cannotParseResponse)
            }
        } catch {
            print("Error generating budget: \(error)")
            isLoading = false
            showError = true
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
