import SwiftUI
import UIKit

// MARK: - Local design tokens
private enum PLColor {
    static let surface       = Color(.secondarySystemBackground)
    static let cardBorder    = Color.black.opacity(0.08)
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let accent        = Color.blue
    static let success       = Color.green
    static let danger        = Color.red
    static let warning       = Color.orange
}
private enum PLSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}
private enum PLRadius { static let md: CGFloat = 12 }

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PLSpacing.md)
            .background(PLColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
            .overlay(RoundedRectangle(cornerRadius: PLRadius.md).stroke(PLColor.cardBorder))
    }
}
private extension View { func plCard() -> some View { modifier(CardModifier()) } }

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(PLColor.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}
private struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(PLColor.success.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PLRadius.md))
    }
}

// MARK: - View
struct GroceryListDetailView: View {
    var groceryList: GroceryList
    
    @Environment(\.presentationMode) var presentationMode

    @State private var items: [GroceryItem] = []
    @State private var newItemName: String = ""
    @State private var newItemQuantity: Int = 1

    @State private var selectedItem: GroceryItem? = nil
    @State private var isEditPresented: Bool = false
    
    @State private var shareSuccess: Bool? = nil
    @State private var canArchiveList: Bool = false
    @State private var archiveSuccess: Bool? = nil

    private var totalItems: Int { items.count }
    private var purchasedItems: Int { items.filter { $0.checked }.count }
    private var completionRatio: Double {
        guard totalItems > 0 else { return 0 }
        return Double(purchasedItems) / Double(totalItems)
    }
    
    @State private var showGroceryAddedAlert = false
    @State private var recentlyAddedGroceryAmount: Double? = nil
    @State private var canUndoGroceryAddition = false
    
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    @State private var dietaryMessage: String? = nil
    @State private var showDietaryInfo: Bool = false
    @State private var showMealCreatedAlert: Bool = false
    @State private var mealCreatedMessage: String = ""
    
    @State private var groceryBudget: Double? = nil
    
    @AppStorage private var savedEstimate: Double
    init(groceryList: GroceryList) {
        self.groceryList = groceryList
        _savedEstimate = AppStorage(wrappedValue: 0, "estimate-\(groceryList.id.uuidString)")
    }
    
    private var itemText: String { totalItems == 1 ? "Item" : "Items" }

