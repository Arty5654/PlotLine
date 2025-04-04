//
//  GenerateFromMealView.swift
//  PlotLine
//
//  Created by Yash Mehta on 4/3/25.
//

import SwiftUI

struct GenerateFromMealView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var mealName: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    @State private var dietaryMessage: String? = nil
    @State private var showDietaryInfo: Bool = false
    
    var onGroceryListCreated: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Generate a Grocery List From a Meal")
                    .font(.headline)
                    .padding(.top)
                
                TextField("Enter meal name (e.g., Lasagna)", text: $mealName)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Text("We'll create a grocery list with all the ingredients you need, adapted to your dietary preferences!")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button(action: {
                    generateGroceryList()
                }) {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Generate Grocery List")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(mealName.isEmpty ? Color.gray : Color.green)
                            .cornerRadius(10)
                    }
                }
                .disabled(mealName.isEmpty || isGenerating)
                .padding()
                
                Spacer()
            }
            .padding()
            .navigationTitle("AI Meal Generator")
            .navigationBarItems(
                trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .alert(isPresented: $showError, content: {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage ?? "An unknown error occurred."),
                    dismissButton: .default(Text("OK"))
                )
            })
            .alert(isPresented: $showDietaryInfo, content: {
                Alert(
                    title: Text("About your request"),
                    message: Text(dietaryMessage ?? ""),
                    dismissButton: .default(Text("OK")) {
                        // On dismiss of this alert, we should also dismiss the sheet and refresh the lists
                        onGroceryListCreated()
                        presentationMode.wrappedValue.dismiss()
                    }
                )
            })
        }
    }

    private func generateGroceryList() {
        guard !mealName.isEmpty else { return }

        isGenerating = true

        Task {
            do {
                // Call the API function to generate a grocery list from the meal name
                let result = try await GroceryListAPI.generateGroceryListFromMeal(mealName: mealName)
                
                DispatchQueue.main.async {
                    isGenerating = false
                    
                    // Check if the result starts with "INCOMPATIBLE:" which indicates the meal
                    // cannot be made with the user's dietary restrictions
                    if let incompatiblePrefix = result.range(of: "INCOMPATIBLE:") {
                        // Parse the JSON to extract the reason
                        let json = String(result[incompatiblePrefix.upperBound...])
                        
                        print(json)
                        
                        if let data = json.data(using: .utf8),
                           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let reason = dict["reason"] as? String {
                            
                            dietaryMessage = "This meal cannot be made with your dietary restrictions: \n\n \(reason)"
                            showDietaryInfo = true
                        } else {
                            dietaryMessage = "This meal is not compatible with your dietary restrictions."
                            showDietaryInfo = true
                        }
                    }
                    // Check if the result contains a modification message
                    else if let modPrefix = result.range(of: "MODIFIED:") {
                        let json = String(result[modPrefix.upperBound...])
                        
                        if let data = json.data(using: .utf8),
                            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            let modifications = dict["modifications"] as? String,
                            let listId = dict["listId"] as? String {
                            
                            dietaryMessage = "We've adjusted this recipe to match your dietary preferences: \n\n \(modifications)"
                            showDietaryInfo = true
                        } else {
                            // If we couldn't parse the modification, still created the list
                            onGroceryListCreated()
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    // Standard success case
                    else {
                        // Just created the list successfully with no modifications
                        onGroceryListCreated()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            } catch {
                // Handle any errors
                DispatchQueue.main.async {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

#Preview {
    GenerateFromMealView(onGroceryListCreated: {})
}
