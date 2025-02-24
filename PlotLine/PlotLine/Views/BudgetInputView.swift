import SwiftUI
import Foundation

struct BudgetInputView: View {
    // MARK: - State
    @State private var selectedType: String =
        UserDefaults.standard.string(forKey: "selectedType") ?? "Weekly"
    
    @State private var budgetItems: [BudgetItem] = []
    @State private var newCategory: String = ""
    
    // Single alert state: .saved or .cleared
    @State private var activeAlert2: ActiveAlert2? = nil
    
    // For optional budgeting tips
    @State private var budgetingTips: [String] = []
    
    // MARK: - Constants / Defaults
    private let username: String = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    
    /// Default categories to show if none stored or none on backend
    private static let defaultBudgetCategories: [BudgetItem] = [
        BudgetItem(category: "Rent", amount: ""),
        BudgetItem(category: "Groceries", amount: ""),
        BudgetItem(category: "Subscriptions", amount: ""),
        BudgetItem(category: "Eating Out", amount: ""),
        BudgetItem(category: "Entertainment", amount: ""),
        BudgetItem(category: "Utilities", amount: ""),
        BudgetItem(category: "Miscellaneous", amount: "")
    ]
    
    // A computed property to convert UI text ("Weekly"/"Monthly") to backend param ("weekly"/"monthly")
    private var backendType: String {
        selectedType.lowercased()
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 15) {
            Text("Create Your \(selectedType) Budget")
                .font(.title2)
                .bold()
            
            // Weekly/Monthly Picker
            Picker("Type", selection: $selectedType) {
                Text("Weekly").tag("Weekly")
                Text("Monthly").tag("Monthly")
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            // When user changes between Weekly & Monthly, fetch from backend
            .onChange(of: selectedType) { _ in
                fetchBudgetData()
                UserDefaults.standard.set(selectedType, forKey: "selectedType")
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
                        
                        // Remove row button
                        Button {
                            removeCategory(item: item)
                        } label: {
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
                Button {
                    addCategory()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding()
            
            // Display Budgeting Tips (optional)
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
                    clearAllBudget()
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
        .navigationTitle("\(selectedType) Budget")
        
        // Alert that shows either "saved" or "cleared"
        .alert(item: $activeAlert2) { alertType in
            switch alertType {
            case .saved:
                return Alert(
                    title: Text("Budget Saved"),
                    message: Text("Your \(selectedType) budget was saved successfully."),
                    dismissButton: .default(Text("OK"))
                )
            case .cleared:
                return Alert(
                    title: Text("Budget Cleared"),
                    message: Text("Your \(selectedType) budget was cleared, and default categories have been restored."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        
        // Fetch data on first appear
        .onAppear {
            fetchBudgetData()
        }
    }
}

// MARK: - Methods
extension BudgetInputView {
    
    // Add a new category row if it doesn't already exist
    private func addCategory() {
        guard !newCategory.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let lowerNew = newCategory.lowercased()
        // Check if category already exists
        if !budgetItems.contains(where: { $0.category.lowercased() == lowerNew }) {
            budgetItems.append(BudgetItem(category: newCategory, amount: ""))
        }
        newCategory = ""
    }
    
    // Remove a category from the list
    private func removeCategory(item: BudgetItem) {
        budgetItems.removeAll { $0.id == item.id }
    }
    
    // Delete using swipe
    private func deleteItems(at offsets: IndexSet) {
        budgetItems.remove(atOffsets: offsets)
    }
    
    // Fetch user budget data from the backend for Weekly or Monthly
    private func fetchBudgetData() {
        let urlString = "http://localhost:8080/api/budget/\(username)/\(backendType)"
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL: \(urlString)")
            return
        }
        
        print("📡 Fetching \(selectedType) budget data for user: \(username)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ Error fetching budget data:", error.localizedDescription)
                // If error, revert to default categories
                DispatchQueue.main.async {
                    self.budgetItems = Self.defaultBudgetCategories
                }
                return
            }
            
            guard let data = data, !data.isEmpty else {
                print("⚠️ No budget data found; using default categories.")
                DispatchQueue.main.async {
                    self.budgetItems = Self.defaultBudgetCategories
                }
                return
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(BudgetResponse.self, from: data)
                DispatchQueue.main.async {
                    // Convert [String:Double] to [BudgetItem]
                    self.budgetItems = decodedResponse.budget.map { (cat, val) in
                        BudgetItem(category: cat, amount: String(val))
                    }
                }
            } catch {
                print("❌ Failed to decode budget data:", error)
                DispatchQueue.main.async {
                    self.budgetItems = Self.defaultBudgetCategories
                }
            }
        }.resume()
    }
    
    // Save user budget data to the backend
    private func saveBudget() {
        let budgetDict = budgetItems.reduce(into: [String: Double]()) { result, item in
            if let val = Double(item.amount) {
                result[item.category] = val
            }
        }
        
        let payload: [String: Any] = [
            "username": username,
            "type": backendType, // "weekly" or "monthly"
            "budget": budgetDict
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            print("❌ Could not serialize budget payload to JSON.")
            return
        }
        
        let urlString = "http://localhost:8080/api/budget"
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL for saving budget data:", urlString)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"  // or PUT if your backend requires that
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        print("📡 Saving \(selectedType) budget data to backend...")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Error saving budget data:", error.localizedDescription)
                return
            }
            print("✅ Budget data successfully saved!")
            
            // Show "saved" alert on main thread
            DispatchQueue.main.async {
                self.activeAlert2 = .saved
                self.generateBudgetingTips() // optional tip generation
            }
        }.resume()
    }
    
    // Clear all budget data, update backend, then revert to default categories
    private func clearAllBudget() {
        let urlString = "http://localhost:8080/api/budget/\(username)/\(backendType)"
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL for clearing budget data:", urlString)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        print("❌ Clearing \(selectedType) budget data on backend...")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Error clearing budget data on backend:", error.localizedDescription)
                return
            }
            print("✅ Successfully cleared \(self.selectedType) budget data on backend.")
            
            // Revert UI to default categories
            DispatchQueue.main.async {
                self.budgetItems = Self.defaultBudgetCategories
                self.activeAlert2 = .cleared
                self.budgetingTips.removeAll()
            }
        }.resume()
    }
    
