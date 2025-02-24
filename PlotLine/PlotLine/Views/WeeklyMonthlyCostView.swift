//
//  WeeklyMonthlyCostView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 2/15/25.
//

import SwiftUI
import Foundation

struct WeeklyMonthlyCostView: View {
    @State private var selectedType = UserDefaults.standard.string(forKey: "selectedType") ?? "Weekly"
    @State private var costItems: [BudgetItem] = []
    @State private var budgetLimits: [String: Double] = [:] // Stores budget limits
    @State private var newCategory: String = ""
    @State private var showSuccessAlert: Bool = false
    @State private var showBudgetWarning: Bool = false
    @State private var budgetWarningMessage: String = ""

    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        VStack(spacing: 15) {
            Text("Enter Your \(selectedType) Costs")
                .font(.title2)
                .bold()

            // Weekly/Monthly Toggle
            Picker("Type", selection: $selectedType) {
                Text("Weekly").tag("Weekly")
                Text("Monthly").tag("Monthly")
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            .onChange(of: selectedType) {
                loadBudgetLimits() // Load budget when type changes
                loadSavedData()
            }

            // Expense Inputs
            List {
                ForEach($costItems) { $item in
                    HStack {
                        Text(item.category)
                            .frame(width: 120, alignment: .leading)
                        TextField("Amount ($)", text: $item.amount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: item.amount) {
                                checkBudgetWarnings() // Check warnings on input change
                            }

                        // ⚠️ Budget Warning Indicator (if cost exceeds budget)
                        if let budget = budgetLimits[item.category], let cost = Double(item.amount) {
                            if cost > budget {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .overlay(
                                        Text("Over budget!")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                            .padding(5)
                                            .frame(width: 120)
                                            .background(Color.white)
                                            .cornerRadius(5)
                                            .shadow(radius: 3)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .offset(y: -25), // Position above the warning icon
                                        alignment: .top
                                    )
                            } else if cost >= budget * 0.8 {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .overlay(
                                        Text("Nearing budget")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                            .padding(5)
                                            .frame(width: 120)
                                            .background(Color.white)
                                            .cornerRadius(5)
                                            .shadow(radius: 3)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .offset(y: -25),
                                        alignment: .top
                                    )
                            }
                        }

                        // Remove category button
                        Button(action: { removeCategory(item: item) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
                .onDelete(perform: deleteItems)
            }

            .frame(height: 300)

            // Add new category input
            HStack {
                TextField("New Category", text: $newCategory)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button(action: addCategory) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding()

            // Save Button
            Button(action: saveCosts) {
                Text("Save Costs")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding()
            .alert(isPresented: $showBudgetWarning) {
                Alert(
                    title: Text("⚠️ Budget Warning"),
                    message: Text(budgetWarningMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .padding()
        .navigationTitle("\(selectedType) Cost Input")
        .alert(isPresented: $showSuccessAlert) {
            Alert(
                title: Text("Success"),
                message: Text("Your \(selectedType) costs have been saved."),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            loadBudgetLimits()
            loadSavedData()
        }
    }

    // MARK: - Functions

    private func addCategory() {
        guard !newCategory.isEmpty else { return }
        if !costItems.contains(where: { $0.category.lowercased() == newCategory.lowercased() }) {
            costItems.append(BudgetItem(category: newCategory, amount: ""))
        }
        newCategory = ""
    }

    private func removeCategory(item: BudgetItem) {
        costItems.removeAll { $0.id == item.id }
    }

    private func deleteItems(at offsets: IndexSet) {
        costItems.remove(atOffsets: offsets)
    }

    // Save user input costs
    private func saveCosts() {
        let costData: [String: Any] = [
            "username": username,
            "type": selectedType.lowercased(),
            "costs": costItems.reduce(into: [String: Double]()) { result, item in
                if let amount = Double(item.amount) {
                    result[item.category] = amount
                }
            }
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: costData) else { return }

        var request = URLRequest(url: URL(string: "http://localhost:8080/api/costs")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, error in
            if error == nil {
                DispatchQueue.main.async {
                    self.showSuccessAlert = true
                }
            }
        }.resume()
    }

    // Load budget limits from backend
    private func loadBudgetLimits() {
        let budgetKey = "\(selectedType.lowercased())-budget.json"
        let urlString = "http://localhost:8080/api/budget/\(username)/\(selectedType.lowercased())"

        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ Error fetching budget:", error.localizedDescription)
                return
            }

            guard let data = data, !data.isEmpty else {
                print("⚠️ No budget data found.")
                return
            }

            do {
                let decodedData = try JSONDecoder().decode(BudgetResponse.self, from: data)
                DispatchQueue.main.async {
                    self.budgetLimits = decodedData.budget
                }
            } catch {
                print("❌ Failed to decode budget data:", error)
            }
        }.resume()
    }

    // Fetch saved costs or use default categories
    private func loadSavedData() {
        let urlString = "http://localhost:8080/api/costs/\(username)/\(selectedType.lowercased())"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ Error fetching costs:", error.localizedDescription)
                return
            }

            guard let data = data, !data.isEmpty else {
                print("⚠️ No cost data found.")
                DispatchQueue.main.async {
                    self.setDefaultCategories()
                }
                return
            }

            do {
                let decodedData = try JSONDecoder().decode(WeeklyMonthlyCostResponse.self, from: data)
                DispatchQueue.main.async {
                    self.costItems = decodedData.costs.map { BudgetItem(category: $0.key, amount: String($0.value)) }
                }
            } catch {
                print("❌ Failed to decode costs:", error)
            }
        }.resume()
    }

    // Default categories if no data is found
    private func setDefaultCategories() {
        self.costItems = [
            BudgetItem(category: "Rent", amount: ""),
            BudgetItem(category: "Groceries", amount: ""),
            BudgetItem(category: "Subscriptions", amount: ""),
            BudgetItem(category: "Eating Out", amount: ""),
            BudgetItem(category: "Entertainment", amount: ""),
            BudgetItem(category: "Utilities", amount: ""),
            BudgetItem(category: "Savings", amount: ""),
            BudgetItem(category: "Miscellaneous", amount: "")
        ]
    }

    // Check for budget warnings dynamically
    private func checkBudgetWarnings() {
        budgetWarningMessage = ""
        for item in costItems {
            if let budgetLimit = budgetLimits[item.category], let costValue = Double(item.amount) {
                if costValue >= budgetLimit {
                    budgetWarningMessage += "\(item.category) exceeds the budget limit!\n"
                }
            }
        }
        showBudgetWarning = !budgetWarningMessage.isEmpty
    }
}

// MARK: - Data Models
//struct BudgetResponse: Codable {
//    let username: String
//    let type: String
//    let budget: [String: Double]
//}
