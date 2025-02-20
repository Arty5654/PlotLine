//
//  BudgetInputView.swift
//  PlotLine
//
//  Created by Arteom Avetissian on 2/19/25.
//

import SwiftUI

struct BudgetInputView: View {
    @State private var selectedType = UserDefaults.standard.string(forKey: "selectedType") ?? "Weekly"
    @State private var budgetItems: [BudgetItem] = []
    @State private var newCategory: String = ""
    @State private var showSuccessAlert: Bool = false
    @State private var showClearConfirmation: Bool = false
    @State private var budgetingTips: [String] = []

    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        VStack(spacing: 15) {
            Text("Create Your \(selectedType) Budget")
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

            // Budget Input List
            List {
                ForEach($budgetItems) { $item in
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

            // Add a New Budget Category
            HStack {
                TextField("New Category", text: $newCategory)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button(action: addCategory) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding()

            // Display Budgeting Tips
            if !budgetingTips.isEmpty {
                VStack(alignment: .leading) {
                    Text("💡 Budgeting Tips:")
                        .font(.headline)
                        .padding(.top)
                    ForEach(budgetingTips, id: \.self) { tip in
                        Text("• \(tip)")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                    }
                }
                .padding()
            }

            // Save & Clear Buttons
            HStack {
                Button(action: saveBudget) {
                    Text("Save Budget")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }

                Button(action: {
                    showClearConfirmation = true
                }) {
                    Text("Clear All")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(10)
                }
            }
            .padding()
            .alert(isPresented: $showSuccessAlert) {
                Alert(
                    title: Text("Success"),
                    message: Text("Your \(selectedType) budget has been saved."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert(isPresented: $showClearConfirmation) {
                Alert(
                    title: Text("Confirm"),
                    message: Text("Are you sure you want to delete all budget data?"),
                    primaryButton: .destructive(Text("Delete")) {
                        clearBudget()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .padding()
        .navigationTitle("\(selectedType) Budget")
        .onAppear(perform: loadSavedData) // Load saved data when screen appears
    }

    // MARK: - Functions

    private func addCategory() {
        guard !newCategory.isEmpty else { return }
        if !budgetItems.contains(where: { $0.category.lowercased() == newCategory.lowercased() }) {
            budgetItems.append(BudgetItem(category: newCategory, amount: ""))
            saveToUserDefaults()
        }
        newCategory = ""
    }

    private func removeCategory(item: BudgetItem) {
        budgetItems.removeAll { $0.id == item.id }
        saveToUserDefaults()
    }

    private func deleteItems(at offsets: IndexSet) {
        budgetItems.remove(atOffsets: offsets)
        saveToUserDefaults()
    }

    private func saveBudget() {
        let budgetData: [String: Any] = [
            "username": username,
            "type": selectedType.lowercased(),
            "budget": budgetItems.reduce(into: [String: Double]()) { result, item in
                if let amount = Double(item.amount) {
                    result[item.category] = amount
                }
            }
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: budgetData) else { return }

        let url = URL(string: "http://localhost:8080/api/budget")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error saving budget: \(error)")
                return
            }
            DispatchQueue.main.async {
                showSuccessAlert = true
                saveToUserDefaults()
                generateBudgetingTips()
            }
        }.resume()
    }

    private func saveToUserDefaults() {
        let savedData = budgetItems.map { ["category": $0.category, "amount": $0.amount] }
        UserDefaults.standard.set(savedData, forKey: "savedBudget_\(selectedType)")
        UserDefaults.standard.set(selectedType, forKey: "selectedType")
    }

    private func loadSavedData() {
        if let savedArray = UserDefaults.standard.array(forKey: "savedBudget_\(selectedType)") as? [[String: String]] {
            budgetItems = savedArray.map { BudgetItem(category: $0["category"] ?? "", amount: $0["amount"] ?? "") }
        } else {
            budgetItems = [
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

    private func generateBudgetingTips() {
        budgetingTips.removeAll()
        if let rentAmount = Double(budgetItems.first(where: { $0.category == "Rent" })?.amount ?? "0"),
           let income = UserDefaults.standard.string(forKey: "userIncome"),
           let incomeAmount = Double(income),
           rentAmount > incomeAmount * 0.3 {
            budgetingTips.append("Your rent exceeds 30% of your income. Consider finding ways to reduce it.")
        }
        if let foodAmount = Double(budgetItems.first(where: { $0.category == "Eating Out" })?.amount ?? "0"),
           foodAmount > 200 {
            budgetingTips.append("You’re spending a lot on eating out. Try cooking at home more.")
        }
    }

    private func clearBudget() {
        budgetItems.removeAll()
        UserDefaults.standard.removeObject(forKey: "savedBudget_\(selectedType)")
        showClearConfirmation = false
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

// MARK: - Preview
#Preview {
    BudgetInputView()
}
