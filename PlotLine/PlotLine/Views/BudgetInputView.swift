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
    
    @State private var budgetingWarnings: String = "" // Stores warning message

    // User's income and rent fetched from backend
    @State private var userIncome: Double = 0.0
    @State private var userRent: Double = 0.0
    
    // Whether the user acknowledged warnings
    @State private var warningsAcknowledged: Bool = false
    
    // MARK: - Constants / Defaults
    private let username: String = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
    
    // For the Budget Quiz
    var prefilledBudget: [String: Double]? = nil
    
    /// Default categories to show if none stored or none on backend
    private static let defaultBudgetCategories: [BudgetItem] = [
        BudgetItem(category: "Rent", amount: ""),
        BudgetItem(category: "Groceries", amount: ""),
        BudgetItem(category: "Subscriptions", amount: ""),
        BudgetItem(category: "Eating Out", amount: ""),
        BudgetItem(category: "Entertainment", amount: ""),
        BudgetItem(category: "Utilities", amount: ""),
        BudgetItem(category: "Savings", amount: ""),
        BudgetItem(category: "Investments", amount: ""),
        BudgetItem(category: "Other", amount: "")
    ]
    
    // ("Weekly"/"Monthly") to backend param ("weekly"/"monthly")
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
            
            // Save & Clear Buttons
            HStack {
                Button(action: attemptSaveBudget) {
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
            case .warning:
                // Show warnings and let user proceed or cancel
                return Alert(
                    title: Text("⚠️ Budgeting Warning"),
                    message: Text(budgetingWarnings),
                    primaryButton: .default(Text("Proceed Anyway"), action: {
                        // User acknowledges warning => do the actual save
                        saveBudget()
                    }),
                    secondaryButton: .cancel()
                )
                
            case .saved:
                return Alert(
                    title: Text("Budget Saved"),
                    message: Text("Your \(selectedType) budget was saved successfully."),
                    dismissButton: .default(Text("OK"))
                )
                
            case .cleared:
                return Alert(
                    title: Text("Budget Cleared"),
                    message: Text("Your \(selectedType) budget was cleared and default categories have been restored."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        
        // Fetch data on first appear
        .onAppear {
            if let prefilled = prefilledBudget {
                self.budgetItems = prefilled.map { BudgetItem(category: $0.key, amount: String($0.value)) }
            } else {
                fetchIncomeData()
                fetchBudgetData()
            }
        }
    }
}

// MARK: - Methods
extension BudgetInputView {
    
    // Attempt to save budget (checks warnings first)
    private func attemptSaveBudget() {
       generateBudgetingWarnings()  // sets `budgetingWarnings`
       
       if budgetingWarnings.isEmpty {
           // No warnings? Save immediately
           saveBudget()
       } else {
           // Warnings exist => show .warning alert
           activeAlert2 = .warning
       }
   }
    
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
    
    private func fetchIncomeData() {
        let urlString = "http://localhost:8080/api/income/\(username)"
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ Error fetching income data:", error.localizedDescription)
                return
            }
            
            guard let data = data, !data.isEmpty else {
                print("⚠️ No income data found; defaulting to 0.")
                return
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(IncomeResponse.self, from: data)
                DispatchQueue.main.async {
                    self.userIncome = decodedResponse.income
                    self.userRent = decodedResponse.rent
                }
            } catch {
                print("❌ Failed to decode income data:", error)
            }
        }.resume()
    }
    
    // Save user budget data to the backend
    private func saveBudget() {
        generateBudgetingWarnings() // Generate warnings before saving
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
            print("Could not serialize budget payload to JSON.")
            return
        }
        
        let urlString = "http://localhost:8080/api/budget"
        guard let url = URL(string: urlString) else {
            print("Invalid URL for saving budget data:", urlString)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"  // or PUT if your backend requires that
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        print("Saving \(selectedType) budget data to backend...")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error saving budget data:", error.localizedDescription)
                return
            }
            print("Budget data successfully saved!")
            
            // Show "saved" alert on main thread
            DispatchQueue.main.async {
                self.activeAlert2 = .saved
                //self.generateBudgetingTips() // optional tip generation
            }
        }.resume()
    }
    
    // Generate budgeting warnings dynamically
    private func generateBudgetingWarnings() {
        budgetingWarnings = ""

        let rent = Double(budgetItems.first(where: { $0.category == "Rent" })?.amount ?? "0") ?? 0
        let savings = Double(budgetItems.first(where: { $0.category == "Savings" })?.amount ?? "0") ?? 0
        let eatingOut = Double(budgetItems.first(where: { $0.category == "Eating Out" })?.amount ?? "0") ?? 0

        if rent > userIncome * 0.3 {
            budgetingWarnings += "⚠️ Your rent exceeds 30% of your income. Consider reducing it.\n"
        }
        
        if savings < userIncome * 0.1 {
            budgetingWarnings += "⚠️ Consider increasing your savings to at least 10% of your income.\n"
        }
        
        if eatingOut > 200 {
            budgetingWarnings += "⚠️ You’re spending a lot on eating out. Try cooking at home more often.\n"
        }
        
        if !budgetingWarnings.isEmpty {
            activeAlert2 = .warning
        }
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
                //self.budgetingTips.removeAll()
            }
        }.resume()
    }
    
}

// MARK: - ActiveAlert2 Enum
fileprivate enum ActiveAlert2: Identifiable {
    case saved
    case cleared
    case warning
    
    var id: String {
        switch self {
        case .saved: return "saved"
        case .cleared: return "cleared"
        case .warning: return "warning"
        }
    }
}

struct IncomeResponse: Codable {
    let username: String
    let income: Double
    let rent: Double
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