    var body: some View {
        VStack(spacing: PLSpacing.md) {
            ScrollView {
                VStack(spacing: PLSpacing.lg) {
                    // Header
                    HStack(alignment: .center, spacing: PLSpacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(groceryList.name)
                                .font(.title2).bold()
                            if let mealName = groceryList.mealName {
                                Text(mealName)
                                    .font(.subheadline)
                                    .foregroundColor(PLColor.textSecondary)
                                    .lineLimit(1)
                            } else {
                                Text("No meal attached")
                                    .font(.subheadline)
                                    .foregroundColor(PLColor.textSecondary)
                            }
                        }
                        Spacer()
                        if let budget = groceryBudget {
                            let currentTotal = items.reduce(0.0) { $0 + ($1.price ?? 0.0) }
                            HStack(spacing: 6) {
                                Image(systemName: "dollarsign.circle")
                                Text("\(currentTotal, specifier: "%.2f") / \(budget, specifier: "%.2f")")
                            }
                            .font(.caption)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background((currentTotal > budget ? PLColor.danger.opacity(0.12) : PLColor.success.opacity(0.12)))
                            .foregroundColor(currentTotal > budget ? PLColor.danger : PLColor.success)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Button {
                            shareGroceryList()
                            shareSuccess = nil
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.headline)
                        }
                    }
                    .plCard()
                    
                    // Progress / Archive bar
                    if totalItems > 0 {
                        VStack(alignment: .leading, spacing: PLSpacing.sm) {
                            HStack {
                                Text("\(totalItems) \(itemText) • \(purchasedItems) checked")
                                    .foregroundColor(PLColor.textSecondary)
                                Spacer()
                                Button {
                                    archiveList()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "archivebox.fill")
                                        Text("Archive")
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background((canArchiveList ? PLColor.success : Color.gray))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .disabled(!canArchiveList)
                            }
                            
                            ProgressView(value: completionRatio)
                                .tint(canArchiveList ? PLColor.success : PLColor.accent)
                        }
                        .plCard()
                    }
                    
                    // Items list
                    if items.isEmpty {
                        VStack(spacing: 8) {
                            Text("No items in this grocery list.")
                                .font(.headline)
                                .foregroundColor(PLColor.textSecondary)
                            Text("Add an item below to get started.")
                                .font(.caption)
                                .foregroundColor(PLColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .plCard()
                    } else {
                        VStack(spacing: 8) {
                            ForEach(items) { item in
                                HStack(spacing: PLSpacing.md) {
                                    Button {
                                        toggleChecked(item: item)
                                    } label: {
                                        Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                                            .foregroundColor(item.checked ? PLColor.success : PLColor.textSecondary)
                                            .font(.title3)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.body)
                                            .strikethrough(item.checked, color: PLColor.success)
                                            .foregroundColor(item.checked ? PLColor.textSecondary : PLColor.textPrimary)
                                            .onTapGesture {
                                                selectedItem = item
                                                isEditPresented = true
                                            }
                                        HStack(spacing: 10) {
                                            Text("Qty: \(item.quantity)")
                                                .foregroundColor(PLColor.textSecondary)
                                                .font(.caption)
                                            if let price = item.price, price > 0 {
                                                Text("$\(price, specifier: "%.2f")")
                                                    .font(.caption)
                                                    .foregroundColor(PLColor.textSecondary)
                                            }
                                            if let store = item.store, !store.isEmpty {
                                                Text(store)
                                                    .font(.caption)
                                                    .foregroundColor(PLColor.textSecondary)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        deleteItem(item)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(PLColor.danger)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 8)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(PLColor.cardBorder))
                            }
                        }
                        .plCard()
                    }
                    
                    // Actions (Generate meal / Done shopping)
                    if !items.isEmpty {
                        HStack(spacing: PLSpacing.md) {
                            Button {
                                generateMealFromListView()
                            } label: {
                                HStack(spacing: 8) {
                                    if isGenerating { ProgressView() }
                                    Image(systemName: "sparkles")
                                    Text(isGenerating ? "Generating…" : "Generate Meal")
                                }
                            }
                            .buttonStyle(PrimaryButton())
                            .disabled(isGenerating)
                            .opacity(isGenerating ? 0.75 : 1)
                            
                            Button {
                                checkallItems()
                                estimateGroceryCostAndUpdateBudget()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Done Shopping")
                                }
                            }
                            .buttonStyle(SecondaryButton())
                        }
                        .plCard()
                    }
                    
                    // Undo banner
                    if canUndoGroceryAddition, let undoAmount = recentlyAddedGroceryAmount {
                        HStack(spacing: PLSpacing.md) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .foregroundColor(PLColor.warning)
                            Text("Added $\(undoAmount, specifier: "%.2f") to Weekly Groceries")
                                .font(.subheadline)
                            Spacer()
                            Button("Undo") {
                                undoGroceryCost(
                                    username: UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser",
                                    amount: undoAmount
                                )
                            }
                            .foregroundColor(PLColor.danger)
                        }
                        .padding(.horizontal, PLSpacing.md)
                        .padding(.vertical, 10)
                        .background(PLColor.warning.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 2)
                    }
                    
                    // Add item
                    VStack(spacing: PLSpacing.sm) {
                        Text("Add Item")
                            .font(.headline)
                        HStack(spacing: PLSpacing.sm) {
                            TextField("e.g., Eggs", text: $newItemName)
                                .textFieldStyle(.roundedBorder)
                            Stepper(value: $newItemQuantity, in: 1...999) {
                                Text("Qty \(newItemQuantity)")
                                    .frame(minWidth: 70, alignment: .trailing)
                            }
                        }
                        Button {
                            addItemToList()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add to List")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButton())
                        .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
                    }
                    .plCard()
                }
                .padding(.horizontal, PLSpacing.lg)
                .padding(.top, PLSpacing.lg)
            }

            // Overlay editor (unchanged behavior)
            if isEditPresented {
                Color.black.opacity(0.45).ignoresSafeArea()
                GroceryItemInfoView(item: $selectedItem, onClose: {
                    isEditPresented = false
                })
            }
            
            if showDietaryInfo {
                Text(dietaryMessage ?? "")
                    .foregroundColor(PLColor.danger)
                    .padding(.bottom, PLSpacing.sm)
            }
        }
        .navigationTitle("Grocery List Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchItems()
            fetchGroceryBudget()
        }
        .onChange(of: items) { _ in
            canArchiveList = isListCompleted()
        }
        // Alerts (unchanged)
        .alert("Share Result", isPresented: .constant(shareSuccess != nil)) {
            Button("OK") { shareSuccess = nil }
        } message: {
            Text(shareSuccess == true ? "Your grocery list was shared successfully." : "There was an issue sharing the list.")
        }
        .alert("Archive Result", isPresented: .constant(archiveSuccess != nil)) {
            Button("OK") { archiveSuccess = nil }
        } message: {
            Text(archiveSuccess == true ? "Your grocery list was archived successfully." : "There was an issue archiving the list.")
        }
        .alert("Groceries Added", isPresented: $showGroceryAddedAlert) {
            Button("OK") { }
        } message: {
            Text("Added $\(recentlyAddedGroceryAmount ?? 0, specifier: "%.2f") to Weekly Groceries.")
        }
        .alert("Meal Created", isPresented: $showMealCreatedAlert) {
            Button("OK") { }
        } message: {
            Text(mealCreatedMessage)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Your logic (UNTOUCHED)
    func fetchItems() {
        Task {
            do {
                let listIdString = groceryList.id.uuidString
                let fetchedItems = try await GroceryListAPI.getItems(listId: listIdString)
                items = fetchedItems
            } catch {
                print("Failed to fetch items: \(error)")
            }
        }
    }

    func isListCompleted() -> Bool {
        return !items.isEmpty && items.allSatisfy { $0.checked }
    }

    func addItemToList() {
        guard !newItemName.isEmpty else { return }

        Task {
            do {
                let listIdString = groceryList.id.uuidString
                let newItem = GroceryItem(listId: groceryList.id, id: UUID(), name: newItemName, quantity: newItemQuantity, checked: false, price: nil, store: "", notes: "")

                try await GroceryListAPI.addItem(listId: listIdString, item: newItem)

                items.append(newItem)
                estimateCostForNewItem(itemID: newItem.id, name: newItem.name, quantity: newItem.quantity)
                newItemName = ""
                newItemQuantity = 1
            } catch {
                print("Failed to add item: \(error)")
            }
        }
    }
    
    func estimateCostForNewItem(itemID: UUID, name: String, quantity: Int) {
        let payload: [String: Any] = [
            "location": "Indiana",
            "items": [["name": name, "quantity": quantity]]
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        
        var request = URLRequest(
            url: URL(string: "http://localhost:8080/api/groceryLists/estimate-grocery-cost-live")!
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let estimatedCost = try? JSONDecoder().decode(Double.self, from: data)
            else {
                DispatchQueue.main.async {
                    errorMessage = "Unable to estimate price for '\(name)'."
                    showError = true
                }
                return
            }
            
            DispatchQueue.main.async {
                if let idx = items.firstIndex(where: { $0.id == itemID }) {
                    items[idx].price = estimatedCost
                    savedEstimate = items.reduce(0.0){ $0 + ($1.price ?? 0.0) }
                }
            }
        }.resume()
    }

    func deleteItem(_ item: GroceryItem) {
        Task {
            do {
                let listIdString = groceryList.id.uuidString
                try await GroceryListAPI.deleteItem(listId: listIdString, itemId: item.id.uuidString)
                items.removeAll { $0.id == item.id }
            } catch {
                print("Failed to delete item: \(error)")
            }
        }
    }

    func toggleChecked(item: GroceryItem) {
        Task {
            do {
                let listIdString = groceryList.id.uuidString
                let updatedItem = GroceryItem(listId: groceryList.id, id: item.id, name: item.name, quantity: item.quantity, checked: !item.checked, price: item.price, store: item.store, notes: item.notes)
                try await GroceryListAPI.toggleChecked(listId: listIdString, itemId: item.id.uuidString)
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index] = updatedItem
                }
            } catch {
                print("Failed to toggle checked status: \(error)")
            }
        }
    }

    func moveItem(from indices: IndexSet, to newOffset: Int) {
        Task {
            do {
                items.move(fromOffsets: indices, toOffset: newOffset)
                try await GroceryListAPI.updateItemOrder(listId: groceryList.id.uuidString, reorderedItems: items)
            } catch {
                print("Failed to reorder items: \(error)")
            }
        }
    }

    func shareGroceryList() {
        let shareText = convertGroceryListToText(groceryList: groceryList)
        let activityViewController = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        activityViewController.completionWithItemsHandler = { _, completed, _, _ in
            shareSuccess = completed
        }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let topController = windowScene.windows.first?.rootViewController {
            topController.present(activityViewController, animated: true, completion: nil)
        }
    }

    func convertGroceryListToText(groceryList: GroceryList) -> String {
        var result = "Grocery List: \(groceryList.name)\n\n"
        for item in groceryList.items {
            if item.checked { result += "(PURCHASED) " }
            result += "\(item.quantity) x \(item.name)"
            if let price = item.price, price > 0 {
                result += " - $\(String(format: "%.2f", price))"
            }
            if let store = item.store, !store.isEmpty {
                result += " from \(store)"
            }
            if let notes = item.notes, !notes.isEmpty {
                result += " (\(notes))"
            }
            result += "\n"
        }
        return result
    }
    
    func archiveList() {
        let username: String? = UserDefaults.standard.string(forKey: "loggedInUsername")
        GroceryListAPI.archiveGroceryList(username: username ?? "", groceryList: groceryList) { result in
            switch result {
            case .success:
                archiveSuccess = true
            case .failure(let error):
                print("Failed to archive grocery list: \(error.localizedDescription)")
                archiveSuccess = false
            }
        }
    }
    
    func estimateGroceryCostAndUpdateBudget() {
        let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
        let totalToAdd = items.reduce(0.0) { $0 + ($1.price ?? 0.0) }
        recentlyAddedGroceryAmount = totalToAdd
        addCostToWeeklyGroceries(username: username, amount: totalToAdd)
        showGroceryAddedAlert = true
        canUndoGroceryAddition = true
    }

    func addCostToWeeklyGroceries(username: String, amount: Double) {
        let getURL = URL(string: "http://localhost:8080/api/costs/\(username)/weekly")!
        URLSession.shared.dataTask(with: getURL) { data, _, _ in
            guard let data = data,
                  var decoded = try? JSONDecoder().decode(WeeklyMonthlyCostResponse.self, from: data) else { return }
            var current = decoded.costs["Groceries"] ?? 0.0
            current += amount
            decoded.costs["Groceries"] = current

            let uploadPayload: [String: Any] = [
                "username": username,
                "type": "weekly",
                "costs": decoded.costs
            ]
            guard let newJson = try? JSONSerialization.data(withJSONObject: uploadPayload) else { return }

            var uploadRequest = URLRequest(url: URL(string: "http://localhost:8080/api/costs")!)
            uploadRequest.httpMethod = "POST"
            uploadRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            uploadRequest.httpBody = newJson

            URLSession.shared.dataTask(with: uploadRequest) { _, _, _ in
                DispatchQueue.main.async {
                    showGroceryAddedAlert = true
                    canUndoGroceryAddition = true
                }
            }.resume()
        }.resume()
    }
    
    func undoGroceryCost(username: String, amount: Double) {
        let getURL = URL(string: "http://localhost:8080/api/costs/\(username)/weekly")!
        URLSession.shared.dataTask(with: getURL) { data, _, _ in
            guard let data = data,
                  var decoded = try? JSONDecoder().decode(WeeklyMonthlyCostResponse.self, from: data) else { return }
            var current = decoded.costs["Groceries"] ?? 0.0
            current = max(0.0, current - amount)
            decoded.costs["Groceries"] = current

            let uploadPayload: [String: Any] = [
                "username": username,
                "type": "weekly",
                "costs": decoded.costs
            ]
            guard let newJson = try? JSONSerialization.data(withJSONObject: uploadPayload) else { return }

            var uploadRequest = URLRequest(url: URL(string: "http://localhost:8080/api/costs")!)
            uploadRequest.httpMethod = "POST"
            uploadRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            uploadRequest.httpBody = newJson

            URLSession.shared.dataTask(with: uploadRequest) { _, _, _ in
                DispatchQueue.main.async {
                    canUndoGroceryAddition = false
                    recentlyAddedGroceryAmount = nil
                }
            }.resume()
        }.resume()
    }
    
    func checkallItems() {
        Task {
            let uncheckedItems = items.filter { !$0.checked }
            if uncheckedItems.isEmpty { return }
            for item in uncheckedItems {
                do {
                    let listIdString = groceryList.id.uuidString
                    try await GroceryListAPI.toggleChecked(listId: listIdString, itemId: item.id.uuidString)
                    await MainActor.run {
                        if let index = items.firstIndex(where: { $0.id == item.id }) {
                            let updatedItem = GroceryItem(
                                listId: groceryList.id,
                                id: item.id,
                                name: item.name,
                                quantity: item.quantity,
                                checked: true,
                                price: item.price,
                                store: item.store,
                                notes: item.notes
                            )
                            items[index] = updatedItem
                        }
                    }
                    try await Task.sleep(nanoseconds: 200_000_000)
                } catch {
                    print("Failed to check off item \(item.name): \(error)")
                }
            }
        }
    }
    
    func generateMealFromListView() -> [(name: String, quantity: Int)] {
        let listItems = items
        var items_short: [(name: String, quantity: Int)] = []
        listItems.forEach { item in items_short.append((item.name, item.quantity)) }
        generateMealFromList(groceryListItems: items_short)
        return items_short
    }
    
    func fetchGroceryBudget() {
        let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
        let url = URL(string: "http://localhost:8080/api/budget/\(username)/monthly/groceries")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
                  let budget = result["Groceries"] else { return }
            DispatchQueue.main.async { groceryBudget = budget }
        }.resume()
    }

    private func generateMealFromList(groceryListItems: [(name: String, quantity: Int)]) {
        guard !groceryListItems.isEmpty else { return }
        isGenerating = true
        Task {
            do {
                let result = try await GroceryListAPI.generateMealFromList(listID: groceryList.id.uuidString, groceryListItems: groceryListItems)
                await MainActor.run {
                    isGenerating = false
                    if let incompatiblePrefix = result.range(of: "INCOMPATIBLE:") {
                        let json = String(result[incompatiblePrefix.upperBound...])
                        if let data = json.data(using: .utf8),
                           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let reason = dict["reason"] as? String {
                            dietaryMessage = "This meal cannot be made with your dietary restrictions: \n\n \(reason)"
                            showDietaryInfo = true
                            errorMessage = "Cannot create meal: \(reason)"
                            showError = true
                        } else {
                            dietaryMessage = "This meal is not compatible with your dietary restrictions."
                            showDietaryInfo = true
                            errorMessage = "This meal is not compatible with your dietary restrictions."
                            showError = true
                        }
                    } else if let modPrefix = result.range(of: "MODIFIED:") {
                        let json = String(result[modPrefix.upperBound...])
                        if let data = json.data(using: .utf8),
                           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let modifications = dict["modifications"] as? String {
                            dietaryMessage = "We've adjusted this recipe to match your dietary preferences: \n\n \(modifications)"
                            showDietaryInfo = true
                            mealCreatedMessage = "A new meal has been created with adjustments to match your dietary preferences."
                            showMealCreatedAlert = true
                        } else {
                            mealCreatedMessage = "A new meal has been created successfully!"
                            showMealCreatedAlert = true
                        }
                        onMealCreated?()
                    } else {
                        mealCreatedMessage = "A new meal has been created successfully!"
                        showMealCreatedAlert = true
                        onMealCreated?()
                    }
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                    showError = true
                    print("Error generating meal: \(error)")
                }
            }
        }
    }

    var onMealCreated: (() -> Void)?
}