    // Generate tips after saving (optional feature)
    private func generateBudgetingTips() {
        budgetingTips.removeAll()
        
        // Example: If rent > 30% of userIncome
        if let rentVal = Double(budgetItems.first(where: { $0.category == "Rent" })?.amount ?? "0"),
           let userIncomeStr = UserDefaults.standard.string(forKey: "userIncome"),
           let userIncomeVal = Double(userIncomeStr),
           rentVal > userIncomeVal * 0.3 {
            budgetingTips.append("Your rent exceeds 30% of your income. Consider ways to reduce it.")
        }
        
        // Example: If Eating Out > $200
        if let eatingOutVal = Double(budgetItems.first(where: { $0.category == "Eating Out" })?.amount ?? "0"),
           eatingOutVal > 200 {
            budgetingTips.append("You’re spending a lot on eating out. Try cooking at home more often.")
        }
    }
}

// MARK: - ActiveAlert2 Enum
fileprivate enum ActiveAlert2: Identifiable {
    case saved
    case cleared
    
    var id: String {
        switch self {
        case .saved: return "saved"
        case .cleared: return "cleared"
        }
    }
}

// MARK: - Data Models
//struct BudgetItem: Identifiable, Codable {
//    var id = UUID()
//    let category: String
//    var amount: String
//}
//
///// Example backend responses
//struct BudgetResponse: Codable {
//    let username: String
//    let type: String
//    let budget: [String: Double]
//}
