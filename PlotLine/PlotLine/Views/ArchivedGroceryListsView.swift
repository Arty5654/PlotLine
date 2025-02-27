//
//  ArchivedGroceryListsView.swift
//  PlotLine
//
//  Created by Yash Mehta on 2/27/25.
//


import SwiftUI

struct ArchivedGroceryListsView: View {
    @State private var archivedLists: [GroceryList] = []  // List to store archived grocery lists
    @State private var filteredLists: [GroceryList] = []  // Filtered list based on search
    @State private var searchText: String = ""            // State to hold the search query
    @State private var isLoading: Bool = false            // Loading state for fetching the lists
    @State private var errorMessage: String? = nil        // Error message in case of failure
    @State private var showAlert: Bool = false            // State for showing the alert
    @State private var alertMessage: String = ""          // Message to display in the alert
    
    let username: String // Username of the user whose archived lists are being fetched
    
    var body: some View {
        VStack {
            // Search Bar pinned to the top
            HStack {
                TextField("Search by name", text: $searchText)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: searchText) { newValue in
                        filterLists()
                    }
            }
            .padding(.horizontal)

            if isLoading {
                ProgressView("Loading Archived Lists...")
                    .padding()
            } else if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            } else if filteredLists.isEmpty {
                // This text will be centered when the list is empty
                Spacer()
                Text("No archived grocery lists found.")
                    .font(.title2)
                    .foregroundColor(.gray)
                Spacer()
            } else {
                // Display the filtered lists in a list
                List {
                    ForEach(filteredLists) { groceryList in
                        HStack {
                            Text(groceryList.name) // Display list name
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Button(action: {
                                restoreList(groceryList)
                            }) {
                                Text("Restore")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle("Archived Grocery Lists")
        .onAppear {
            fetchArchivedGroceryLists()
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Restore Status"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // Fetch archived grocery lists
    func fetchArchivedGroceryLists() {
        isLoading = true
        GroceryListAPI.getArchivedGroceryLists(username: username) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let lists):
                    archivedLists = lists
                    filteredLists = lists // Initially set filtered lists to all archived lists
                case .failure(let error):
                    errorMessage = "Failed to load archived lists: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // Filter the lists based on search text
    func filterLists() {
        if searchText.isEmpty {
            filteredLists = archivedLists // If search text is empty, show all lists
        } else {
            filteredLists = archivedLists.filter { $0.name.lowercased().contains(searchText.lowercased()) }
        }
    }
    
    // Restore the grocery list
    func restoreList(_ groceryList: GroceryList) {
        GroceryListAPI.restoreGroceryList(username: username, groceryList: groceryList) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let message):
                    // Show success message or handle UI updates as needed
                    alertMessage = "Successfully restored the grocery list: \(groceryList.name)"
                    showAlert = true
                    fetchArchivedGroceryLists() // Refresh the list after restoring
                case .failure(let error):
                    alertMessage = "Failed to restore grocery list: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
}
