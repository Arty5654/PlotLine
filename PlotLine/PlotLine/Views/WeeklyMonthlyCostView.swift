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
    @State private var fileIdentifier: String = ""

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
                loadSavedData()
            }
            
            //Text("Debug: \(costItems.count) items")

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
                                checkBudgetWarnings()
                            }
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
            .alert(isPresented: $showBudgetWarning) {
                Alert(
                    title: Text("Budget Warning"),
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
            checkForReset()
            print("🛠 onAppear called! costItems: \(costItems.count)")
            
        }
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

        var request = URLRequest(url: URL(string: "http://localhost:8080/api/costs")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error saving costs: \(error)")
                return
            }
            DispatchQueue.main.async {
                print("Costs saved")
                self.hideKeyboard()
                self.showSuccessAlert = true
            }
        }.resume()
    }
    
   



    private func saveToUserDefaults() {
        let savedData = costItems.map { ["category": $0.category, "amount": $0.amount] }
        UserDefaults.standard.set(savedData, forKey: "savedCosts_\(selectedType)")
        UserDefaults.standard.set(fileIdentifier, forKey: "fileIdentifier_\(selectedType)")
    }
    
    private func loadSavedData() {
        guard let url = URL(string: "http://localhost:8080/api/costs/\(username)/\(selectedType.lowercased())") else {
            print("Invalid URL")
            return
        }

        print("Fetching costs for user:", username, "Type:", selectedType)

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching costs:", error.localizedDescription)
                return
            }

            guard let data = data, !data.isEmpty else {
                print("No data received from backend. Initializing empty costs.")
                DispatchQueue.main.async {
                    self.getDefaultCategories()
                }
                return
            }

            do {
                let decodedData = try JSONDecoder().decode(WeeklyMonthlyCostResponse.self, from: data)
                print("Decoded Data:", decodedData)

                DispatchQueue.main.async {
                    if decodedData.costs.isEmpty {
                        print("No data, its empty or file does not exist")
                        self.getDefaultCategories()
                        
                    }
                    self.costItems = decodedData.costs.map { BudgetItem(category: $0.key, amount: String($0.value)) }
                }
            } catch {
                print("Failed to decode JSON:", error)
                DispatchQueue.main.async {
                    self.getDefaultCategories()
                }
            }
        }.resume()
    }




    private func checkForReset() {
        loadSavedData()
    }
    
    private func getDefaultCategories() {
        print("Setting default categories")

        let defaultItems = [
            BudgetItem(category: "Rent", amount: ""),
            BudgetItem(category: "Groceries", amount: ""),
            BudgetItem(category: "Subscriptions", amount: ""),
            BudgetItem(category: "Eating Out", amount: ""),
            BudgetItem(category: "Entertainment", amount: ""),
            BudgetItem(category: "Utilities", amount: ""),
            BudgetItem(category: "Savings", amount: ""),
            BudgetItem(category: "Miscellaneous", amount: "")
        ]

        DispatchQueue.main.async {
            self.costItems.removeAll() // Force refresh
            self.costItems = defaultItems // Assign new default values
            print("Updated costItems:", self.costItems)
        }
    }


    /*
    private func resetCosts() {
        costItems = costItems.map { BudgetItem(category: $0.category, amount: "") }
        saveToUserDefaults()
    }
     */

    private func checkBudgetWarnings() {
        budgetWarningMessage = ""
        for item in costItems {
            if let budgetLimit = budgetLimits[item.category], let costValue = Double(item.amount) {
                if costValue >= budgetLimit {
                    budgetWarningMessage += "\(item.category) exceeds the budget limit!\n"
                } else if costValue >= budgetLimit * 0.8 {
                    budgetWarningMessage += "\(item.category) is nearing the budget limit.\n"
                }
            }
        }
        showBudgetWarning = !budgetWarningMessage.isEmpty
    }
}

// MARK: - Data Model
/*
struct BudgetItem: Identifiable {
    let id = UUID()
    let category: String
    var amount: String
}
 */

//struct WeeklyMonthlyCostResponse: Codable {
//    let username: String
//    let type: String
//    let costs: [String: Double] // This ensures the costs are properly decoded
//}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}



// MARK: - Preview
#Preview {
    WeeklyMonthlyCostView()
}
