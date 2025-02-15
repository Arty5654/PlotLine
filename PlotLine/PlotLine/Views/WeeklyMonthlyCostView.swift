//
//  WeeklyMonthlyCostView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 2/15/25.
//

import SwiftUI

struct WeeklyMonthlyCostView: View {
    @State private var selectedType = UserDefaults.standard.string(forKey: "selectedType") ?? "Weekly"
    @State private var costItems: [BudgetItem] = []
    @State private var newCategory: String = ""
    @State private var showSuccessAlert: Bool = false

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
                // Reload data when user switches
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
                        Button(action: {
                            removeCategory(item: item)
                        }) {
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
            .alert(isPresented: $showSuccessAlert) {
                Alert(
                    title: Text("Success"),
                    message: Text("Your \(selectedType) costs have been saved."),
                    // Do not go back to budget page
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .padding()
        .navigationTitle("\(selectedType) Cost Input")
        // Load saved data when the screen appears
        .onAppear(perform: loadSavedData)
    }

    // MARK: - Functions

    private func addCategory() {
        guard !newCategory.isEmpty else { return }
        if !costItems.contains(where: { $0.category.lowercased() == newCategory.lowercased() }) {
            costItems.append(BudgetItem(category: newCategory, amount: ""))
            saveToUserDefaults()
        }
        newCategory = ""
    }

    private func removeCategory(item: BudgetItem) {
        costItems.removeAll { $0.id == item.id }
        saveToUserDefaults()
    }

    private func deleteItems(at offsets: IndexSet) {
        costItems.remove(atOffsets: offsets)
        saveToUserDefaults()
    }

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

        let url = URL(string: "http://localhost:8080/api/costs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error saving costs: \(error)")
                return
            }
            DispatchQueue.main.async {
                showSuccessAlert = true
            }
        }.resume()
        
        // Save to local storage after saving to backend
        saveToUserDefaults()
    }

    private func saveToUserDefaults() {
        let savedData = costItems.map { ["category": $0.category, "amount": $0.amount] }
        UserDefaults.standard.set(savedData, forKey: "savedCosts_\(selectedType)")
        UserDefaults.standard.set(selectedType, forKey: "selectedType")
    }

    private func loadSavedData() {
        if let savedArray = UserDefaults.standard.array(forKey: "savedCosts_\(selectedType)") as? [[String: String]] {
            costItems = savedArray.map { BudgetItem(category: $0["category"] ?? "", amount: $0["amount"] ?? "") }
        } else {
            costItems = [
                BudgetItem(category: "Rent", amount: ""),
                BudgetItem(category: "Groceries", amount: ""),
                BudgetItem(category: "Subscriptions", amount: ""),
                BudgetItem(category: "Eating Out", amount: ""),
                BudgetItem(category: "Entertainment", amount: ""),
                BudgetItem(category: "Utilities", amount: ""),
                BudgetItem(category: "Miscellaneous", amount: "")
            ]
        }
    }
}

// MARK: - Data Model
struct BudgetItem: Identifiable {
    let id = UUID()
    let category: String
    var amount: String
}

// MARK: - Preview
#Preview {
    WeeklyMonthlyCostView()
}
