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

    @State private var selectedCategories: Set<String> = Set(defaultCategories)
    @State private var customCategory = ""

    @State private var quizCompleted = false
    @State private var generatedBudget: [String: Double]? = nil
    @State private var showBudgetInput = false

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
                            .font(.caption)
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
                    Button("Generate Budget") {
                        Task {
                            await generateLLMBudget()
                        }
                    }
                    .disabled(yearlyIncome.isEmpty || numberOfDependents.isEmpty || (city.isEmpty && !useDeviceLocation))
                }
            }
            .navigationTitle("Budget Quiz")

            // Navigate when ready
            .navigationDestination(isPresented: $showBudgetInput) {
                if let gen = generatedBudget {
                    BudgetInputView(prefilledBudget: gen)
                }
            }
        }
    }

    // MARK: - LLM Budget Gen
    func generateLLMBudget() async {
        guard let income = Double(yearlyIncome) else { return }

        let finalCity = city
        let finalState = state

        let prompt: [String: Any] = [
            "username": username,
            "yearlyIncome": income,
            "dependents": numberOfDependents,
            "city": finalCity,
            "state": finalState,
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
                DispatchQueue.main.async {
                    self.generatedBudget = decoded
                    self.showBudgetInput = true
                }
            }
        } catch {
            print("Error generating budget: \(error)")
        }
        // Make sure the quiz is completed first before other features appear
        UserDefaults.standard.set(true, forKey: "budgetQuizCompleted")
    }

    // MARK: - Location
    func getLocation() {
        LocationManager.shared.requestLocation { cityName, stateName in
            self.city = cityName
            self.state = stateName
        }
    }
}

class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    private let manager = CLLocationManager()
    private var completion: ((String, String) -> Void)?

    func requestLocation(completion: @escaping (String, String) -> Void) {
        self.completion = completion
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            if let place = placemarks?.first {
                let city = place.locality ?? ""
                let state = place.administrativeArea ?? ""
                self.completion?(city, state)
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
