import SwiftUI

struct SpendingPeriodView: View {
    @State private var spendingItems: [BudgetItem] = []
    @State private var newCategory: String = ""
    
    // Instead of two separate Bool flags, we use one enum-based alert:
    @State private var activeAlert2: ActiveAlert2? = nil
    
    @State private var startDate: Date = Date()
    @State private var endDate: Date =
        Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    private var username: String {
        return UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    }

    var body: some View {
        VStack(spacing: 15) {
            Text("Enter Spending for a Specific Time Period")
                .font(.title2)
                .bold()

            // 📅 Start & End Date Pickers
            VStack {
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding()

                DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding()
            }

            // 📝 Expense Inputs
            List {
                ForEach($spendingItems) { $item in
                    HStack {
                        Text(item.category)
                            .frame(width: 120, alignment: .leading)
                        TextField("Amount ($)", text: $item.amount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        // Remove button
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

            // ➕ Add New Category
            HStack {
                TextField("New Category", text: $newCategory)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button(action: addCategory) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding()

            // 💾 Save & Clear Buttons
            HStack {
                Button(action: saveSpending) {
                    Text("Save Spending")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }

                Button(action: {
                    // Instead of setting showClearConfirmation = true,
                    // we set our single enum-based alert
                    activeAlert2 = .clearConfirmation
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
        }
        .padding()
        .navigationTitle("Spending Input")
        .onAppear {
            loadSpendingData()
        }
        
        // Fetch data when date changes
        .onChange(of: startDate) {
            loadSpendingData()
        }
        .onChange(of: endDate) {
            loadSpendingData()
        }
        
        // MARK: - Single Alert for "Success" or "Clear Confirmation"
        .alert(item: $activeAlert2) { whichAlert in
            switch whichAlert {
            case .success:
                return Alert(
                    title: Text("Success"),
                    message: Text("Your spending for \(formatDate(startDate)) to \(formatDate(endDate)) has been saved."),
                    dismissButton: .default(Text("OK"))
                )
                
            case .clearConfirmation:
                return Alert(
                    title: Text("⚠️ Confirm"),
                    message: Text("Are you sure you want to delete all spending data for \(formatDate(startDate)) to \(formatDate(endDate))?"),
                    primaryButton: .destructive(Text("Delete")) {
                        clearSpending()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    // MARK: - Functions

    private func addCategory() {
        guard !newCategory.isEmpty else { return }
        if !spendingItems.contains(where: { $0.category.lowercased() == newCategory.lowercased() }) {
            spendingItems.append(BudgetItem(category: newCategory, amount: ""))
        }
        newCategory = ""
    }

    private func removeCategory(item: BudgetItem) {
        spendingItems.removeAll { $0.id == item.id }
    }

    private func deleteItems(at offsets: IndexSet) {
        spendingItems.remove(atOffsets: offsets)
    }

    // 💾 Save Spending Data
    private func saveSpending() {
        let spendingData: [String: Any] = [
            "username": username,
            "startDate": formatDate(startDate),
            "endDate": formatDate(endDate),
            "spending": spendingItems.reduce(into: [String: Double]()) { result, item in
                if let amount = Double(item.amount) {
                    result[item.category] = amount
                }
            }
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: spendingData) else { return }

        let url = URL(string: "\(BackendConfig.baseURLString)/api/spending")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error saving spending: \(error)")
                return
            }
            DispatchQueue.main.async {
                // Instead of showSuccessAlert = true, set activeAlert2 = .success
                activeAlert2 = .success
            }
        }.resume()
    }

    // 📡 Fetch Spending Data or Set Default
    private func loadSpendingData() {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/spending/\(username)/\(formatDate(startDate))/\(formatDate(endDate))") else {
            print("Invalid URL for spending data")
            return
        }

        print("📡 Fetching spending data for \(username) from \(formatDate(startDate)) to \(formatDate(endDate))")

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching spending:", error.localizedDescription)
                return
            }

            guard let data = data, !data.isEmpty else {
                print("No spending data found, using default categories.")
                DispatchQueue.main.async {
                    self.setDefaultSpending()
                }
                return
            }
            
            // Print raw JSON to debug
            if let jsonString = String(data: data, encoding: .utf8) {
                print(" Raw JSON Response: \(jsonString)")
            }

            do {
                let decodedResponse = try JSONDecoder().decode(SpendingResponse.self, from: data)
                DispatchQueue.main.async {
                    if decodedResponse.spending.isEmpty {
                        print("⚠️ No spending data found, using default categories.")
                        self.setDefaultSpending()
                    } else {
                        self.spendingItems = decodedResponse.spending.map {
                            BudgetItem(category: $0.key, amount: String($0.value))
                        }
                    }
                }
            } catch {
                print("Failed to decode spending data:", error)
                DispatchQueue.main.async {
                    self.setDefaultSpending()
                }
            }
        }.resume()
    }

    // 🗑 Clear Spending & Reset Defaults
    private func clearSpending() {
        guard let url = URL(string: "\(BackendConfig.baseURLString)/api/spending/\(username)/\(formatDate(startDate))/\(formatDate(endDate))") else {
            print("❌ Invalid URL for deleting spending")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Error deleting spending:", error.localizedDescription)
                return
            }
            DispatchQueue.main.async {
                print("✅ Spending data deleted from backend.")
                self.setDefaultSpending()
            }
        }.resume()
    }

    // 🆕 Set Default Spending Categories
    private func setDefaultSpending() {
        self.spendingItems = [
            BudgetItem(category: "Travel", amount: ""),
            BudgetItem(category: "Shopping", amount: ""),
            BudgetItem(category: "Dining Out", amount: ""),
            BudgetItem(category: "Entertainment", amount: ""),
            BudgetItem(category: "Miscellaneous", amount: "")
        ]
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Enum for Single Alert
fileprivate enum ActiveAlert2: Identifiable {
    case success
    case clearConfirmation
    
    var id: String {
        switch self {
        case .success: return "success"
        case .clearConfirmation: return "clearConfirmation"
        }
    }
}

//// MARK: - Data Models
struct SpendingResponse: Codable {
    let username: String
    let startDate: String
    let endDate: String
    let spending: [String: Double]
}
//
//struct BudgetItem: Identifiable {
//    let id = UUID()
//    let category: String
//    var amount: String
//}
