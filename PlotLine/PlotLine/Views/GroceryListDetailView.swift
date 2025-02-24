//
//  GroceryListDetailView.swift
//  PlotLine
//
//  Created by Yash Mehta on 2/22/25.
//

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
                List(items, id: \.id) { item in
                    HStack {
                        // Toggle check mark when the user taps on the item
                        Button(action: {}) {
                            Image(systemName: item.checked ? "checkmark.square" : "square")
                                .foregroundColor(item.checked ? .green : .gray)
                        }
                        .onTapGesture {
                            toggleChecked(item: item)
                        }

                        Text(item.name)
                            .font(.body)
                            .foregroundStyle(Color.primary.opacity(item.checked ? 0.5 : 1))
                            .strikethrough(item.checked)

                        Spacer()

                        Text("x \(item.quantity)") // Display item quantity
                            .foregroundColor(.gray)

                        // Delete the item when the trash icon is clicked
                        Button(action: {}) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .onTapGesture {
                            deleteItem(item)
                        }
                    }
                }
            }

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
                let newItem = GroceryItem(id: UUID(), name: newItemName, quantity: newItemQuantity, checked: false)

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
                let updatedItem = GroceryItem(id: item.id, name: item.name, quantity: item.quantity, checked: !item.checked)

                // Toggle the item checked status on the backend
                try await GroceryListAPI.toggleChecked(listId: listIdString, itemId: item.id.uuidString)

                // Update the item locally
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index] = updatedItem
                }
            } catch {
                print("Failed to toggle checked status: \(error)")
            }
        }
    }
}
