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

    @State private var navigateToPreferences = false  // Flag to control navigation to preferences view
    @State private var dietaryRestrictions: DietaryRestrictions? // Store dietary restrictions here

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
                Button(action: {
                    navigateToPreferencesScreen()
                }) {
                    Text("Preferences")
                        .foregroundColor(.green)
                        .padding()
                        .cornerRadius(5)
                }

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
                fetchDietaryPreferences() // Fetch dietary preferences when the view appears
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
                        if let validUUID = UUID(uuidString: newListID) {
                            groceryLists.append(GroceryList(id: validUUID, name: newGroceryListName, items: [], username: username ?? ""))
                        } else {
                            print("Invalid UUID format for new list ID")
                        }
                        navigateToDetailView = true
                        fetchGroceryLists()
                    }
                )
            }
            // Navigate to DietaryPreferencesView when the flag is set
            .background(
                NavigationLink(
                    destination: DietaryPreferencesView(dietaryRestrictions: $dietaryRestrictions, onClose: {
                        navigateToPreferences = false // Action to close the view
                    }),
                    isActive: $navigateToPreferences
                ) {
                    EmptyView()
                }
            )
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

    private func fetchDietaryPreferences() {
        Task {
            if let loggedInUsername = username {
                DietaryRestrictionsAPI.shared.getDietaryRestrictions(username: loggedInUsername) { result in
                    switch result {
                    case .success(let restrictions):
                        dietaryRestrictions = restrictions // Assign result here
                    case .failure(let error):
                        print("Failed to load dietary preferences: \(error.localizedDescription)")
                        
                        // If there is an error (e.g., no data), create a new object with defaults
                        dietaryRestrictions = DietaryRestrictions(
                            username: loggedInUsername,
                            lactoseIntolerant: false,
                            vegetarian: false,
                            vegan: false,
                            glutenFree: false,
                            kosher: false,
                            dairyFree: false,
                            nutFree: false
                        )
                        print("Loaded default dietary restrictions.")
                    }
                }
            } else {
                print("Username not found!")
            }
        }
    }


    private func navigateToPreferencesScreen() {
        // Only navigate if dietaryRestrictions is not nil
        if dietaryRestrictions != nil {
            navigateToPreferences = true
        } else {
            print("Dietary restrictions not available.")
        }
    }
}
