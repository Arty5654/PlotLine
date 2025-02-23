//
//  MainGroceryList.swift
//  PlotLine
//
//  Created by Yash Mehta on 2/22/25.
//

import SwiftUI

struct MainGroceryListView: View {
    @State private var groceryLists: [GroceryList] = []
    @State private var showingCreateGroceryList = false
    @State private var newGroceryListName: String = ""
    @State private var showSuccessMessage: Bool = false
    @State private var successMessage: String = ""
    @State private var username: String? = UserDefaults.standard.string(forKey: "loggedInUsername")
    
    // New state for programmatically navigating to the grocery list detail view
    @State private var navigateToDetailView = false
    @State private var createdGroceryListID: String? = nil  // Store the newly created grocery list ID
    @State private var createdGroceryListName: String = ""  // Store the name of the created grocery list

    var body: some View {
        NavigationView {
            VStack {
                Button(action: {
                    showingCreateGroceryList.toggle()
                }) {
                    Text("Create New Grocery List")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                }
                .padding()

                if groceryLists.isEmpty {
                    Text("No grocery lists available.")
                        .font(.title2)
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List(groceryLists) { groceryList in
                        NavigationLink(destination: GroceryListDetailView(groceryList: groceryList)) {
                            Text(groceryList.name)
                        }
                    }
                }

                if showSuccessMessage {
                    Text(successMessage)
                        .foregroundColor(.green)
                        .padding()
                }
            }
            .navigationTitle("Grocery Lists")
            .onAppear {
                fetchGroceryLists()
            }
            .sheet(isPresented: $showingCreateGroceryList) {
                CreateGroceryListView(
                    newGroceryListName: $newGroceryListName,
                    showSuccessMessage: $showSuccessMessage,
                    successMessage: $successMessage,
                    onGroceryListCreated: { newListID in
                        // After creating a new list, set the ID, name, and trigger navigation
                        createdGroceryListID = newListID
                        createdGroceryListName = newGroceryListName
                        navigateToDetailView = true
                        fetchGroceryLists() // Refresh the list after creation (optional)
                    }
                )
            }
        }
    }

    private func fetchGroceryLists() {
        Task {
            do {
                if let loggedInUsername = username {
                    groceryLists = try await GroceryListAPI.getGroceryLists(username: loggedInUsername)
                } else {
                    print("Username not found!")
                }
            } catch {
                print("Failed to load grocery lists: \(error)")
            }
        }
    }
}
