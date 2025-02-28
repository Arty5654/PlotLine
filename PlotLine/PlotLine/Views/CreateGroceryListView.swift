//
//  CreateGroceryListView.swift
//  PlotLine
//
//  Created by Yash Mehta on 2/22/25.
//

import SwiftUI

struct CreateGroceryListView: View {
    @Binding var newGroceryListName: String
    @Environment(\.presentationMode) var presentationMode
    var onGroceryListCreated: () -> Void  // Closure to trigger fetching grocery lists from parent view

    @State private var isShowingAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""

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
            }
            .padding()
            .navigationTitle("Create Grocery List")
            .alert(isPresented: $isShowingAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK")) {
                        // Dismiss the sheet if the list creation was successful
                        if alertTitle == "Success" {
                            self.presentationMode.wrappedValue.dismiss()
                            onGroceryListCreated() // Fetch updated grocery lists in parent
                        }
                    }
                )
            }
        }
        .onAppear {
            newGroceryListName = ""  // Clear the field when the view appears
        }
    }

    func createNewGroceryList() {
        Task {
            do {
                // Create the new grocery list by sending a request to the backend
                let newListID = try await GroceryListAPI.createGroceryList(name: newGroceryListName)

                // Show success alert
                alertTitle = "Success"
                alertMessage = "Grocery list created successfully: \(newGroceryListName)"
                isShowingAlert = true

            } catch {
                // Show error alert
                alertTitle = "Error"
                alertMessage = "Failed to create grocery list."
                isShowingAlert = true
            }
        }
    }
}
