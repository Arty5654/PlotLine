//
//  TransactionsView.swift
//  PlotLine
//
//  Transaction management — view, edit, delete, recategorize, and revert synced transactions.
//

import SwiftUI

private let txnCategories = [
    "Rent", "Groceries", "Subscriptions", "Eating Out",
    "Entertainment", "Utilities", "Savings", "Miscellaneous",
    "Transportation", "Roth IRA", "Car Insurance",
    "Health Insurance", "Brokerage",
    "Gas", "Phone", "Internet", "Gym", "Clothing",
    "Personal Care", "Education", "Childcare", "Pet Care",
    "Home Maintenance", "Gifts", "Donations", "Travel",
    "Baby Supplies", "Hobbies", "Shopping", "Coffee",
    "Alcohol & Bars", "Home Decor", "Electronics",
    "Medical", "Dental", "Vision", "Therapy",
    "Parking", "Tolls", "Laundry", "Haircuts",
    "Streaming Services", "Gaming", "Music", "Books"
]

struct TransactionsView: View {
    @Environment(\.colorScheme) private var colorScheme
    let username: String
    let initialMonth: Date

    @State private var selectedMonth: Date
    @State private var transactions: [SyncedTransaction] = []
    @State private var isLoading = true
    @State private var editingTxn: SyncedTransaction? = nil
    @State private var editAmount: String = ""
    @State private var editCategory: String = ""
    @State private var showDeleteConfirm: SyncedTransaction? = nil
    @State private var errorMessage: String? = nil

    init(username: String, month: Date) {
        self.username = username
        self.initialMonth = month
        _selectedMonth = State(initialValue: month)
    }

    private var monthStr: String {
        let cal = Calendar.current
        let y = cal.component(.year, from: selectedMonth)
        let m = cal.component(.month, from: selectedMonth)
        return String(format: "%04d-%02d", y, m)
    }

