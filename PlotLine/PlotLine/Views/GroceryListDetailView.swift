import SwiftUI
import UIKit

struct GroceryListDetailView: View {
    var groceryList: GroceryList
    @State private var items: [GroceryItem] = [] // Array to hold grocery items
    @State private var newItemName: String = ""  // Name of the new item
    @State private var newItemQuantity: Int = 1  // Quantity for the new item

    @State private var selectedItem: GroceryItem? = nil  // Track the item selected for editing
    @State private var isEditPresented: Bool = false  // Flag to present the edit view
    
    @State private var shareSuccess: Bool? = nil // Track if sharing was successful
    @State private var canArchiveList: Bool = false // Track if the list can be archived
    @State private var archiveSuccess: Bool? = nil

    // Helper variables for the running total
    private var totalItems: Int { items.count }
    private var purchasedItems: Int { items.filter { $0.checked }.count }
    
    // Grocery cost estimates
    @State private var showGroceryAddedAlert = false
    @State private var recentlyAddedGroceryAmount: Double? = nil
    @State private var canUndoGroceryAddition = false
    
    // Calculate item text based on totalItems
    private var itemText: String {
        return totalItems == 1 ? "Item" : "Items"
    }

    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Top section with List title and share button
                    HStack {
                        Text(groceryList.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .padding()

                        Spacer()

                        Button(action: {
                            shareGroceryList()
                            shareSuccess = nil
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .imageScale(.medium)
                        }
                        .alert(isPresented: .constant(shareSuccess != nil)) {
                            Alert(
                                title: Text(shareSuccess == true ? "Share Successful" : "Share Failed"),
                                message: Text(shareSuccess == true ? "Your grocery list was shared successfully." : "There was an issue sharing the list."),
                                dismissButton: .default(Text("OK"))
                            )
                        }
                        .padding()
                    }

                    // Archive bar
                    if !items.isEmpty {
                        HStack {
                            Text("\(totalItems) \(itemText) - \(purchasedItems) Checked Off")
                                .foregroundColor(.gray)
                                .padding(.leading)

                            Spacer()

                            Button(action: {
                                archiveList()
                            }) {
                                Text("Archive")
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(canArchiveList ? Color.green : Color.gray)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .disabled(!canArchiveList)
                            .alert(isPresented: .constant(archiveSuccess != nil)) {
                                Alert(
                                    title: Text(archiveSuccess == true ? "Archive Successful" : "Archive Failed"),
                                    message: Text(archiveSuccess == true ? "Your grocery list was archived successfully." : "There was an issue archiving the list."),
                                    dismissButton: .default(Text("OK"))
                                )
                            }
                            .padding(.trailing)
                        }
                    }

                    // No items message
                    if items.isEmpty {
                        Spacer()
                        Text("No items in this grocery list.")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .padding()
                        Spacer()
                    } else {
                        VStack {
                            ForEach(items) { item in
                                HStack {
                                    Image(systemName: item.checked ? "checkmark.square" : "square")
                                        .foregroundColor(item.checked ? .green : .gray)
                                        .onTapGesture {
                                            toggleChecked(item: item)
                                        }

                                    Text(item.name)
                                        .font(.body)
                                        .strikethrough(item.checked, color: .green)
                                        .foregroundColor(item.checked ? .gray : .primary)
                                        .onTapGesture {
                                            selectedItem = item
                                            isEditPresented = true
                                        }

                                    Spacer()

                                    Text("x \(item.quantity)")
                                        .foregroundColor(.gray)

                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                        .onTapGesture {
                                            deleteItem(item)
                                        }
                                }
                                .padding(.horizontal)
                            }

                            // Done shopping button
                            Button("Done Shopping") {
                                estimateGroceryCostAndUpdateBudget()
                            }
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .alert(isPresented: $showGroceryAddedAlert) {
                                Alert(
                                    title: Text("Groceries Added"),
                                    message: Text("Added $\(recentlyAddedGroceryAmount ?? 0, specifier: "%.2f") to Weekly Groceries."),
                                    dismissButton: .default(Text("OK"))
                                )
                            }

                            // Undo grocery cost
                            if canUndoGroceryAddition, let undoAmount = recentlyAddedGroceryAmount {
                                Button("Undo Grocery Cost (-$\(undoAmount, specifier: "%.2f"))") {
                                    undoGroceryCost(username: UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser", amount: undoAmount)
                                }
                                .foregroundColor(.red)
                            }
                        }
                    }

                    // Add item input section
                    HStack {
                        TextField("Enter new item", text: $newItemName)
                            .padding(12)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                        Button(action: {
                            addItemToList()
                        }) {
                            Text("Add Item")
                                .fontWeight(.bold)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                }
            }

            // Overlay edit view
            if isEditPresented {
                Color.black.opacity(0.5)
                    .edgesIgnoringSafeArea(.all)

                GroceryItemInfoView(item: $selectedItem, onClose: {
                    isEditPresented = false
                })
            }
        }
        .navigationTitle("Grocery List Details")
        .onAppear {
            fetchItems()
        }
        .onChange(of: items) { _ in
            canArchiveList = isListCompleted()
        }
    }

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
        // Check if all items are checked off
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
                newItemName = ""  // Reset name field
                newItemQuantity = 1  // Reset quantity field
            } catch {
                print("Failed to add item: \(error)")
            }
        }
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
        // Create the text to share
        let shareText = convertGroceryListToText(groceryList: groceryList)

