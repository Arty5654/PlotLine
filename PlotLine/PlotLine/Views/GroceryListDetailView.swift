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
    
    var body: some View {
        ZStack {
            VStack {
                
                // Grocery List name and share button in this HStack
                HStack {
                    Text(groceryList.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding()
                    
                    // Custom share button
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
                }

                if items.isEmpty {
                    Text("No items in this grocery list.")
                        .font(.title2)
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List {
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
                                        // When an item is tapped, show the edit view in the center
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
                        }
                        .onMove { indices, newOffset in
                            moveItem(from: indices, to: newOffset)
                        }
                    }
                    .navigationBarItems(trailing: EditButton())
                }

                // Section to add a new item
                HStack {
                    TextField("Enter new item", text: $newItemName)
                        .padding()
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: .infinity)

                    TextField("Qty", value: $newItemQuantity, formatter: NumberFormatter())
                        .padding()
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 50)
                }
                .padding()

                Button(action: {
                    addItemToList()
                }) {
                    Text("Add Item")
                        .fontWeight(.bold)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
            }

            // Conditional overlay for the custom square window
            if isEditPresented {
                Color.black.opacity(0.5) // Background dimming
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
}
