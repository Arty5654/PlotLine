//
//  ActiveGroceryListView.swift
//  PlotLine
//
//  Created by Yash Mehta on 2/27/25.
//

import SwiftUI

struct ActiveGroceryListView: View {
    @State private var groceryLists: [GroceryList] = []
    @State private var showingCreateGroceryList = false
    @State private var showingMealGenerator = false
    @State private var newGroceryListName: String = ""
    @State private var showSuccessMessage: Bool = false
    @State private var successMessage: String = ""
    @State private var username: String? = UserDefaults.standard.string(forKey: "loggedInUsername")
    @State private var isLoading: Bool = false
    @State private var navigateToPreferences = false
    @State private var dietaryRestrictions: DietaryRestrictions?

    var body: some View {
        VStack {
            // Buttons pinned to the top
            VStack(spacing: 20) {
                // Create New Grocery List Button
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
                
                // Generate from Meal Button
                Button(action: {
                    showingMealGenerator.toggle()
                }) {
                    HStack {
                        Image(systemName: "fork.knife")
                        Text("Generate List from Meal")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }

                // Preferences Button
                Button(action: {
                    navigateToPreferencesScreen()
                }) {
                    Text("Preferences")
                        .foregroundColor(.green)
                        .padding()
                        .cornerRadius(5)
                }
            }
            .padding(.top) // Space between the top and buttons
            
            if isLoading {
                ProgressView("Loading Active Lists...")
                    .padding()
            } else if groceryLists.isEmpty {
                Spacer()  // Push content to the middle
                Text("No active grocery lists available.")
                    .font(.title2)
                    .foregroundColor(.gray)
                    .padding()
                Spacer()  // Keep the message centered vertically
            } else {
                // Display the active grocery lists
                List(groceryLists) { groceryList in
                    NavigationLink(destination: GroceryListDetailView(groceryList: groceryList)) {
                        HStack {
                            Text(groceryList.name)
                            
                            if groceryList.isAI == true {
                                Spacer()
                                Image(systemName: "sparkles")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Active Grocery Lists")
        .onAppear {
            Task {
                await fetchGroceryListsAndWait()
                fetchDietaryPreferences()
            }
        }
        .sheet(isPresented: $showingCreateGroceryList) {
            CreateGroceryListView(
                newGroceryListName: $newGroceryListName,
                onGroceryListCreated: {
                    // After the list is created, fetch the updated grocery lists
                    Task {
                        await fetchGroceryListsAndWait()
                    }
                }
            )
        }
        .sheet(isPresented: $showingMealGenerator) {
            GenerateFromMealView(
                onGroceryListCreated: {
                    // After the list is created, fetch the updated grocery lists
                    Task {
                        await fetchGroceryListsAndWait()
                    }
                }
            )
        }
        // Preferences Navigation
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

    // Function to fire off the api to create a new list
    private func createNewGroceryList() {
        guard !newGroceryListName.isEmpty else {
            print("Grocery list name cannot be empty.")
            return
        }

        Task {
            do {
                // Create the new grocery list and get its ID
                let newID = try await GroceryListAPI.createGroceryList(name: newGroceryListName)

                // Fetch the grocery lists and wait until they are loaded
                await fetchGroceryListsAndWait()

                showingCreateGroceryList = false
                newGroceryListName = ""

            } catch {
                print("Failed to create grocery list: \(error)")
            }
        }
    }

    private func fetchGroceryListsAndWait() async {
        isLoading = true

        do {
            if let loggedInUsername = username {
                let lists = try await GroceryListAPI.getGroceryLists(username: loggedInUsername)
                groceryLists = lists
            } else {
                print("Username not found!")
            }

            isLoading = false
        } catch {
            print("Failed to load grocery lists: \(error)")
            isLoading = false
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
    
    private func getLastCreatedGroceryList(listId: String) -> GroceryList? {
        print("List ID checking for in getLast: \(listId)")
        
        // Find the first grocery list with a matching id
        let mostRecentList = groceryLists.first { $0.id == UUID(uuidString: listId)}
        
        print("from get last: \(mostRecentList)")
        return mostRecentList
    }
}
