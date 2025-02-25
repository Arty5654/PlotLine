import SwiftUI

struct GroceryItemInfoView: View {
    @Binding var item: GroceryItem?
    var onClose: () -> Void
    
    // State vars to track whether we are editing the item
    @State private var isEditing = false
    @State private var priceWarning = "" // Track price warning message
    @State private var quantityWarning = "" // Track quantity warning message
    @State private var isSaveDisabled = false // Track if Save button should be disabled
    
    // Update Save button state (disabled if there's a warning on either price or quantity)
    private func updateSaveButtonState() {
        if !priceWarning.isEmpty || !quantityWarning.isEmpty {
            isSaveDisabled = true
        } else {
            isSaveDisabled = false
        }
    }
    
    var body: some View {
        VStack {
            HStack {
                Text(isEditing ? "Edit Item" : "View Item")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding()

                Spacer()

                Button(action: {
                    if !priceWarning.isEmpty || !quantityWarning.isEmpty {
                        // If there's a warning, do not allow the user to save
                        return
                    }

                    if isEditing {
                        // When Done is clicked, update the item
                        Task {
                            await updateItemInBackend()
                        }
                    }
                    isEditing.toggle()
                }) {
                    Text(isEditing ? "Save" : "Edit")
                        .fontWeight(.bold)
                        .padding()
                        .background(!isEditing ? Color.blue : (isSaveDisabled ? Color.green.opacity(0.5) : Color.green))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(isSaveDisabled) // Disable Save button if there are warnings
            }

            // Editable or non-editable form
            VStack(spacing: 20) {
                // Item Name
                HStack {
                    Text("Item Name:")
                        .frame(width: 100, alignment: .leading)
                    if isEditing {
                        TextField("Item Name", text: Binding(
                            get: { item?.name ?? "" },
                            set: { item?.name = $0 }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 180)
                    } else {
                        Text(item?.name ?? "No name set")
                            .frame(width: 180, alignment: .leading)
                    }
                }

                // Quantity
                HStack {
                    Text("Quantity:")
                        .frame(width: 100, alignment: .leading)
                    if isEditing {
                        TextField("Quantity", text: Binding(
                            get: { item?.quantity != nil ? String(item?.quantity ?? 0) : "" },
                            set: { input in
                                let validInput = validateQuantityInput(input)
                                item?.quantity = Int(validInput) ?? 0
                                updateSaveButtonState()
                            }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 180)
                    } else {
                        Text("\(item?.quantity ?? 1)")
                            .frame(width: 180, alignment: .leading)
                    }
                }

                // Price
                HStack {
                    Text("Price:")
                        .frame(width: 100, alignment: .leading)
                    if isEditing {
                        TextField("Price", text: Binding(
                            get: { item?.price != nil ? String(item?.price ?? 0.0) : "" },
                            set: { input in
                                let validInput = validatePriceInput(input)
                                item?.price = Double(validInput) ?? 0.0
                                updateSaveButtonState()
                            }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 180)
                    } else {
                        // Format the price with a dollar sign and 2 decimal places
                        Text(item?.price == 0.0 || item?.price == nil ? "No price set" : priceFormatter.string(from: NSNumber(value: item?.price ?? 0.0)) ?? "No price set")
                            .frame(width: 180, alignment: .leading)
                    }
                }

                // Store
                HStack {
                    Text("Store:")
                        .frame(width: 100, alignment: .leading)
                    if isEditing {
                        TextField("Store", text: Binding(
                            get: { item?.store ?? "" },
                            set: { item?.store = $0 }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 180)
                    } else {
                        Text(item?.store?.isEmpty ?? true ? "No store set" : item?.store ?? "No store set")
                            .frame(width: 180, alignment: .leading)
                    }
                }

                // Notes
                HStack {
                    Text("Notes:")
                        .frame(width: 100, alignment: .leading)
                    if isEditing {
                        TextField("Notes", text: Binding(
                            get: { item?.notes ?? "" },
                            set: { item?.notes = $0 }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 180)
                    } else {
                        Text(item?.notes?.isEmpty ?? true ? "No notes set" : item?.notes ?? "No notes set")
                            .frame(width: 180, alignment: .leading)
                    }
                }
            }
            
            // Warning messages with fixed height box
            VStack {
                // Empty warning box, fixed height
                VStack {
                    if !priceWarning.isEmpty {
                        Text(priceWarning)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.top, 5)
                    }
                    if !quantityWarning.isEmpty {
                        Text(quantityWarning)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.top, 5)
                    }
                }
                .frame(height: 40) // Set a fixed height for the warning box
                .padding(.top, 10) // Optional: add some top padding for spacing
            }

            // Close Button
            Button(action: {
                onClose() // Close the window
            }) {
                Text("Close")
                    .fontWeight(.bold)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()

            Spacer()
        }
        .padding()
        .frame(width: 350, height: 500) // Set size of the window
        .background(Color.white)
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding(40) // Keep some padding from the edges of the screen
    }
    
    // Formatter for the price to show two decimal places with a dollar sign
    private var priceFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
    
    // Helper method to validate price input
    private func validatePriceInput(_ input: String) -> String {
        let decimalRegex = "^[0-9]*\\.?[0-9]{0,2}$"  // Only numbers and up to two decimal places
        let priceTest = NSPredicate(format: "SELF MATCHES %@", decimalRegex)
        
        if priceTest.evaluate(with: input) {
            priceWarning = "" // Clear the warning if input is valid
            return input // Return valid input
        } else {
            priceWarning = "Please enter a valid price."
            return "" // Return empty string or previous valid input
        }
    }
    
    // Helper method to validate quantity input (positive integer only)
    private func validateQuantityInput(_ input: String) -> String {
        let integerRegex = "^[0-9]+$" // Only positive integers (no decimals, no negative)
        let quantityTest = NSPredicate(format: "SELF MATCHES %@", integerRegex)
        
        if quantityTest.evaluate(with: input), let value = Int(input), value >= 0 {
            quantityWarning = "" // Clear the warning if input is valid
            return input // Return valid input
        } else {
            quantityWarning = "Please enter a valid quantity (positive integer)."
            return "" // Return empty string or previous valid input
        }
    }
    
    // API call to update item
    func updateItemInBackend() async {
        guard let item = item else {
            print("Item is nil, cannot update.")
            return
        }
        
        let listId = item.listId.uuidString
        let itemId = item.id.uuidString

        do {
            try await GroceryListAPI.updateItem(listId: listId, itemId: itemId, updatedItem: item)
            print("Item updated successfully.")
        } catch {
            print("Failed to update item: \(error)")
        }
    }
}