    private var monthDisplay: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: selectedMonth)
    }

    // Group transactions by date (descending)
    private var groupedByDate: [(String, [SyncedTransaction])] {
        let dict = Dictionary(grouping: transactions) { $0.date }
        return dict.sorted { $0.key > $1.key }
    }

    private var totalSpent: Double {
        transactions.reduce(0) { $0 + $1.amount }
    }

    // All categories: from current transactions + common list, sorted
    private var allCategories: [String] {
        var cats = Set(txnCategories)
        for t in transactions { cats.insert(t.category) }
        return cats.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Month navigation
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .blue)
                }
                Spacer()
                Text(monthDisplay)
                    .font(.headline)
                Spacer()
                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))

            if isLoading {
                Spacer()
                ProgressView("Loading transactions…")
                Spacer()
            } else if transactions.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No transactions")
                        .font(.headline)
                    Text("No synced transactions for \(monthDisplay).")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                Spacer()
            } else {
                // Summary bar
                HStack {
                    Text("\(transactions.count) transactions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Total: $\(String(format: "%.2f", totalSpent))")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

                List {
                    ForEach(groupedByDate, id: \.0) { date, txns in
                        Section(header: Text(formatDateHeader(date))) {
                            ForEach(txns) { txn in
                                transactionRow(txn)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Transactions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { fetchTransactions() }
        .alert("Delete Transaction?", isPresented: Binding(
            get: { showDeleteConfirm != nil },
            set: { if !$0 { showDeleteConfirm = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let txn = showDeleteConfirm {
                    deleteTransaction(txn)
                }
            }
            Button("Cancel", role: .cancel) { showDeleteConfirm = nil }
        } message: {
            if let txn = showDeleteConfirm {
                Text("Remove \"\(txn.name)\" ($\(String(format: "%.2f", txn.amount)))? This will update your costs.")
            }
        }
        .sheet(item: $editingTxn) { txn in
            editSheet(txn)
        }
    }

    // MARK: - Month Navigation

    private func changeMonth(by delta: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) {
            selectedMonth = newMonth
            fetchTransactions()
        }
    }

    // MARK: - Row

    private func transactionRow(_ txn: SyncedTransaction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(txn.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(txn.category)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if txn.originalAmount != nil {
                        Text("(edited)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(String(format: "%.2f", txn.amount))")
                    .font(.body.monospacedDigit())
                    .fontWeight(.medium)
                if let orig = txn.originalAmount {
                    Text("was $\(String(format: "%.2f", orig))")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                        .strikethrough()
                }
            }
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showDeleteConfirm = txn
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                editAmount = String(format: "%.2f", txn.amount)
                editCategory = txn.category
                editingTxn = txn
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if txn.originalAmount != nil {
                Button {
                    revertTransaction(txn)
                } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .tint(.orange)
            }
        }
    }

    // MARK: - Edit Sheet

    private func editSheet(_ txn: SyncedTransaction) -> some View {
        NavigationView {
            Form {
                Section {
                    Text(txn.name)
                        .font(.headline)
                    Text(formatDateHeader(txn.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Amount") {
                    HStack {
                        Text("$")
                            .font(.title3)
                        TextField("Amount", text: $editAmount)
                            .keyboardType(.decimalPad)
                            .font(.title3)
                    }
                    if let orig = txn.originalAmount {
                        HStack {
                            Text("Original")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("$\(String(format: "%.2f", orig))")
                                .foregroundColor(.orange)
                        }
                        .font(.subheadline)
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $editCategory) {
                        ForEach(allCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(colorScheme == .dark ? .white : .blue)
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Text("Swipe left to edit or delete.\nSwipe right to revert edited transactions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingTxn = nil
                        errorMessage = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEdit(txn)
                    }
                }
            }
        }
    }

    // MARK: - Date formatting

    private func formatDateHeader(_ isoDate: String) -> String {
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = isoFormatter.date(from: isoDate) else { return isoDate }
        let display = DateFormatter()
        display.dateFormat = "EEEE, MMM d"
        return display.string(from: date)
    }

    // MARK: - Network

    private func fetchTransactions() {
        isLoading = true
        let urlStr = "\(BackendConfig.baseURLString)/api/costs/transactions/\(username)?month=\(monthStr)"
        guard let url = URL(string: urlStr) else { isLoading = false; return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                guard let data = data,
                      let arr = try? JSONDecoder().decode([SyncedTransaction].self, from: data) else {
                    return
                }
                transactions = arr.sorted { $0.date > $1.date }
            }
        }.resume()
    }

    private func saveEdit(_ txn: SyncedTransaction) {
        guard let newAmt = Double(editAmount), newAmt >= 0 else {
            errorMessage = "Enter a valid amount"
            return
        }
        errorMessage = nil

        let amountChanged = newAmt != txn.amount
        let categoryChanged = editCategory != txn.category

        if !amountChanged && !categoryChanged {
            editingTxn = nil
            return
        }

        // If category changed, do that first, then update amount if needed
        if categoryChanged {
            recategorize(txn, to: editCategory) {
                if amountChanged {
                    // After recategorize completes, update amount
                    updateAmount(txn, newAmount: newAmt)
                } else {
                    editingTxn = nil
                }
            }
        } else if amountChanged {
            updateAmount(txn, newAmount: newAmt)
        }
    }

    private func updateAmount(_ txn: SyncedTransaction, newAmount: Double) {
        let urlStr = "\(BackendConfig.baseURLString)/api/costs/transactions/\(username)/\(txn.id)?month=\(monthStr)"
        guard let url = URL(string: urlStr) else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["amount": newAmount]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            DispatchQueue.main.async {
                if (200...299).contains(code) {
                    if let idx = transactions.firstIndex(where: { $0.id == txn.id }) {
                        if transactions[idx].originalAmount == nil {
                            transactions[idx].originalAmount = txn.amount
                        }
                        transactions[idx].amount = newAmount
                    }
                    editingTxn = nil
                } else {
                    errorMessage = "Failed to save amount (HTTP \(code))"
                }
            }
        }.resume()
    }

    private func recategorize(_ txn: SyncedTransaction, to newCategory: String, completion: @escaping () -> Void) {
        let urlStr = "\(BackendConfig.baseURLString)/api/costs/transactions/\(username)/\(txn.id)/category?month=\(monthStr)"
        guard let url = URL(string: urlStr) else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["category": newCategory]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            DispatchQueue.main.async {
                if (200...299).contains(code) {
                    if let idx = transactions.firstIndex(where: { $0.id == txn.id }) {
                        transactions[idx].category = newCategory
                    }
                    completion()
                } else {
                    errorMessage = "Failed to change category (HTTP \(code))"
                }
            }
        }.resume()
    }

    private func revertTransaction(_ txn: SyncedTransaction) {
        let urlStr = "\(BackendConfig.baseURLString)/api/costs/transactions/\(username)/\(txn.id)/revert?month=\(monthStr)"
        guard let url = URL(string: urlStr) else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "POST"

        URLSession.shared.dataTask(with: req) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            DispatchQueue.main.async {
                if (200...299).contains(code) {
                    if let idx = transactions.firstIndex(where: { $0.id == txn.id }),
                       let orig = transactions[idx].originalAmount {
                        transactions[idx].amount = orig
                        transactions[idx].originalAmount = nil
                    }
                }
            }
        }.resume()
    }

    private func deleteTransaction(_ txn: SyncedTransaction) {
        let urlStr = "\(BackendConfig.baseURLString)/api/costs/transactions/\(username)/\(txn.id)?month=\(monthStr)"
        guard let url = URL(string: urlStr) else { return }
        var req = URLRequest(url: url)
        BackendConfig.addApiKey(to: &req)
        req.httpMethod = "DELETE"

        URLSession.shared.dataTask(with: req) { _, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            DispatchQueue.main.async {
                if (200...299).contains(code) {
                    transactions.removeAll { $0.id == txn.id }
                }
                showDeleteConfirm = nil
            }
        }.resume()
    }
}

// MARK: - Model

struct SyncedTransaction: Codable, Identifiable {
    let id: String
    let name: String
    var amount: Double
    var category: String
    let date: String
    let source: String?
    var originalAmount: Double?
}
