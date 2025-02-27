//
//  CreateGroceryListView.swift
//  PlotLine
//
//  Created by Yash Mehta on 2/22/25.
//

import SwiftUI

struct CreateGroceryListView: View {
    @Binding var newGroceryListName: String
    @Binding var showSuccessMessage: Bool
    @Binding var successMessage: String
    var onGroceryListCreated: (String) -> Void  // Closure that returns the new grocery list ID

    @Environment(\.presentationMode) var presentationMode

    @State private var createdGroceryListID: String = ""
    @State private var username: String? = UserDefaults.standard.string(forKey: "loggedInUsername")

    var body: some View {
        NavigationStack {
            VStack {
                TextField("Enter Grocery List Name", text: $newGroceryListName)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button(action: {
                    createNewGroceryList()
                }) {
                    Text("Create Grocery List")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                }
                .padding()

                if showSuccessMessage {
                    Text(successMessage)
                        .foregroundColor(.green)
                        .padding()
                }
            }
            .padding()
            .navigationTitle("Create Grocery List")
        }
    }

    func createNewGroceryList() {
        Task {
            do {
                // Create the new grocery list by sending a request to the backend
                let newListID = try await GroceryListAPI.createGroceryList(name: newGroceryListName)

                // Set the created list's ID and trigger navigation
                createdGroceryListID = newListID

                // Show success message
                self.successMessage = "Grocery list created successfully: \(newGroceryListName)"
                self.showSuccessMessage = true
                
                // Dismiss the success message after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.showSuccessMessage = false
                }

                // Call the parent view's closure with the new list's ID
                onGroceryListCreated(newListID)

                // Close the sheet
                self.presentationMode.wrappedValue.dismiss()  // Close the sheet

            } catch {
                // Handle error
                self.successMessage = "Failed to create grocery list."
                self.showSuccessMessage = true

                // Dismiss the error message after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.showSuccessMessage = false
                }
            }
        }
    }
}