        // Create an ActivityViewController to share the text
        let activityViewController = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        
        activityViewController.completionWithItemsHandler = { activity, completed, items, error in
            // Update the state based on whether the share was successful or not
            shareSuccess = completed
        }

        // Get the relevant window scene
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let topController = windowScene.windows.first?.rootViewController {
            topController.present(activityViewController, animated: true, completion: nil)
        }
    }

    // Function to convert GroceryList to a text message
    func convertGroceryListToText(groceryList: GroceryList) -> String {
        var result = "Grocery List: \(groceryList.name)\n\n"
        
        for item in groceryList.items {
            // Check if item has been checked off
            if item.checked {
                result += "(PURCHASED) "
            }
            
            // Start with the quantity and name
            result += "\(item.quantity) x \(item.name)"
            
            // Handle price, store, and notes edge cases
            if let price = item.price {
                if price > 0 {
                    result += " - $\(String(format: "%.2f", price))"
                }
            }
            
            if let store = item.store, !store.isEmpty {
                result += " from \(store)"
            }
            
            if let notes = item.notes, !notes.isEmpty {
                result += " (\(notes))"
            }
            
            // Skip items where all optional fields are empty or zero
            if (item.price == 0 || item.store == nil || item.store?.isEmpty == true) && (item.notes == nil || item.notes?.isEmpty == true) {
                result += "\n"
            } else {
                result += "\n"
            }
        }
        
        return result
    }
    
    // Archive function
    func archiveList() {
        let username: String? = UserDefaults.standard.string(forKey: "loggedInUsername")
        
        GroceryListAPI.archiveGroceryList(username: username ?? "", groceryList: groceryList) { result in
            switch result {
            case .success(let message):
                // Handle success
                print("Grocery list archived successfully: \(message)")
                archiveSuccess = true // Set success flag
                
            case .failure(let error):
                // Handle failure
                print("Failed to archive grocery list: \(error.localizedDescription)")
                archiveSuccess = false // Set failure flag
            }
        }
    }
    
    func estimateGroceryCostAndUpdateBudget() {
        let username = UserDefaults.standard.string(forKey: "loggedInUsername") ?? "UnknownUser"
        let location = "Indiana" // Could be fetched from CoreLocation if available

        let groceryItems = items.map { ["name": $0.name, "quantity": $0.quantity] }

        let payload: [String: Any] = [
            "location": location,
            "items": groceryItems
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: URL(string: "http://localhost:8080/api/groceryLists/estimate-grocery-cost")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data, let cost = try? JSONDecoder().decode(Double.self, from: data) else { return }

            DispatchQueue.main.async {
                recentlyAddedGroceryAmount = cost
                addCostToWeeklyGroceries(username: username, amount: cost)
            }
        }.resume()
    }

    func addCostToWeeklyGroceries(username: String, amount: Double) {
        // Fetch current weekly costs
        let getURL = URL(string: "http://localhost:8080/api/costs/\(username)/weekly")!
        URLSession.shared.dataTask(with: getURL) { data, _, _ in
            guard let data = data,
                  var decoded = try? JSONDecoder().decode(WeeklyMonthlyCostResponse.self, from: data) else { return }

            // Add to groceries
            var current = decoded.costs["Groceries"] ?? 0.0
            current += amount
            decoded.costs["Groceries"] = current

            // Re-upload
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

            // Subtract from groceries
            var current = decoded.costs["Groceries"] ?? 0.0
            current = max(0.0, current - amount) // prevent negative cost
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

}
