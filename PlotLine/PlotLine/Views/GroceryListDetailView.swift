import SwiftUI

struct GroceryListDetailView: View {
    var groceryList: GroceryList
    @State private var items: [GroceryItem] = [] // Array to hold grocery items
    @State private var newItemName: String = ""  // Name of the new item
    @State private var newItemQuantity: Int = 1  // Quantity for the new item

    var body: some View {
        VStack {
            Text(groceryList.name)
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()

            if items.isEmpty {
                Text("No items in this grocery list.")
                    .font(.title2)
                    .foregroundColor(.gray)
                    .padding()
            } else {
                List(items, id: \.name) { item in
                    HStack {
                        Text(item.name) // Display item name
                        Spacer()
                        Text("x\(item.quantity)") // Display item quantity
                            .foregroundColor(.gray)
                        Button(action: {
                            deleteItem(item)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }

            HStack {
                // Name input field (takes up most of the width)
                TextField("Enter new item", text: $newItemName)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: .infinity) // Take as much space as possible

                // Quantity input field (smaller width)
                TextField("Qty", value: $newItemQuantity, formatter: NumberFormatter())
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 50) // Small width for quantity field
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
        .navigationTitle("Grocery List Details")
        .onAppear {
            fetchItems()
        }
    }

    func fetchItems() {
        Task {
            do {
                let listIdString = groceryList.id.uuidString
                // Fetch items as GroceryItem objects
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
                // Create a GroceryItem object
                let newItem = GroceryItem(id: UUID(), name: newItemName, quantity: newItemQuantity, checked: false)

                // Add the new item to the backend
                try await GroceryListAPI.addItem(listId: listIdString, item: newItem)

                // Update UI
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
                // Delete the item by its name or ID
                try await GroceryListAPI.deleteItem(listId: listIdString, itemId: item.name)

                // Remove item from UI
                items.removeAll { $0.name == item.name }
            } catch {
                print("Failed to delete item: \(error)")
            }
        }
    }
}
